#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

/// Finds Fujifilm cameras over Bluetooth and runs the Wi-Fi hand-off (see `FujiBluetooth`) with CoreBluetooth.
///
/// GATT operations run one at a time; each callback resumes the single pending operation. Keep the object alive
/// while the camera is in use: the camera may turn its Wi-Fi off when the Bluetooth connection drops.
public final class FujiBluetoothCentral: NSObject, @unchecked Sendable {
    public struct Camera: Sendable, Identifiable, Equatable {
        public let id: UUID
        public let name: String
        /// Present while the camera is in pairing mode.
        public let token: Data?
    }

    public var log: (String) -> Void
    /// Called on the central's queue for every camera seen while scanning.
    public var onDiscover: ((Camera) -> Void)?

    private let queue = DispatchQueue(label: "fujikit.bluetooth")
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?

    private var poweredOn: [CheckedContinuation<Void, Error>] = []
    private var pending: CheckedContinuation<Any?, Error>?
    private var pendingKey: String?
    private var wifiStatusWaiter: CheckedContinuation<Data?, Never>?
    private var wifiStatus: Data?

    public init(log: @escaping (String) -> Void = { _ in }) {
        self.log = log
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: - Scanning

    /// Scans until `stopScan()`. Cameras appear through `onDiscover`.
    public func scan() async throws {
        try await waitUntilPoweredOn()
        queue.async { self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
    }

    public func stopScan() {
        queue.async { self.central.stopScan() }
    }

    // MARK: - Hand-off

    /// Pairs with (or reconnects to) a camera and returns its Wi-Fi credentials. The camera then starts its network.
    /// `saved` is a previous pairing with this camera; without it the camera must be in pairing mode.
    public func handOff(cameraID: UUID, saved: FujiBluetooth.Pairing?, clientName: String,
                        progress: @escaping @Sendable (Double) -> Void = { _ in })
        async throws -> (FujiBluetooth.WiFiCredentials, FujiBluetooth.Pairing) {
        typealias U = FujiBluetooth.UUIDs
        try await waitUntilPoweredOn()
        let peripheral: CBPeripheral = try queue.sync {
            if let known = peripherals[cameraID] { return known }
            guard let found = central.retrievePeripherals(withIdentifiers: [cameraID]).first else {
                throw FujiBluetooth.HandoffError.failed("The camera wasn't found. Turn on its Bluetooth and try again.")
            }
            peripherals[cameraID] = found
            return found
        }
        let advertisedToken = queue.sync { advertisedTokens[cameraID] }
        guard let token = advertisedToken ?? saved?.token else { throw FujiBluetooth.HandoffError.notInPairingMode }
        stopScan()

        log("Bluetooth: connecting to \(peripheral.name ?? "camera")")
        _ = try await perform("connect", timeout: 15) { self.central.connect(peripheral) }
        queue.sync { connected = peripheral; peripheral.delegate = self; wifiStatus = nil }
        progress(0.2)
        _ = try await perform("services", timeout: 15) { peripheral.discoverServices(nil) }
        for service in peripheral.services ?? [] {
            _ = try await perform("characteristics", timeout: 15) { peripheral.discoverCharacteristics(nil, for: service) }
        }
        progress(0.35)

        let pairService: String
        let subscriptions: [(service: String, characteristic: String)]
        if characteristic(U.pairService, U.pairToken, in: peripheral) != nil {
            log("Bluetooth: older pairing")
            pairService = U.pairService
            subscriptions = FujiBluetooth.legacySubscriptions
            do {
                try await write(token, to: U.pairService, U.pairToken, in: peripheral)
            } catch {
                throw FujiBluetooth.HandoffError.rejected
            }
        } else {
            guard characteristic(U.securePairService, U.secureStatus, in: peripheral) != nil else {
                throw FujiBluetooth.HandoffError.notAFujifilmCamera
            }
            log("Bluetooth: secure pairing")
            pairService = U.securePairService
            subscriptions = FujiBluetooth.secureSubscriptions
            // The first read of this encrypted characteristic makes macOS ask to pair.
            let status = try await read(U.securePairService, U.secureStatus, in: peripheral, timeout: 60)
            guard let ack = FujiBluetooth.acknowledgement(status: status) else {
                throw FujiBluetooth.HandoffError.failed("The camera sent an unexpected pairing status.")
            }
            try await write(ack, to: U.securePairService, U.secureStatus, in: peripheral)
        }
        progress(0.5)
        try await write(Data(clientName.utf8), to: pairService, U.clientName, in: peripheral)
        for (index, sub) in subscriptions.enumerated() {
            // libfuji ignores characteristics a model doesn't have.
            if characteristic(sub.service, sub.characteristic, in: peripheral) != nil {
                _ = try? await perform("notify \(sub.characteristic)", timeout: 5) {
                    if let c = self.characteristic(sub.service, sub.characteristic, in: peripheral) {
                        peripheral.setNotifyValue(true, for: c)
                    }
                }
            }
            progress(0.5 + 0.3 * Double(index + 1) / Double(subscriptions.count))
        }

        let ssid = FujiBluetooth.string(try await read(U.wifiService, U.wifiSSID, in: peripheral))
        try await write(FujiBluetooth.startWiFi, to: U.shutterService, U.wifiStart, in: peripheral)
        let password = FujiBluetooth.string(try await read(U.wifiService, U.wifiPassword, in: peripheral))
        guard !ssid.isEmpty else { throw FujiBluetooth.HandoffError.failed("The camera didn't send its Wi-Fi name.") }
        log("Bluetooth: the camera's network is \(ssid)")

        // The camera indicates 1 a few seconds later once its Wi-Fi is up, or 0 when it's busy.
        let status = await waitForWiFiStatus(timeout: 8)
        if status?.first == 0 { throw FujiBluetooth.HandoffError.cameraBusy }
        progress(1)

        let pairing = FujiBluetooth.Pairing(identifier: cameraID.uuidString, name: peripheral.name ?? ssid, token: token)
        return (FujiBluetooth.WiFiCredentials(ssid: ssid, password: password), pairing)
    }

    public func disconnect() {
        queue.async {
            if let connected = self.connected { self.central.cancelPeripheralConnection(connected) }
            self.connected = nil
        }
    }

    // MARK: - GATT helpers

    private var advertisedTokens: [UUID: Data] = [:]

    private func characteristic(_ service: String, _ uuid: String, in peripheral: CBPeripheral) -> CBCharacteristic? {
        peripheral.services?.first { $0.uuid == CBUUID(string: service) }?
            .characteristics?.first { $0.uuid == CBUUID(string: uuid) }
    }

    private func read(_ service: String, _ uuid: String, in peripheral: CBPeripheral, timeout: TimeInterval = 10) async throws -> Data {
        guard let c = characteristic(service, uuid, in: peripheral) else {
            throw FujiBluetooth.HandoffError.failed("The camera has no characteristic \(uuid).")
        }
        let value = try await perform("read \(uuid)", timeout: timeout) { peripheral.readValue(for: c) }
        return value as? Data ?? Data()
    }

    private func write(_ data: Data, to service: String, _ uuid: String, in peripheral: CBPeripheral) async throws {
        guard let c = characteristic(service, uuid, in: peripheral) else {
            throw FujiBluetooth.HandoffError.failed("The camera has no characteristic \(uuid).")
        }
        _ = try await perform("write \(uuid)", timeout: 10) { peripheral.writeValue(data, for: c, type: .withResponse) }
    }

    /// Starts one operation on the queue and waits for the delegate callback that finishes `key`.
    private func perform(_ key: String, timeout: TimeInterval, _ start: @escaping () -> Void) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.pending = cont
                self.pendingKey = key
                start()
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if self.pendingKey == key { self.finish(key, .failure(FujiBluetooth.HandoffError.timeout)) }
                }
            }
        }
    }

    /// Resumes the pending operation if it is `key`. Runs on the queue.
    private func finish(_ key: String, _ result: Result<Any?, Error>) {
        guard pendingKey == key, let cont = pending else { return }
        pending = nil
        pendingKey = nil
        cont.resume(with: result)
    }

    private func waitUntilPoweredOn() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                switch self.central.state {
                case .poweredOn: cont.resume()
                case .unknown, .resetting: self.poweredOn.append(cont)
                default: cont.resume(throwing: FujiBluetooth.HandoffError.bluetoothUnavailable)
                }
            }
        }
    }

    private func waitForWiFiStatus(timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { cont in
            queue.async {
                if let status = self.wifiStatus { return cont.resume(returning: status) }
                self.wifiStatusWaiter = cont
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.wifiStatusWaiter?.resume(returning: nil)
                    self.wifiStatusWaiter = nil
                }
            }
        }
    }
}

extension FujiBluetoothCentral: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            poweredOn.forEach { $0.resume() }
            poweredOn = []
        case .unknown, .resetting:
            break
        default:
            poweredOn.forEach { $0.resume(throwing: FujiBluetooth.HandoffError.bluetoothUnavailable) }
            poweredOn = []
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              FujiBluetooth.isFujifilm(manufacturerData: data) else { return }
        peripherals[peripheral.identifier] = peripheral
        let token = FujiBluetooth.pairingToken(manufacturerData: data)
        if let token { advertisedTokens[peripheral.identifier] = token }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Fujifilm camera"
        onDiscover?(Camera(id: peripheral.identifier, name: name, token: token))
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        finish("connect", .success(nil))
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish("connect", .failure(error ?? FujiBluetooth.HandoffError.failed("Couldn't connect over Bluetooth.")))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Bluetooth: disconnected")
        if peripheral == connected { connected = nil }
        if let key = pendingKey {
            finish(key, .failure(FujiBluetooth.HandoffError.failed("The camera ended the Bluetooth connection.")))
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        finish("services", error.map { .failure($0) } ?? .success(nil))
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        finish("characteristics", error.map { .failure($0) } ?? .success(nil))
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        finish("notify \(characteristic.uuid.uuidString)", error.map { .failure($0) } ?? .success(nil))
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        finish("write \(characteristic.uuid.uuidString)", error.map { .failure($0) } ?? .success(nil))
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid.uuidString
        if pendingKey == "read \(uuid)" {
            finish("read \(uuid)", error.map { .failure($0) } ?? .success(characteristic.value ?? Data()))
            return
        }
        // Notifications and indications.
        typealias U = FujiBluetooth.UUIDs
        switch characteristic.uuid {
        case CBUUID(string: U.timeRequest):
            if let time = peripheral.services?.first(where: { $0.uuid == CBUUID(string: U.timeService) })?
                .characteristics?.first(where: { $0.uuid == CBUUID(string: U.time) }) {
                peripheral.writeValue(FujiBluetooth.timePacket(Date()), for: time, type: .withResponse)
            }
        case CBUUID(string: U.wifiStatus):
            wifiStatus = characteristic.value
            wifiStatusWaiter?.resume(returning: characteristic.value)
            wifiStatusWaiter = nil
        default:
            break
        }
    }
}
#endif
