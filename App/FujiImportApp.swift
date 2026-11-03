import SwiftUI

@main
struct FujiImportApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = CameraModel()
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        WindowGroup("Ferry", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 500)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(after: .windowArrangement) {
                OpenLogButton()
            }
            CommandMenu("Import") {
                Button("Import New") { model.importNew() }
                    .keyboardShortcut("i")
                    .disabled(model.phase != .connected || model.itemsToImport.isEmpty || model.isImporting)
                Button("Import Selected") { model.importSelected() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(model.phase != .connected || model.selection.isEmpty || model.isImporting)
                Divider()
                Button("Stop Import") { model.cancelImport() }
                    .keyboardShortcut(".")
                    .disabled(!model.isImporting)
            }
        }

        Window("Connection Log", id: "log") {
            LogView()
                .environment(model)
        }
        .defaultSize(width: 700, height: 420)

        MenuBarExtra("Ferry", systemImage: "camera.aperture", isInserted: $showMenuBarIcon) {
            MenuBarContent()
                .environment(model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

private struct OpenLogButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Connection Log") { openWindow(id: "log") }
            .keyboardShortcut("l", modifiers: [.command, .option])
    }
}
