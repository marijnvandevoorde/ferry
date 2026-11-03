//! The desktop shell: runs `ferryctl serve` as a sidecar and relays its JSON lines to the UI.
//! All camera logic lives in ferryctl (FerryKit); see docs/adr/0001-windows-linux-app.md.

mod bluetooth;
mod wifi;

use std::io::Write;
use std::sync::Mutex;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, State, WindowEvent};
use tauri_plugin_shell::process::{CommandChild, CommandEvent};
use tauri_plugin_shell::ShellExt;

#[derive(Default)]
struct Sidecar(Mutex<Option<CommandChild>>);

/// Sends one command (a JSON object) to ferryctl.
#[tauri::command]
fn send(command: serde_json::Value, sidecar: State<Sidecar>) -> Result<(), String> {
    let mut guard = sidecar.0.lock().map_err(|e| e.to_string())?;
    let child = guard.as_mut().ok_or("ferryctl is not running")?;
    let mut line = command.to_string();
    line.push('\n');
    child.write(line.as_bytes()).map_err(|e| e.to_string())
}

/// The folder that holds the connection log.
#[tauri::command]
fn log_dir(app: AppHandle) -> Result<String, String> {
    let dir = app.path().app_log_dir().map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.to_string_lossy().into_owned())
}

/// Appends to the connection log on disk (ferry.log in the app's log folder), so a dropped connection can be looked
/// into afterwards. Starts over past 5 MB, keeping the previous file as ferry.old.log.
fn append_log(app: &AppHandle, line: &str) {
    let Ok(dir) = app.path().app_log_dir() else { return };
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join("ferry.log");
    if std::fs::metadata(&path).map(|m| m.len() > 5_000_000).unwrap_or(false) {
        let _ = std::fs::rename(&path, dir.join("ferry.old.log"));
    }
    if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(file, "[{}] {}", chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f"), line);
    }
}

/// The line an event adds to the log file, if any (progress and thumbnails would drown the rest).
fn log_line(event: &serde_json::Value) -> Option<String> {
    let text = |key: &str| event.get(key).and_then(|v| v.as_str()).unwrap_or("").to_string();
    match event.get("event")?.as_str()? {
        "log" => Some(text("line")),
        "error" => Some(format!("Error: {}", text("message"))),
        "status" => Some(format!("Status: {} {} {}", text("phase"), text("camera"), text("address")).trim_end().to_string()),
        "done" => Some(format!("Import done: {}", event)),
        _ => None,
    }
}

fn start_sidecar(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let mut args = vec!["serve".to_string()];
    // FERRY_HOST points the app at a camera emulator during development.
    if let Ok(host) = std::env::var("FERRY_HOST") {
        args.insert(0, host);
        args.insert(0, "--host".into());
    }
    let (mut events, child) = app.shell().sidecar("ferryctl")?.args(args).spawn()?;
    app.state::<Sidecar>().0.lock().unwrap().replace(child);

    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let mut pending = Vec::new();
        while let Some(event) = events.recv().await {
            match event {
                CommandEvent::Stdout(bytes) => {
                    // Output can arrive in arbitrary chunks; forward complete lines.
                    pending.extend_from_slice(&bytes);
                    while let Some(pos) = pending.iter().position(|&b| b == b'\n') {
                        let line: Vec<u8> = pending.drain(..=pos).collect();
                        if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&line) {
                            if let Some(line) = log_line(&value) {
                                append_log(&app, &line);
                            }
                            let _ = app.emit("ferryctl", value);
                        }
                    }
                }
                CommandEvent::Stderr(bytes) => {
                    let line = String::from_utf8_lossy(&bytes).trim().to_string();
                    append_log(&app, &line);
                    let _ = app.emit("ferryctl", serde_json::json!({ "event": "log", "line": line }));
                }
                CommandEvent::Terminated(status) => {
                    let message = format!("ferryctl stopped ({:?})", status.code);
                    append_log(&app, &message);
                    let _ = app.emit("ferryctl", serde_json::json!({ "event": "error", "message": message }));
                    break;
                }
                _ => {}
            }
        }
    });
    Ok(())
}

fn show_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--minimized"]),
        ))
        .manage(Sidecar::default())
        .manage(bluetooth::Bluetooth::default())
        .invoke_handler(tauri::generate_handler![
            send,
            log_dir,
            bluetooth::bluetooth_saved,
            bluetooth::bluetooth_scan,
            bluetooth::bluetooth_connect,
            bluetooth::bluetooth_disconnect,
            bluetooth::bluetooth_forget,
            wifi::wifi_join,
        ])
        .setup(|app| {
            start_sidecar(app.handle())?;

            let open = MenuItem::with_id(app, "open", "Open Ferry", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &quit])?;
            TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Ferry")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "open" => show_main_window(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;

            if std::env::args().any(|a| a == "--minimized") {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.hide();
                }
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            // Closing the window keeps the app in the tray, so it can keep watching for the camera.
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .build(tauri::generate_context!())
        .expect("error while building the app")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                if let Some(child) = app.state::<Sidecar>().0.lock().unwrap().take() {
                    let _ = child.kill();
                }
            }
        });
}
