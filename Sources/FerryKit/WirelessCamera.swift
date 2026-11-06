import Foundation

/// A camera reached over Wi-Fi that can list and download its photos. Implemented by `FujiCamera` (Fuji's
/// own protocol) and `PTPIPCamera` (standard PTP/IP, used by Canon, Nikon and others).
///
/// All calls are blocking and must be serialized by the caller.
public protocol WirelessCamera: AnyObject, Sendable {
    var cameraName: String { get }
    var isConnected: Bool { get }
    /// Handles of the objects on the card, after `connect()`.
    var objectHandles: [UInt32] { get }

    func connect(onWaitingForApproval: () -> Void) throws
    func disconnect()
    func objectInfo(_ handle: UInt32) throws -> ObjectInfo
    /// The embedded JPEG thumbnail, or nil if the camera has none for this object.
    func thumbnail(_ handle: UInt32) throws -> Data?
    @discardableResult
    func download(_ handle: UInt32, to destination: URL, progress: (Int64, Int64) -> Void) throws -> ObjectInfo
    /// Keeps the connection alive and picks up new photos; returns the current number of objects.
    func refreshObjectCount() throws -> Int
    /// The battery charge in percent, when the camera reports it; updated by `connect()` and `refreshObjectCount()`.
    var batteryPercent: Int? { get }
    /// Cancels the download running now, if the camera can stop one midway; it then throws `CancellationError`.
    /// May be called from any thread, unlike the other calls. `SerialCamera.run` calls it when its task is cancelled.
    func cancelTransfer()
}

extension WirelessCamera {
    public var batteryPercent: Int? { nil }
    public func cancelTransfer() {}
}

/// Serializes calls to a camera on its own queue, for use from async code.
public final class SerialCamera: @unchecked Sendable {
    public let camera: WirelessCamera
    private let queue = DispatchQueue(label: "fujikit.camera.serial")

    public init(_ camera: WirelessCamera) {
        self.camera = camera
    }

    /// Fuji-specific features (selection mode, PC AutoSave, profile) when the camera is a Fuji.
    public var fuji: FujiCamera? { camera as? FujiCamera }

    /// Runs `body` on the camera's queue. Cancelling the calling task while `body` runs cancels the camera's
    /// running download (`cancelTransfer()`), which then throws `CancellationError`.
    public func run<T: Sendable>(_ body: @escaping @Sendable (WirelessCamera) throws -> T) async throws -> T {
        let camera = self.camera
        let run = Run()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async {
                    run.setRunning(true)
                    let result = Result { try body(camera) }
                    run.setRunning(false)
                    cont.resume(with: result)
                }
            }
        } onCancel: {
            run.ifRunning { camera.cancelTransfer() }
        }
    }

    /// Whether a `run` body is on the queue now, so a cancelled caller never stops another caller's download.
    private final class Run: @unchecked Sendable {
        private let lock = NSLock()
        private var running = false

        func setRunning(_ value: Bool) {
            lock.lock()
            running = value
            lock.unlock()
        }

        func ifRunning(_ action: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            if running { action() }
        }
    }
}

/// Where a camera listens, to check later whether it is still there without talking to it.
public struct CameraAddress: Sendable, Equatable {
    public var host: String
    public var port: UInt16
    public var interface: String?

    public init(host: String, port: UInt16, interface: String? = nil) {
        self.host = host
        self.port = port
        self.interface = interface
    }

    /// True when something accepts a TCP connection at the address. Connects and closes again, no handshake.
    public func answers(timeout: TimeInterval = 2) -> Bool {
        (try? TCPSocket(host: host, port: port, interface: interface, connectTimeout: timeout)) != nil
    }
}

extension WirelessCamera {
    /// The address and port this camera was reached on, when known.
    public var address: CameraAddress? {
        switch self {
        case let camera as FujiCamera:
            return CameraAddress(host: camera.host, port: PTP.commandPort, interface: camera.interface)
        case let camera as PTPIPCamera:
            return CameraAddress(host: camera.host, port: PTPIPCamera.port, interface: camera.interface)
        case let camera as DLNACamera:
            guard let url = camera.controlURL, let host = url.host else { return nil }
            return CameraAddress(host: host, port: UInt16(url.port ?? 80))
        case let camera as HTTPCamera:
            guard let host = camera.base.host else { return nil }
            return CameraAddress(host: host, port: UInt16(camera.base.port ?? 80))
        default:
            return nil
        }
    }
}

public enum CameraProtocol: String, Sendable, CaseIterable {
    /// Fujifilm's protocol on port 55740 (Camera Remote era).
    case fuji
    /// Standard PTP/IP on port 15740 (Canon, Nikon, Sony and others).
    case ptpip
    /// Olympus and OM System (OI.Share HTTP API).
    case olympus
    /// Ricoh GR II / III (HTTP API).
    case ricoh
    /// GoPro HERO9 and later (Open GoPro HTTP API).
    case gopro
    /// DLNA media server: older Sony ("Send to Smartphone") and Panasonic Lumix.
    case dlna

    /// Connects with each protocol in turn and returns the first camera that accepts. A protocol is skipped only
    /// when nothing listens on its port, so no camera gets a throwaway connection (some accept just one).
    /// `afterBluetoothHandoff`: the camera's Wi-Fi was started over Bluetooth (newer Fujifilm cameras).
    public static func connect(host: String, interface: String?, clientName: String, afterBluetoothHandoff: Bool = false,
                               log: @escaping (String) -> Void, onWaitingForApproval: () -> Void = {}) throws -> WirelessCamera {
        var lastError: Error = FujiError.connectionFailed("no camera at \(host)")
        for proto in allCases {
            let camera = proto.camera(host: host, interface: interface, clientName: clientName,
                                      afterBluetoothHandoff: afterBluetoothHandoff, log: log)
            do {
                try camera.connect(onWaitingForApproval: onWaitingForApproval)
                return camera
            } catch FujiError.connectionFailed(let reason) {
                lastError = FujiError.connectionFailed(reason)
            }
        }
        throw lastError
    }

    public func camera(host: String, interface: String?, clientName: String, afterBluetoothHandoff: Bool = false,
                       log: @escaping (String) -> Void) -> WirelessCamera {
        switch self {
        case .fuji: FujiCamera(host: host, interface: interface, clientName: clientName,
                               afterBluetoothHandoff: afterBluetoothHandoff, log: log)
        case .ptpip: PTPIPCamera(host: host, interface: interface, clientName: clientName, log: log)
        case .olympus: OlympusCamera(host: host, log: log)
        case .ricoh: RicohCamera(host: host, log: log)
        case .gopro: GoProCamera(host: host, log: log)
        case .dlna: DLNACamera(host: host, log: log)
        }
    }
}

/// Checks that a download is complete, so a truncated file is never imported.
func verifySize(_ file: URL, expected: UInt32) throws {
    guard expected > 0 else { return }
    let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.uint64Value ?? 0
    guard size == UInt64(expected) else {
        throw FujiError.protocolError("incomplete download: \(size) of \(expected) bytes")
    }
}

extension WirelessCamera {
    @discardableResult
    public func download(_ handle: UInt32, to destination: URL) throws -> ObjectInfo {
        try download(handle, to: destination) { _, _ in }
    }
}

extension FujiCamera: WirelessCamera {
    public func refreshObjectCount() throws -> Int {
        try pollEvents()
        return objectCount
    }
}
