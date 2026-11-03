import AppKit
import SwiftUI
import UserNotifications

/// The menu bar icon's menu: camera status and the main actions, so the window can stay closed.
struct MenuBarContent: View {
    @Environment(CameraModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(status)
        if let p = model.importProgress {
            Text(p.total == 0 ? "Receiving \(p.filename)" : "Importing \(p.index) of \(p.total)")
            Button("Stop Import") { model.cancelImport() }
        } else if model.phase == .connected {
            Button(model.itemsToImport.isEmpty ? "No New Items" : "Import \(model.itemsToImport.count) New") {
                model.importNew()
            }
            .disabled(model.itemsToImport.isEmpty || model.isListing)
        }
        if let summary = model.importSummary {
            Text(summary)
        }
        Divider()
        Button("Open Ferry") {
            NSApp.activate()
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true || $0.title == "Ferry" }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Ferry") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        switch model.phase {
        case .searching: String(localized: "No camera connected")
        case .connecting: String(localized: "Connecting…")
        case .waitingForApproval: String(localized: "Press OK on the camera")
        case .connected: String(localized: "\(model.cameraName.isEmpty ? String(localized: "Camera") : model.cameraName): \(model.newItems.count) new")
        }
    }
}

/// Local notifications for when the app is in the background.
enum Notifier {
    static func post(_ title: String, _ body: String) {
        guard !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

/// Applies "menu bar only" (no Dock icon) at launch and when the setting changes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.applyDockIconPreference()
    }

    static func applyDockIconPreference() {
        let hide = UserDefaults.standard.bool(forKey: Prefs.hideDockIcon)
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
    }
}
