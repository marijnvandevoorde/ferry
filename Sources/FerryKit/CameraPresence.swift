import Foundation

/// Whether a camera's address still answers, without talking to the camera: a plain TCP connect to the port its
/// protocol listens on, closed straight away. Used to wait for the camera to go away after letting go of it.
public enum CameraPresence {
    /// The address and port to check for `camera`.
    public static func endpoint(of camera: WirelessCamera) -> (host: String, port: UInt16)? {
        switch camera {
        case let fuji as FujiCamera:
            return (fuji.host, PTP.commandPort)
        case let ptp as PTPIPCamera:
            return (ptp.host, PTPIPCamera.port)
        case let http as HTTPCamera:
            guard let host = http.base.host else { return nil }
            var port = http.base.port ?? 80
            // DLNA cameras serve on their own port; the known description URLs carry it.
            if http is DLNACamera,
               let known = DLNACamera.knownDescriptions.compactMap(URL.init(string:)).first(where: { $0.host == host }) {
                port = known.port ?? port
            }
            return (host, UInt16(clamping: port))
        default:
            return nil
        }
    }

    /// True when something accepts a TCP connection on `host`:`port` within `timeout`.
    public static func answers(host: String, port: UInt16, interface: String? = nil, timeout: TimeInterval = 2) -> Bool {
        guard let socket = try? TCPSocket(host: host, port: port, interface: interface, connectTimeout: timeout) else {
            return false
        }
        socket.close()
        return true
    }
}
