import FerryKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(CameraModel.self) private var model
    @AppStorage(Prefs.host) private var host = ""
    @AppStorage(Prefs.autoConnect) private var autoConnect = true
    @AppStorage(Prefs.autoImport) private var autoImport = false
    @AppStorage(Prefs.disconnectAfterImport) private var disconnectAfterImport = false
    @AppStorage(Prefs.destination) private var destination = DestinationKind.photos
    @AppStorage(Prefs.useAlbum) private var useAlbum = true
    @AppStorage(Prefs.albumName) private var albumName = "Ferry"
    @AppStorage(Prefs.folderTemplate) private var folderTemplate = PathTemplate.defaultFolder.template
    @AppStorage(Prefs.renameFiles) private var renameFiles = false
    @AppStorage(Prefs.fileTemplate) private var fileTemplate = "{yyyy-MM-dd}_{original}"
    @AppStorage(Prefs.backupEnabled) private var backupEnabled = false
    @AppStorage(Prefs.skipVideos) private var skipVideos = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.hideDockIcon) private var hideDockIcon = false
    @AppStorage(Prefs.autoSave) private var autoSave = false
    @AppStorage(Prefs.immichEnabled) private var immichEnabled = false
    @AppStorage(Prefs.immichServer) private var immichServer = ""
    @AppStorage(Prefs.immichAlbum) private var immichAlbum = ""
    @State private var immichKey = ImmichKey.load() ?? ""
    @State private var folder = FolderBookmark.url(for: Prefs.folderBookmark)
    @State private var backupFolder = FolderBookmark.url(for: Prefs.backupBookmark)
    @State private var confirmForget = false

    private static let folderPresets = [
        ("Year / Date", "{yyyy}/{yyyy-MM-dd}"),
        ("Date", "{yyyy-MM-dd}"),
        ("Year / Month", "{yyyy}/{MM}"),
        ("No subfolders", ""),
    ]

    var body: some View {
        Form {
            Section("Camera") {
                TextField("Camera address", text: $host, prompt: Text("Automatic (Wi-Fi router)"))
                Toggle("Connect automatically when the camera is found", isOn: $autoConnect)
                Toggle("Import new photos automatically after connecting", isOn: $autoImport)
                Toggle(isOn: $disconnectAfterImport) {
                    Text("Disconnect when the import is done")
                    Text("Lets this Mac go back to your usual Wi-Fi network once the camera closes its own.")
                }
                Toggle("Leave videos out of “Import New”", isOn: $skipVideos)
                Toggle("Open Ferry at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show in the menu bar", isOn: $showMenuBarIcon)
                Toggle("Hide the Dock icon", isOn: $hideDockIcon)
                    .disabled(!showMenuBarIcon)
                    .onChange(of: hideDockIcon) { AppDelegate.applyDockIconPreference() }
                    .onChange(of: showMenuBarIcon) { _, show in if !show { hideDockIcon = false } }
            }
            Section {
                Toggle("Receive photos over the home network", isOn: $autoSave)
                    .onChange(of: autoSave) { model.updateAutoSave() }
                if autoSave && !model.autoSaveStatus.isEmpty {
                    LabeledContent("Status", value: model.autoSaveStatus)
                }
            } header: {
                Text("PC AutoSave")
            } footer: {
                Text("Fujifilm cameras: the camera joins your Wi-Fi and sends new photos to this Mac, so the Mac stays online. Once, on the camera: Set Up → Connection Setting → PC AutoSave Setting. Join your network (Simple Setup uses your router's WPS button, no password to type), then register this Mac. After that, choose PC AutoSave in the camera's playback menu to send photos.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Import to", selection: $destination) {
                    ForEach(DestinationKind.allCases) { Text($0.title).tag($0) }
                }
                switch destination {
                case .photos:
                    Toggle("Add imported photos to an album", isOn: $useAlbum)
                    TextField("Album name", text: $albumName, prompt: Text("Ferry {yyyy}-{MM}"))
                        .disabled(!useAlbum)
                case .folder:
                    FolderRow(title: "Folder", url: folder) {
                        folder = FolderBookmark.choose(for: Prefs.folderBookmark, message: String(localized: "Choose where to put imported photos.")) ?? folder
                    }
                    Picker("Subfolders", selection: $folderTemplate) {
                        ForEach(Self.folderPresets, id: \.1) { Text(LocalizedStringKey($0.0)).tag($0.1) }
                        if !Self.folderPresets.contains(where: { $0.1 == folderTemplate }) {
                            Text(folderTemplate).tag(folderTemplate)
                        }
                    }
                    Toggle("Rename files", isOn: $renameFiles)
                    TextField("File name", text: $fileTemplate, prompt: Text("{yyyy-MM-dd}_{original}"))
                        .disabled(!renameFiles)
                }
            } header: {
                Text("Destination")
            } footer: {
                if destination == .folder {
                    Text("Example: \(example). For Lightroom Classic, pick the folder that Auto Import watches; for Capture One, its hot folder. Tokens: {yyyy} {MM} {dd} {HH} {mm} {ss} {camera} {original}.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Also copy to a backup folder", isOn: $backupEnabled)
                if backupEnabled {
                    FolderRow(title: "Backup folder", url: backupFolder) {
                        backupFolder = FolderBookmark.choose(for: Prefs.backupBookmark, message: String(localized: "Choose a backup folder, for example on an external drive.")) ?? backupFolder
                    }
                }
            } footer: {
                if backupEnabled {
                    Text("Backups are sorted into Year / Date folders.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Also upload to Immich", isOn: $immichEnabled)
                if immichEnabled {
                    TextField("Server", text: $immichServer, prompt: Text("https://photos.example.com"))
                    SecureField("API key", text: $immichKey)
                        .onChange(of: immichKey) { _, key in ImmichKey.save(key) }
                    TextField("Album (optional)", text: $immichAlbum)
                }
            } footer: {
                if immichEnabled {
                    Text("Create an API key in Immich under Account Settings → API Keys.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Forget Import History…") { confirmForget = true }
            } footer: {
                Text("Ferry remembers which photos it imported so it only offers new ones.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize()
        .confirmationDialog("Forget which photos were imported?", isPresented: $confirmForget) {
            Button("Forget History", role: .destructive) { model.forgetHistory() }
        } message: {
            Text("All photos on the camera will show as not imported. Nothing is deleted.")
        }
    }

    private var example: String {
        let date = Date()
        let template = PathTemplate(folderTemplate)
        let name = renameFiles && !fileTemplate.isEmpty
            ? PathTemplate(fileTemplate).render(date: date, camera: "X-T20", original: "DSCF1234") + ".JPG"
            : "DSCF1234.JPG"
        return (template.folderComponents(date: date, camera: "X-T20", original: "DSCF1234") + [name]).joined(separator: "/")
    }
}

private struct FolderRow: View {
    let title: LocalizedStringKey
    let url: URL?
    let choose: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack {
                if let url {
                    Text(url.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not chosen").foregroundStyle(.secondary)
                }
                Button("Choose…", action: choose)
            }
        }
    }
}
