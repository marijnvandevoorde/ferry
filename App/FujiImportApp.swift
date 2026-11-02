import SwiftUI

@main
struct FujiImportApp: App {
    @State private var model = CameraModel()

    var body: some Scene {
        WindowGroup("Fuji Import") {
            ContentView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 500)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(after: .windowArrangement) {
                OpenLogButton()
            }
        }

        Window("Connection Log", id: "log") {
            LogView()
                .environment(model)
        }
        .defaultSize(width: 700, height: 420)

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
