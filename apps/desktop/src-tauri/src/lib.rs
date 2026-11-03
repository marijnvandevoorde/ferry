//! The desktop shell: runs `fujictl serve` as a sidecar and relays its JSON lines to the UI.
//! All camera logic lives in fujictl (FujiKit); see docs/adr/0001-windows-linux-app.md.

mod bluetooth;
mod wifi;

use std::sync::Mutex;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, State, WindowEvent};
use tauri_plugin_shell::process::{CommandChild, CommandEvent};
use tauri_plugin_shell::ShellExt;

#[derive(Default)]
struct Sidecar(Mutex<Option<CommandChild>>);

/// Sends one command (a JSON object) to fujictl.
#[tauri::command]
fn send(command: serde_json::Value, sidecar: State<Sidecar>) -> Result<(), String> {
    let mut guard = sidecar.0.lock().map_err(|e| e.to_string())?;
    let child = guard.as_mut().ok_or("fujictl is not running")?;
    let mut line = command.to_string();
    line.push('\n');
    child.write(line.as_bytes()).map_err(|e| e.to_string())
}

fn start_sidecar(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let mut args = vec!["serve".to_string()];
    // FUJIIMPORT_HOST points the app at a camera emulator during development.
    if let Ok(host) = std::env::var("FUJIIMPORT_HOST") {
        args.insert(0, host);
        args.insert(0, "--host".into());
    }
    let (mut events, child) = app.shell().sidecar("fujictl")?.args(args).spawn()?;
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
                            let _ = app.emit("fujictl", value);
                        }
                    }
                }
                CommandEvent::Stderr(bytes) => {
                    let line = String::from_utf8_lossy(&bytes).trim().to_string();
                    let _ = app.emit("fujictl", serde_json::json!({ "event": "log", "line": line }));
                }
                CommandEvent::Terminated(status) => {
                    let message = format!("fujictl stopped ({:?})", status.code);
                    let _ = app.emit("fujictl", serde_json::json!({ "event": "error", "message": message }));
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
            bluetooth::bluetooth_saved,
            bluetooth::bluetooth_scan,
            bluetooth::bluetooth_connect,
            bluetooth::bluetooth_disconnect,
            bluetooth::bluetooth_forget,
            wifi::wifi_join,
        ])
        .setup(|app| {
            start_sidecar(app.handle())?;

            let open = MenuItem::with_id(app, "open", "Open Fuji Import", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &quit])?;
            TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Fuji Import")
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
