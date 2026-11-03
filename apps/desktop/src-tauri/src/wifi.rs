//! Joins the camera's Wi-Fi network after the Bluetooth hand-off: nmcli on Linux, netsh on Windows.
//! The camera's network may be hidden. The password is never logged; when joining fails, the UI shows the
//! network name and password so the user can join by hand.

use serde::Serialize;
use tauri::{AppHandle, Emitter};

/// An error for the UI, shaped like `bluetooth::BtError`.
#[derive(Debug, Serialize)]
pub struct WifiError {
    message: &'static str,
    detail: Option<String>,
}

const JOIN_FAILED: &str = "Couldn't join the camera's network.";
#[cfg(target_os = "linux")]
const NO_NMCLI: &str = "NetworkManager (nmcli) isn't installed, so the network can't be joined automatically.";
#[cfg(not(any(target_os = "linux", target_os = "windows")))]
const UNSUPPORTED: &str = "Joining the network automatically isn't supported on this system.";

/// Joins the network; returns once the computer is on it (or gave up).
#[tauri::command]
pub async fn wifi_join(ssid: String, password: String, app: AppHandle) -> Result<(), WifiError> {
    let _ = app.emit("bluetooth", serde_json::json!({ "step": "joining", "ssid": ssid }));
    tauri::async_runtime::spawn_blocking(move || join(&ssid, &password))
        .await
        .map_err(|e| WifiError { message: JOIN_FAILED, detail: Some(e.to_string()) })?
}

/// Tool output, with the password masked in case a tool echoes it back.
#[cfg(any(target_os = "linux", target_os = "windows"))]
fn output_text(output: &std::process::Output, password: &str) -> String {
    let text = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
    let text = if password.is_empty() { text } else { text.replace(password, "•••") };
    text.trim().to_string()
}

#[cfg(target_os = "linux")]
fn join(ssid: &str, password: &str) -> Result<(), WifiError> {
    use std::process::Command;
    // nmcli waits until the connection is up (or failed).
    let output = Command::new("nmcli")
        .args(["--wait", "45", "device", "wifi", "connect", ssid, "password", password, "hidden", "yes"])
        .output()
        .map_err(|e| match e.kind() {
            std::io::ErrorKind::NotFound => WifiError { message: NO_NMCLI, detail: None },
            _ => WifiError { message: JOIN_FAILED, detail: Some(e.to_string()) },
        })?;
    if output.status.success() {
        Ok(())
    } else {
        Err(WifiError { message: JOIN_FAILED, detail: Some(output_text(&output, password)) })
    }
}

#[cfg(target_os = "windows")]
fn join(ssid: &str, password: &str) -> Result<(), WifiError> {
    use std::os::windows::process::CommandExt;
    use std::process::Command;
    use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let failed = |detail: String| WifiError { message: JOIN_FAILED, detail: Some(detail) };
    let netsh = |args: &[String]| {
        let mut command = Command::new("netsh");
        command.creation_flags(CREATE_NO_WINDOW);
        // netsh wants name="value" as is, which Rust's own argument quoting would mangle.
        for arg in args {
            command.raw_arg(arg);
        }
        command.output().map_err(|e| failed(e.to_string()))
    };

    // A WPA2 profile for a hidden network. The file holds the password, so it only lives for the netsh call.
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or_default();
    let path = std::env::temp_dir().join(format!("ferry-wlan-{}-{stamp}.xml", std::process::id()));
    std::fs::write(&path, wlan_profile(ssid, password)).map_err(|e| failed(e.to_string()))?;
    let added = netsh(&["wlan".into(), "add".into(), "profile".into(), format!("filename=\"{}\"", path.display()), "user=current".into()]);
    let _ = std::fs::remove_file(&path);
    let added = added?;
    if !added.status.success() {
        return Err(failed(output_text(&added, password)));
    }

    let quoted = ssid.replace('"', "");
    let connect = netsh(&["wlan".into(), "connect".into(), format!("name=\"{quoted}\""), format!("ssid=\"{quoted}\"")])?;
    if !connect.status.success() {
        return Err(failed(output_text(&connect, password)));
    }

    // `netsh wlan connect` returns before the connection is up; wait until an interface reports the network.
    // The labels are localized, but "SSID" isn't.
    let deadline = Instant::now() + Duration::from_secs(20);
    while Instant::now() < deadline {
        if let Ok(output) = netsh(&["wlan".into(), "show".into(), "interfaces".into()]) {
            let text = String::from_utf8_lossy(&output.stdout);
            let on_it = text.lines().any(|line| {
                line.split_once(':').is_some_and(|(key, value)| key.trim() == "SSID" && value.trim() == ssid)
            });
            if on_it {
                // Give DHCP a moment before ferryctl looks for the camera.
                std::thread::sleep(Duration::from_secs(2));
                return Ok(());
            }
        }
        std::thread::sleep(Duration::from_millis(500));
    }
    Err(failed("Windows didn't connect to the network in time".into()))
}

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
fn join(_ssid: &str, _password: &str) -> Result<(), WifiError> {
    Err(WifiError { message: UNSUPPORTED, detail: None })
}

#[cfg(any(target_os = "windows", test))]
fn wlan_profile(ssid: &str, password: &str) -> String {
    let ssid = xml_escape(ssid);
    let password = xml_escape(password);
    format!(
        r#"<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>{ssid}</name>
  <SSIDConfig>
    <SSID><name>{ssid}</name></SSID>
    <nonBroadcast>true</nonBroadcast>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA2PSK</authentication>
        <encryption>AES</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>{password}</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>
"#
    )
}

#[cfg(any(target_os = "windows", test))]
fn xml_escape(text: &str) -> String {
    text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;").replace('\'', "&apos;")
}

#[cfg(test)]
mod tests {
    #[test]
    fn profile_escapes() {
        let xml = super::wlan_profile("FUJIFILM-X-T5-<1>", "a&b\"c");
        assert!(xml.contains("<name>FUJIFILM-X-T5-&lt;1&gt;</name>"));
        assert!(xml.contains("<keyMaterial>a&amp;b&quot;c</keyMaterial>"));
        assert!(xml.contains("<nonBroadcast>true</nonBroadcast>"));
    }
}
