import AppKit
import FerryKit
import SwiftUI
import UniformTypeIdentifiers

/// Saves FerryKit's diagnostics trace (every step and exchange with the camera, no photos) for a camera report.
@MainActor
enum Diagnostics {
    static func setUp() {
        Trace.shared.app = "Mac app"
        Trace.shared.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        if let name = Host.current().localizedName { Trace.shared.redact(name) }
    }

    static func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Trace.suggestedFileName()
        panel.allowedContentTypes = [.json]
        panel.message = String(localized: "Attach this file to your camera report. It holds what Ferry and the camera said to each other, but no photos.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Trace.shared.export(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

struct SaveDiagnosticsButton: View {
    var body: some View {
        Button("Save Diagnostics…") { Diagnostics.save() }
    }
}
