//! Bluetooth hand-off for newer Fujifilm cameras (X-T30/X-T4 and later). Bluetooth is only used to get onto the
//! camera's Wi-Fi: pair over BLE, ask the camera to start its network, read the network name and password, and
//! hand those to the UI, which joins the network (see wifi.rs) and lets fujictl connect as usual.
//!
//! The GATT sequence follows libfuji's lib/bluetooth.c (MIT); docs/bluetooth.md has the background. None of this
//! has been tried against a real camera yet.
//!
//! The OS bond: newer cameras protect their pairing service with an encrypted link, so the first pairing needs a
//! Bluetooth bond between computer and camera. btleplug can't create one itself. Windows and BlueZ (with the
//! desktop's pairing agent running) normally start pairing on their own when an encrypted characteristic is read;
//! when that doesn't happen, the read fails and we ask the user to pair the camera in the OS Bluetooth settings
//! (with the camera in pairing mode) and try again.

use std::path::PathBuf;
use std::time::Duration;

use btleplug::api::{Central, Characteristic, Manager as _, Peripheral as _, PeripheralProperties, ScanFilter, WriteType};
use btleplug::platform::{Adapter, Manager, Peripheral};
use chrono::{Datelike, Local, Timelike};
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager as _, State};
use tokio::sync::{mpsc, Mutex};
use tokio::time::{sleep, timeout};
use uuid::{uuid, Uuid};

/// The name the camera shows for this computer.
const CLIENT_NAME: &str = "Ferry";

/// Manufacturer data of a camera in pairing mode: Fujifilm's company id, then type 0x02 and a 4-byte token.
const FUJIFILM: u16 = 0x04d8;
const ADV_PAIRING: u8 = 0x02;

// Older Bluetooth cameras: the token from the advertisement unlocks the connection.
const PAIR_SERVICE: Uuid = uuid!("91f1de68-dff6-466e-8b65-ff13b0f16fb8");
const PAIR_TOKEN: Uuid = uuid!("aba356eb-9633-4e60-b73f-f52516dbd671");
const CLIENT_NAME_CHR: Uuid = uuid!("85b9163e-62d1-49ff-a6f5-054b4630d4a1");
// Newer cameras: a bonded link, and a status word to acknowledge.
const SECURE_PAIR_SERVICE: Uuid = uuid!("123d8f06-62a1-4935-9322-833c531ee225");
const SECURE_STATUS: Uuid = uuid!("f557d96b-8284-4667-8793-b971c1deca2a");

const CONF_SERVICE: Uuid = uuid!("4c0020fe-f3b6-40de-acc9-77d129067b14");
const WIFI_STATUS: Uuid = uuid!("a68e3f66-0fcc-4395-8d4c-aa980b5877fa");
const IND2: Uuid = uuid!("bd17ba04-b76b-4892-a545-b73ba1f74dae");
const TIME_REQUEST: Uuid = uuid!("f9150137-5d40-4801-a8dc-f7fc5b01da50");
const IND3: Uuid = uuid!("049ec406-ef75-4205-a390-08fe209c51f0");
const GEOTAG_REQUEST: Uuid = uuid!("ad06c7b7-f41a-46f4-a29a-712055319122");
const NOT6: Uuid = uuid!("e6692c5c-b7cd-44f4-95fc-eda07ce32560");

const NOT3_SERVICE: Uuid = uuid!("804daa8e-ffeb-4ab3-8e75-6edd7303208d");
const NOT3: Uuid = uuid!("7170fd5a-56d9-4c19-b043-7a7047d8e1a0");

const WIFI_SERVICE: Uuid = uuid!("4e941240-d01d-46b9-a5ea-67636806830b");
const WIFI_SSID: Uuid = uuid!("bf6dc9cf-3606-4ec9-a4c8-d77576e93ea4");
const WIFI_PASSWORD: Uuid = uuid!("e809256a-915c-4967-92e8-53b7d4cad213");
const NOT5: Uuid = uuid!("75823784-fbb7-4b71-abae-cd9a34072e3c");
const NOT7: Uuid = uuid!("aab609c4-94dd-4d89-bc60-665d5090b828");
const NOT8: Uuid = uuid!("2a125640-706d-4dd1-b420-c0f4ab93c361");
const NOT9: Uuid = uuid!("82a9f452-c5ce-4ef5-8203-3fc9a47f8171");
const NOT10: Uuid = uuid!("deef7187-3f43-4364-9e22-11a8c8a15951");
const GEOTAG_INTERVAL: Uuid = uuid!("c95d91ae-b247-4d6d-8661-7dd5d6a0f85b");

const TIME_SERVICE: Uuid = uuid!("e872b11f-d526-4ae1-9bb4-89a99d48fa59");
const TIME: Uuid = uuid!("b9bfd37f-ccad-4d36-a1ee-018e792b3edf");

const SHUTTER_SERVICE: Uuid = uuid!("6514eb81-4e8f-458d-aa2a-e691336cdfac");
const START_WIFI: Uuid = uuid!("600655e6-3637-42f1-8fb2-44efc5c63b13");

/// What the older cameras' app subscribes to.
const SUBSCRIPTIONS_OLD: &[(Uuid, Uuid)] = &[
    (WIFI_SERVICE, WIFI_SSID),
    (CONF_SERVICE, WIFI_STATUS),
    (CONF_SERVICE, IND2),
    (CONF_SERVICE, TIME_REQUEST),
    (CONF_SERVICE, GEOTAG_REQUEST),
    (CONF_SERVICE, IND3),
];

/// What the newer cameras' app subscribes to; the camera seems to expect all of these before it starts its Wi-Fi.
const SUBSCRIPTIONS_NEW: &[(Uuid, Uuid)] = &[
    (CONF_SERVICE, WIFI_STATUS),
    (CONF_SERVICE, IND2),
    (CONF_SERVICE, TIME_REQUEST),
    (CONF_SERVICE, GEOTAG_REQUEST),
    (NOT3_SERVICE, NOT3),
    (WIFI_SERVICE, WIFI_SSID),
    (WIFI_SERVICE, NOT5),
    (CONF_SERVICE, NOT6),
    (WIFI_SERVICE, NOT7),
    (WIFI_SERVICE, NOT8),
    (WIFI_SERVICE, NOT9),
    (WIFI_SERVICE, NOT10),
    (WIFI_SERVICE, GEOTAG_INTERVAL),
];

const SCAN_TIME: Duration = Duration::from_secs(6);
const FIND_TIME: Duration = Duration::from_secs(15);
const CONNECT_TIME: Duration = Duration::from_secs(20);
const WIFI_STATUS_TIME: Duration = Duration::from_secs(5);

/// An error for the UI: `message` is fixed English text (the UI translates it), `detail` is what the OS said.
#[derive(Debug, Serialize)]
pub struct BtError {
    message: &'static str,
    detail: Option<String>,
}

impl BtError {
    fn new(message: &'static str) -> Self {
        Self { message, detail: None }
    }
    fn with(message: &'static str, detail: impl ToString) -> Self {
        Self { message, detail: Some(detail.to_string()) }
    }
}

const NO_ADAPTER: &str = "No Bluetooth adapter found. Turn Bluetooth on and try again.";
const UNAVAILABLE: &str = "Bluetooth isn't available on this computer.";
const NOT_FOUND: &str = "Couldn't find the camera. Make sure it's on and nearby, then try again.";
const NOT_PAIRING: &str = "The camera isn't in pairing mode anymore. Choose Pairing Registration on the camera and search again.";
const CONNECT_FAILED: &str = "Couldn't connect to the camera over Bluetooth.";
const NOT_BONDED: &str = "This computer isn't paired with the camera yet. Put the camera in pairing mode, pair it in your computer's Bluetooth settings, then try again.";
const REJECTED: &str = "The camera didn't accept this computer. Pair it again from the camera's Bluetooth menu.";
const UNSUPPORTED: &str = "This camera can't share its Wi-Fi over Bluetooth.";
const BUSY: &str = "The camera is busy. Switch it to shooting mode and try again.";
const LOST: &str = "The camera stopped answering over Bluetooth. Try again.";

/// A camera from a scan, or a saved one that wasn't seen.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Camera {
    id: String,
    name: String,
    /// In pairing mode right now, so it can be paired for the first time.
    pairing: bool,
    /// Paired before; it can connect without pairing mode.
    saved: bool,
    /// Seen in this scan.
    nearby: bool,
}

/// A paired camera, kept in bluetooth-cameras.json in the app's config folder.
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct SavedCamera {
    id: String,
    address: String,
    name: String,
    /// The pairing token from the advertisement, hex.
    token: String,
}

/// The camera's Wi-Fi network. Never logged.
#[derive(Serialize)]
pub struct Credentials {
    ssid: String,
    password: String,
}

/// The Bluetooth state: one operation at a time.
#[derive(Default)]
pub struct Bluetooth(Mutex<Inner>);

#[derive(Default)]
struct Inner {
    adapter: Option<Adapter>,
    /// The camera stays connected over Bluetooth while its Wi-Fi is in use, the way Fujifilm's app does it.
    link: Option<Link>,
}

struct Link {
    peripheral: Peripheral,
    listener: tauri::async_runtime::JoinHandle<()>,
}

impl Inner {
    async fn adapter(&mut self) -> Result<Adapter, BtError> {
        if let Some(adapter) = &self.adapter {
            return Ok(adapter.clone());
        }
        let manager = Manager::new().await.map_err(|e| BtError::with(UNAVAILABLE, e))?;
        let adapter = manager
            .adapters()
            .await
            .map_err(|e| BtError::with(UNAVAILABLE, e))?
            .into_iter()
            .next()
            .ok_or(BtError::new(NO_ADAPTER))?;
        self.adapter = Some(adapter.clone());
        Ok(adapter)
    }

    async fn drop_link(&mut self) {
        if let Some(link) = self.link.take() {
            link.listener.abort();
            let _ = link.peripheral.disconnect().await;
        }
    }
}

// MARK: - Saved cameras

fn saved_path(app: &AppHandle) -> Option<PathBuf> {
    app.path().app_config_dir().ok().map(|dir| dir.join("bluetooth-cameras.json"))
}

fn load_saved(app: &AppHandle) -> Vec<SavedCamera> {
    saved_path(app)
        .and_then(|path| std::fs::read(path).ok())
        .and_then(|data| serde_json::from_slice(&data).ok())
        .unwrap_or_default()
}

fn store_saved(app: &AppHandle, cameras: &[SavedCamera]) {
    let Some(path) = saved_path(app) else { return };
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Ok(data) = serde_json::to_vec_pretty(cameras) {
        let _ = std::fs::write(path, data);
    }
}

fn matches(saved: &SavedCamera, peripheral: &Peripheral) -> bool {
    saved.id == peripheral.id().to_string() || (saved.address == peripheral.address().to_string() && !is_zero(&saved.address))
}

/// macOS hides addresses (they read 00:00:00:00:00:00); don't match on those.
fn is_zero(address: &str) -> bool {
    address.chars().all(|c| c == '0' || c == ':')
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn unhex(text: &str) -> Option<[u8; 4]> {
    let bytes: Vec<u8> = (0..text.len())
        .step_by(2)
        .map(|i| text.get(i..i + 2).and_then(|pair| u8::from_str_radix(pair, 16).ok()))
        .collect::<Option<_>>()?;
    bytes.try_into().ok()
}

// MARK: - Scanning

/// The token a camera in pairing mode advertises.
fn pairing_token(properties: &PeripheralProperties) -> Option<[u8; 4]> {
    match properties.manufacturer_data.get(&FUJIFILM)?.as_slice() {
        [ADV_PAIRING, a, b, c, d, ..] => Some([*a, *b, *c, *d]),
        _ => None,
    }
}

fn display_name(properties: Option<&PeripheralProperties>) -> String {
    properties
        .and_then(|p| p.local_name.clone().or_else(|| p.advertisement_name.clone()))
        .filter(|name| !name.trim().is_empty())
        .unwrap_or_else(|| "FUJIFILM".into())
}

fn progress(app: &AppHandle, step: &str) {
    let _ = app.emit("bluetooth", serde_json::json!({ "step": step }));
}

/// Paired cameras, without scanning.
#[tauri::command]
pub fn bluetooth_saved(app: AppHandle) -> Vec<Camera> {
    load_saved(&app)
        .into_iter()
        .map(|s| Camera { id: s.id, name: s.name, pairing: false, saved: true, nearby: false })
        .collect()
}

/// Scans for a few seconds; returns cameras in pairing mode and saved cameras (seen or not).
#[tauri::command]
pub async fn bluetooth_scan(app: AppHandle, bluetooth: State<'_, Bluetooth>) -> Result<Vec<Camera>, BtError> {
    let mut inner = bluetooth.0.lock().await;
    let adapter = inner.adapter().await?;
    progress(&app, "scanning");
    adapter.start_scan(ScanFilter::default()).await.map_err(|e| BtError::with(UNAVAILABLE, e))?;
    sleep(SCAN_TIME).await;
    let peripherals = adapter.peripherals().await.unwrap_or_default();
    let _ = adapter.stop_scan().await;

    let saved = load_saved(&app);
    let mut cameras = Vec::new();
    for peripheral in peripherals {
        let properties = peripheral.properties().await.ok().flatten();
        let pairing = properties.as_ref().and_then(pairing_token).is_some();
        let known = saved.iter().find(|s| matches(s, &peripheral));
        if !pairing && known.is_none() {
            continue;
        }
        cameras.push(Camera {
            id: known.map(|s| s.id.clone()).unwrap_or_else(|| peripheral.id().to_string()),
            name: known.map(|s| s.name.clone()).unwrap_or_else(|| display_name(properties.as_ref())),
            pairing,
            saved: known.is_some(),
            nearby: true,
        });
    }
    for s in saved {
        if !cameras.iter().any(|c| c.id == s.id) {
            cameras.push(Camera { id: s.id, name: s.name, pairing: false, saved: true, nearby: false });
        }
    }
    Ok(cameras)
}

/// Scans until the camera shows up.
async fn find(adapter: &Adapter, id: &str, saved: Option<&SavedCamera>) -> Result<Peripheral, BtError> {
    let is_it = |p: &Peripheral| p.id().to_string() == id || saved.is_some_and(|s| matches(s, p));
    adapter.start_scan(ScanFilter::default()).await.map_err(|e| BtError::with(UNAVAILABLE, e))?;
    let found = timeout(FIND_TIME, async {
        loop {
            if let Some(p) = adapter.peripherals().await.unwrap_or_default().into_iter().find(is_it) {
                return p;
            }
            sleep(Duration::from_millis(500)).await;
        }
    })
    .await;
    let _ = adapter.stop_scan().await;
    found.map_err(|_| BtError::new(NOT_FOUND))
}

// MARK: - Connecting

/// Pairs with (or reconnects to) a camera and gets its Wi-Fi network. Progress goes out as `bluetooth` events.
#[tauri::command]
pub async fn bluetooth_connect(id: String, app: AppHandle, bluetooth: State<'_, Bluetooth>) -> Result<Credentials, BtError> {
    let mut inner = bluetooth.0.lock().await;
    inner.drop_link().await;
    let adapter = inner.adapter().await?;
    let mut saved = load_saved(&app);
    let known = saved.iter().position(|s| s.id == id);

    progress(&app, "searching");
    let peripheral = find(&adapter, &id, known.map(|i| &saved[i])).await?;
    let properties = peripheral.properties().await.ok().flatten();
    // A camera in pairing mode gets paired afresh, even when it was saved before.
    let token = match (properties.as_ref().and_then(pairing_token), known) {
        (Some(token), _) => token,
        (None, Some(i)) => unhex(&saved[i].token).unwrap_or_default(),
        (None, None) => return Err(BtError::new(NOT_PAIRING)),
    };

    progress(&app, "connecting");
    match timeout(CONNECT_TIME, peripheral.connect()).await {
        Ok(Ok(())) => {}
        Ok(Err(e)) => return Err(BtError::with(CONNECT_FAILED, e)),
        Err(_) => return Err(BtError::new(CONNECT_FAILED)),
    }

    // Notifications: the camera asks for the time, and reports whether its Wi-Fi started.
    let (status_tx, status_rx) = mpsc::unbounded_channel();
    let listener = match listen(&peripheral, status_tx).await {
        Ok(listener) => listener,
        Err(e) => {
            let _ = peripheral.disconnect().await;
            return Err(e);
        }
    };
    let link = Link { peripheral: peripheral.clone(), listener };

    match hand_off(&app, &peripheral, token, status_rx).await {
        Ok(credentials) => {
            let camera = SavedCamera {
                id: peripheral.id().to_string(),
                address: peripheral.address().to_string(),
                name: known.map(|i| saved[i].name.clone()).unwrap_or_else(|| display_name(properties.as_ref())),
                token: hex(&token),
            };
            saved.retain(|s| s.id != id && s.id != camera.id);
            saved.insert(0, camera);
            store_saved(&app, &saved);
            inner.link = Some(link);
            Ok(credentials)
        }
        Err(e) => {
            link.listener.abort();
            let _ = link.peripheral.disconnect().await;
            Err(e)
        }
    }
}

async fn listen(peripheral: &Peripheral, status: mpsc::UnboundedSender<u8>) -> Result<tauri::async_runtime::JoinHandle<()>, BtError> {
    peripheral.discover_services().await.map_err(|e| BtError::with(LOST, e))?;
    let mut notifications = peripheral.notifications().await.map_err(|e| BtError::with(LOST, e))?;
    let time = characteristic(peripheral, TIME_SERVICE, TIME);
    let peripheral = peripheral.clone();
    Ok(tauri::async_runtime::spawn(async move {
        while let Some(n) = notifications.next().await {
            if n.uuid == TIME_REQUEST {
                if let Some(time) = &time {
                    let _ = peripheral.write(time, &camera_time(), WriteType::WithResponse).await;
                }
            } else if n.uuid == WIFI_STATUS {
                if let Some(&value) = n.value.first() {
                    let _ = status.send(value);
                }
            }
        }
    }))
}

/// The pairing handshake and the Wi-Fi request, on a connected camera.
async fn hand_off(
    app: &AppHandle,
    peripheral: &Peripheral,
    token: [u8; 4],
    mut status: mpsc::UnboundedReceiver<u8>,
) -> Result<Credentials, BtError> {
    progress(app, "pairing");
    if let Some(pair) = characteristic(peripheral, PAIR_SERVICE, PAIR_TOKEN) {
        // Older cameras: the token is the key.
        write(peripheral, &pair, &token).await.map_err(|e| BtError::with(REJECTED, e.detail.unwrap_or_default()))?;
        send_client_name(peripheral, PAIR_SERVICE).await?;
        subscribe(peripheral, SUBSCRIPTIONS_OLD).await;
    } else {
        // Newer cameras: reading the status needs a bonded (encrypted) link. This is where Windows or BlueZ may
        // start pairing on their own; if they don't, the read fails and the user pairs in the OS settings.
        let status_chr = characteristic(peripheral, SECURE_PAIR_SERVICE, SECURE_STATUS).ok_or(BtError::new(UNSUPPORTED))?;
        let mut word = peripheral.read(&status_chr).await.map_err(|e| BtError::with(NOT_BONDED, e))?;
        if word.len() != 4 {
            return Err(BtError::with(LOST, format!("pairing status has {} bytes", word.len())));
        }
        word[3] = 0x20;
        peripheral.write(&status_chr, &word, WriteType::WithResponse).await.map_err(|e| BtError::with(NOT_BONDED, e))?;
        send_client_name(peripheral, SECURE_PAIR_SERVICE).await?;
        subscribe(peripheral, SUBSCRIPTIONS_NEW).await;
    }

    progress(app, "wifi");
    let ssid = read_string(peripheral, WIFI_SERVICE, WIFI_SSID).await?;
    while status.try_recv().is_ok() {} // only answers to the request below count
    let start = characteristic(peripheral, SHUTTER_SERVICE, START_WIFI).ok_or(BtError::new(UNSUPPORTED))?;
    write(peripheral, &start, &[0x04, 0x00]).await?;
    let password = read_string(peripheral, WIFI_SERVICE, WIFI_PASSWORD).await?;
    // 1: the network is up; 0: the camera is busy (e.g. in playback). No answer: carry on, like libfuji.
    if let Ok(Some(0)) = timeout(WIFI_STATUS_TIME, status.recv()).await {
        return Err(BtError::new(BUSY));
    }
    if ssid.is_empty() {
        return Err(BtError::with(LOST, "empty network name"));
    }
    Ok(Credentials { ssid, password })
}

fn characteristic(peripheral: &Peripheral, service: Uuid, uuid: Uuid) -> Option<Characteristic> {
    peripheral.characteristics().into_iter().find(|c| c.service_uuid == service && c.uuid == uuid)
}

async fn write(peripheral: &Peripheral, chr: &Characteristic, data: &[u8]) -> Result<(), BtError> {
    peripheral.write(chr, data, WriteType::WithResponse).await.map_err(|e| BtError::with(LOST, e))
}

async fn send_client_name(peripheral: &Peripheral, service: Uuid) -> Result<(), BtError> {
    let chr = characteristic(peripheral, service, CLIENT_NAME_CHR).ok_or(BtError::new(UNSUPPORTED))?;
    write(peripheral, &chr, CLIENT_NAME.as_bytes()).await
}

/// Subscribes to what the camera offers of `list`; like libfuji, a missing or failing one isn't fatal.
async fn subscribe(peripheral: &Peripheral, list: &[(Uuid, Uuid)]) {
    for &(service, uuid) in list {
        if let Some(chr) = characteristic(peripheral, service, uuid) {
            let _ = peripheral.subscribe(&chr).await;
        }
    }
}

async fn read_string(peripheral: &Peripheral, service: Uuid, uuid: Uuid) -> Result<String, BtError> {
    let chr = characteristic(peripheral, service, uuid).ok_or(BtError::new(UNSUPPORTED))?;
    let bytes = peripheral.read(&chr).await.map_err(|e| BtError::with(LOST, e))?;
    let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
    Ok(String::from_utf8_lossy(&bytes[..end]).trim().to_string())
}

/// The local time, packed the way the camera wants it: year (u16 LE), month, day, hour, minute, second.
fn camera_time() -> [u8; 7] {
    let now = Local::now();
    let [y0, y1] = (now.year() as u16).to_le_bytes();
    [y0, y1, now.month() as u8, now.day() as u8, now.hour() as u8, now.minute() as u8, now.second() as u8]
}

/// Drops the Bluetooth link to the camera, if any.
#[tauri::command]
pub async fn bluetooth_disconnect(bluetooth: State<'_, Bluetooth>) -> Result<(), BtError> {
    bluetooth.0.lock().await.drop_link().await;
    Ok(())
}

/// Forgets a saved camera. The OS bond, if any, stays; remove it in the OS Bluetooth settings.
#[tauri::command]
pub fn bluetooth_forget(id: String, app: AppHandle) {
    let mut saved = load_saved(&app);
    saved.retain(|s| s.id != id);
    store_saved(&app, &saved);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_from_advertisement() {
        let mut properties = PeripheralProperties::default();
        properties.manufacturer_data.insert(FUJIFILM, vec![0x02, 1, 2, 3, 4]);
        assert_eq!(pairing_token(&properties), Some([1, 2, 3, 4]));
        properties.manufacturer_data.insert(FUJIFILM, vec![0x01, 1, 2, 3, 4]);
        assert_eq!(pairing_token(&properties), None);
        properties.manufacturer_data.insert(FUJIFILM, vec![0x02, 1, 2]);
        assert_eq!(pairing_token(&properties), None);
    }

    #[test]
    fn token_round_trip() {
        assert_eq!(unhex(&hex(&[0xde, 0xad, 0x00, 0x7f])), Some([0xde, 0xad, 0x00, 0x7f]));
        assert_eq!(unhex("abc"), None);
        assert_eq!(unhex("zz000000"), None);
    }
}
