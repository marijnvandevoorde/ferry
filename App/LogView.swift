import SwiftUI

struct LogView: View {
    @Environment(CameraModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.logText.isEmpty ? "No activity yet." : model.logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                Color.clear.frame(height: 1).id("end")
            }
            .onChange(of: model.log.count) { proxy.scrollTo("end") }
        }
        .toolbar {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.logText, forType: .string)
            } label: {
                Label("Copy Log", systemImage: "doc.on.doc")
            }
        }
    }
}
