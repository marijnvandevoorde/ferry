import SwiftUI

struct ConnectView: View {
    @Environment(CameraModel.self) private var model
    @AppStorage(Prefs.autoConnect) private var autoConnect = true
    @AppStorage(Prefs.autoSave) private var autoSave = false
    @State private var showBluetooth = false

    /// The report section of the site's cameras page, in the app's language; it links to the report form.
    static var reportURL: URL {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let prefix = ["nl", "fr", "de", "es", "it"].contains(language) ? "/\(language)" : ""
        return URL(string: "https://ferry.small-victories.co\(prefix)/cameras/#report")!
    }

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 112, height: 112)
                if model.phase == .searching && !model.importDone {
                    Image("FerryMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, isActive: model.phase != .searching)
                }
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if model.phase == .searching {
                if model.importDone {
                    doneSummary
                    DisclosureGroup("How to connect") {
                        steps.padding(.top, 8)
                    }
                    .frame(maxWidth: 480)
                } else {
                    steps
                    if autoSave {
                        Label("PC AutoSave is on: the camera can also send photos over your home Wi-Fi.", systemImage: "house")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    fujifilmLinks
                }
            }

            if model.phase == .searching, !model.importDone, model.lastError == nil, let summary = model.importSummary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            if let error = model.lastError {
                VStack(spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Link("Send a camera report…", destination: Self.reportURL)
                        SaveDiagnosticsButton().buttonStyle(.link)
                    }
                }
                .font(.callout)
                .frame(maxWidth: 460)
            }

            HStack(spacing: 12) {
                if model.phase == .searching {
                    Button("Open Wi-Fi Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
                    }
                    Button("Connect") {
                        Task { await model.connect() }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { model.cancelConnect() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showBluetooth) { BluetoothPairingView() }
    }

    /// Auto-connect is on and not waiting for the user to press Connect.
    private var connectsByItself: Bool { autoConnect && !model.autoConnectPaused }

    /// After Ferry let go of the camera: what was imported, and where to see it.
    @ViewBuilder private var doneSummary: some View {
        if let summary = model.importSummary {
            VStack(spacing: 8) {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                switch model.lastImportLocation {
                case .photos?:
                    Button("Open Photos") { model.showLastImport() }.buttonStyle(.link)
                case .folder?:
                    Button("Show in Finder") { model.showLastImport() }.buttonStyle(.link)
                case nil:
                    EmptyView()
                }
                HStack(spacing: 16) {
                    Link("Send a camera report…", destination: Self.reportURL)
                    SaveDiagnosticsButton().buttonStyle(.link)
                }
            }
            .font(.callout)
        }
    }

    /// "Fujifilm: Stay online with PC AutoSave · Pair over Bluetooth (X-T5 and newer)", each part a link.
    private var fujifilmLinks: some View {
        HStack(spacing: 4) {
            Text("Fujifilm:")
                .foregroundStyle(.secondary)
            if !autoSave {
                SettingsLink {
                    Text("Stay online with PC AutoSave")
                }
                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
            }
            Button("Pair over Bluetooth (X-T5 and newer)") { showBluetooth = true }
        }
        .buttonStyle(.link)
        .font(.callout)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepRow(number: 1, text: CameraGuide.lastConnected.cameraStep)
            StepRow(number: 2, text: "On this Mac, join the camera's Wi-Fi network. Its name usually includes the brand or model.")
            StepRow(number: 3, text: connectsByItself
                    ? "Ferry connects automatically. Press **OK** on the camera if it asks."
                    : "Click **Connect**. Press **OK** on the camera if it asks.")
            DisclosureGroup("Where is Wi-Fi on my camera?") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("**Canon:** the Wi-Fi menu, as for the Camera Connect app.")
                    Text("**Fujifilm:** Playback, then Wireless Communication (on some models the Wi-Fi button).")
                    Text("**GoPro:** Preferences → Connections → Connect Device → GoPro Quik. The network name and password are under Camera Info.")
                    Text("**Olympus / OM System:** as for the OI.Share or OM Image Share app.")
                    Text("**Panasonic Lumix:** as for the Image App or LUMIX Sync app.")
                    Text("**Ricoh GR:** as for the GR WORLD or Image Sync app.")
                    Text("**Sony:** Send to Smartphone in the playback menu.")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            }
            .font(.callout)
            Label("While this Mac is on the camera's network it has no internet. Turn the camera off and this Mac goes back to your usual Wi-Fi.", systemImage: "wifi.exclamationmark")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 480, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var icon: String {
        switch model.phase {
        case .waitingForApproval: "hand.tap"
        case .searching where model.importDone: "checkmark"
        default: "wifi"
        }
    }

    private var title: LocalizedStringKey {
        switch model.phase {
        case .connecting: "Connecting…"
        case .waitingForApproval: "Waiting for the camera"
        case .searching where model.importDone: "Import done"
        default: "Connect your camera"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch model.phase {
        case .connecting: "Talking to the camera at \(model.cameraAddress)"
        case .waitingForApproval: "Check the camera. It may be asking whether to allow this Mac."
        case .searching where model.importDone: "You can turn the camera off now."
        default: connectsByItself ? "Join the camera's Wi-Fi network and Ferry connects by itself." : "Import photos from your camera over Wi-Fi."
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(.tint.opacity(0.18)))
                .foregroundStyle(.tint)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
