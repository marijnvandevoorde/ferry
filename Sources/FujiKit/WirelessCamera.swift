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
}

public enum CameraProtocol: String, Sendable, CaseIterable {
    /// Fujifilm's protocol on port 55740 (Camera Remote era).
    case fuji
    /// Standard PTP/IP on port 15740 (Canon, Nikon, Sony and others).
    case ptpip

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
        }
    }
}

extension WirelessCamera {
    @discardableResult
    public func download(_ handle: UInt32, to destination: URL) throws -> ObjectInfo {
        try download(handle, to: destination) { _, _ in }
    }
}

extension FujiCamera: WirelessCamera {}
