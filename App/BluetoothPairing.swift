import CoreWLAN
import FerryKit
import SwiftUI

/// Pairs with a newer Fujifilm camera over Bluetooth, joins the Wi-Fi network it starts, and hands over to
/// `CameraModel`. See `FujiBluetooth`; not yet tested on a real camera.
@MainActor
@Observable
final class BluetoothPairing {
    enum Step: Equatable {
        case scanning
        case pairing(Double)
        case joining(String)
        /// Joining automatically didn't work: show the network so the user can join it.
        case manual(FujiBluetooth.WiFiCredentials)
        case failed(String)
    }

    private(set) var step: Step = .scanning
    private(set) var cameras: [FujiBluetoothCentral.Camera] = []
    private(set) var saved: [FujiBluetooth.Pairing] = BluetoothPairing.loadSaved()
    private var central: FujiBluetoothCentral?
    private var log: (String) -> Void = { _ in }

    func start(log: @escaping (String) -> Void) {
        self.log = log
        step = .scanning
        cameras = []
        let central = FujiBluetoothCentral(log: log)
        central.onDiscover = { camera in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cameras.removeAll { $0.id == camera.id }
                self.cameras.append(camera)
            }
        }
        self.central = central
        Task {
            do {
                try await central.scan()
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        central?.stopScan()
    }

    /// Pairs (or reconnects) and connects `model` once this Mac is on the camera's network.
    func connect(cameraID: UUID, model: CameraModel) async {
        guard let central else { return }
        let previous = saved.first { $0.identifier == cameraID.uuidString }
        step = .pairing(0)
        do {
            let (wifi, pairing) = try await central.handOff(
                cameraID: cameraID, saved: previous, clientName: Host.current().localizedName ?? "Mac",
                progress: { value in Task { @MainActor [weak self] in self?.step = .pairing(value) } })
            remember(pairing)
            step = .joining(wifi.ssid)
            if await Self.join(wifi) {
                await model.connectAfterBluetoothHandoff(central)
            } else {
                step = .manual(wifi)
            }
        } catch {
            log("Bluetooth: \(error.localizedDescription)")
            step = .failed(error.localizedDescription)
        }
    }

    /// After the user joined the network by hand.
    func joinedManually(model: CameraModel) async {
        guard let central else { return }
        await model.connectAfterBluetoothHandoff(central)
    }

    func forget(_ pairing: FujiBluetooth.Pairing) {
        saved.removeAll { $0 == pairing }
        store()
    }

    private func remember(_ pairing: FujiBluetooth.Pairing) {
        saved.removeAll { $0.identifier == pairing.identifier }
        saved.insert(pairing, at: 0)
        store()
    }

    private func store() {
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Prefs.bluetoothPairings)
    }

    private static func loadSaved() -> [FujiBluetooth.Pairing] {
        guard let data = UserDefaults.standard.data(forKey: Prefs.bluetoothPairings) else { return [] }
        return (try? JSONDecoder().decode([FujiBluetooth.Pairing].self, from: data)) ?? []
    }

    /// Joins the camera's network, which may be hidden. Returns false when macOS doesn't allow it (for example
    /// without Location access, which network scans need); the user then joins it in Wi-Fi settings.
    nonisolated static func join(_ wifi: FujiBluetooth.WiFiCredentials) async -> Bool {
        await Task.detached {
            guard let interface = CWWiFiClient.shared().interface() else { return false }
            do {
                guard let network = try interface.scanForNetworks(withName: wifi.ssid, includeHidden: true).first else {
                    return false
                }
                try interface.associate(to: network, password: wifi.password)
                return true
            } catch {
                return false
            }
        }.value
    }
}

struct BluetoothPairingView: View {
    @Environment(CameraModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pairing = BluetoothPairing()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pair over Bluetooth")
                .font(.title2.weight(.semibold))
            content
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { pairing.start { line in Task { @MainActor in model.appendLog(line) } } }
        .onDisappear { pairing.stop() }
        .onChange(of: model.phase) { _, phase in
            if phase != .searching { dismiss() }
        }
    }

    @ViewBuilder private var content: some View {
        switch pairing.step {
        case .scanning:
            Text("For cameras that pair with Fujifilm's app over Bluetooth, like the X-T5 and X-S20. On the camera, choose **Bluetooth Settings**, then **Pairing Registration**.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if pairing.cameras.isEmpty && pairing.saved.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for cameras…").foregroundStyle(.secondary)
                }
            }
            ForEach(pairing.cameras) { camera in
                let known = pairing.saved.contains { $0.identifier == camera.id.uuidString }
                row(camera.name, detail: camera.token != nil ? "Ready to pair" : known ? "Paired before" : "Not in pairing mode",
                    action: camera.token != nil ? "Pair" : "Connect") {
                    Task { await pairing.connect(cameraID: camera.id, model: model) }
                }
                .disabled(camera.token == nil && !known)
            }
            ForEach(pairing.saved.filter { saved in !pairing.cameras.contains { $0.id.uuidString == saved.identifier } }) { saved in
                row(saved.name, detail: "Paired before", action: "Connect") {
                    guard let id = UUID(uuidString: saved.identifier) else { return }
                    Task { await pairing.connect(cameraID: id, model: model) }
                }
                .contextMenu { Button("Forget This Camera") { pairing.forget(saved) } }
            }
            Text("Not tested on a real camera yet. If you try it, please tell us whether it worked.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .pairing(let progress):
            ProgressView(value: progress) { Text("Pairing… Allow the pairing if macOS or the camera asks.") }
        case .joining(let ssid):
            ProgressView { Text("Joining \(ssid)…") }
        case .manual(let wifi):
            Text("Join the camera's network in Wi-Fi settings, then click Connect.")
            Grid(alignment: .leading, verticalSpacing: 8) {
                GridRow {
                    Text("Network").foregroundStyle(.secondary)
                    Text(wifi.ssid).textSelection(.enabled)
                    copyButton(wifi.ssid)
                }
                GridRow {
                    Text("Password").foregroundStyle(.secondary)
                    Text(wifi.password).textSelection(.enabled).monospaced()
                    copyButton(wifi.password)
                }
            }
            HStack {
                Button("Open Wi-Fi Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
                }
                Button("Connect") { Task { await pairing.joinedManually(model: model) } }
                    .keyboardShortcut(.defaultAction)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { pairing.start { line in Task { @MainActor in model.appendLog(line) } } }
        }
    }

    private func row(_ name: String, detail: LocalizedStringKey, action: LocalizedStringKey,
                     perform: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "camera")
            VStack(alignment: .leading) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action, action: perform)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func copyButton(_ value: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy")
    }
}
