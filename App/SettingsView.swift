import SwiftUI

struct SettingsView: View {
    @Environment(CameraModel.self) private var model
    @AppStorage(Prefs.host) private var host = ""
    @AppStorage(Prefs.autoConnect) private var autoConnect = true
    @AppStorage(Prefs.autoImport) private var autoImport = false
    @AppStorage(Prefs.useAlbum) private var useAlbum = true
    @AppStorage(Prefs.albumName) private var albumName = "Fujifilm"
    @State private var confirmForget = false

    var body: some View {
        Form {
            Section("Camera") {
                TextField("Camera address", text: $host, prompt: Text("Automatic (Wi-Fi router)"))
                Toggle("Connect automatically when the camera is found", isOn: $autoConnect)
                Toggle("Import new photos automatically after connecting", isOn: $autoImport)
            }
            Section("Photos") {
                Toggle("Add imported photos to an album", isOn: $useAlbum)
                TextField("Album name", text: $albumName)
                    .disabled(!useAlbum)
            }
            Section {
                Button("Forget Import History…") { confirmForget = true }
            } footer: {
                Text("Fuji Import remembers which photos it imported so it only offers new ones.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
        .confirmationDialog("Forget which photos were imported?", isPresented: $confirmForget) {
            Button("Forget History", role: .destructive) { model.forgetHistory() }
        } message: {
            Text("All photos on the camera will show as not imported. Nothing is deleted from Photos.")
        }
    }
}
