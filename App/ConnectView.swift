import SwiftUI

struct ConnectView: View {
    @Environment(CameraModel.self) private var model
    @AppStorage(Prefs.autoConnect) private var autoConnect = true
    @AppStorage(Prefs.autoSave) private var autoSave = false

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 112, height: 112)
                Image(systemName: icon)
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, isActive: model.phase != .searching || autoConnect)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if model.phase == .searching {
                steps
                if autoSave {
                    Label("PC AutoSave is on: the camera can also send photos over your home Wi-Fi.", systemImage: "house")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    SettingsLink {
                        Text("Stay online: import over your home Wi-Fi with PC AutoSave…")
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .multilineTextAlignment(.center)
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
                }
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepRow(number: 1, text: CameraGuide.lastConnected.cameraStep)
            StepRow(number: 2, text: "On this Mac, join the camera's Wi-Fi network (named **FUJIFILM-X-…**).")
            StepRow(number: 3, text: autoConnect
                    ? "Fuji Import connects automatically. Press **OK** on the camera if it asks."
                    : "Click **Connect**. Press **OK** on the camera if it asks.")
        }
        .padding(20)
        .frame(maxWidth: 480, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var icon: String {
        switch model.phase {
        case .waitingForApproval: "hand.tap"
        case .connecting: "wifi"
        default: "camera"
        }
    }

    private var title: String {
        switch model.phase {
        case .connecting: "Connecting…"
        case .waitingForApproval: "Press OK on the camera"
        default: "Connect your camera"
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .connecting: "Talking to the camera at \(model.cameraAddress)"
        case .waitingForApproval: "The camera is asking whether to allow this Mac."
        default: autoConnect ? "Looking for the camera on your Wi-Fi network…" : "Import photos from your Fujifilm camera over Wi-Fi."
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
