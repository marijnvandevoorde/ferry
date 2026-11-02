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

    public func run<T: Sendable>(_ body: @escaping @Sendable (WirelessCamera) throws -> T) async throws -> T {
        let camera = self.camera
        return try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try body(camera) }) }
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
    /// DLNA media server: older Sony ("Send to Smartphone") and Panasonic Lumix.
    case dlna

    /// Connects with each protocol in turn and returns the first camera that accepts. A protocol is skipped only
    /// when nothing listens on its port, so no camera gets a throwaway connection (some accept just one).
    public static func connect(host: String, interface: String?, clientName: String, log: @escaping (String) -> Void,
                               onWaitingForApproval: () -> Void = {}) throws -> WirelessCamera {
        var lastError: Error = FujiError.connectionFailed("no camera at \(host)")
        for proto in allCases {
            let camera = proto.camera(host: host, interface: interface, clientName: clientName, log: log)
            do {
                try camera.connect(onWaitingForApproval: onWaitingForApproval)
                return camera
            } catch FujiError.connectionFailed(let reason) {
                lastError = FujiError.connectionFailed(reason)
            }
        }
        throw lastError
    }

    public func camera(host: String, interface: String?, clientName: String, log: @escaping (String) -> Void) -> WirelessCamera {
        switch self {
        case .fuji: FujiCamera(host: host, interface: interface, clientName: clientName, log: log)
        case .ptpip: PTPIPCamera(host: host, interface: interface, clientName: clientName, log: log)
        case .olympus: OlympusCamera(host: host, log: log)
        case .ricoh: RicohCamera(host: host, log: log)
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
