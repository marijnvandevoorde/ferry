import Darwin
import Foundation

/// Fuji's *PC AutoSave*: the camera joins the home network and sends photos to a registered computer.
/// Port of libfuji's discovery.c (MIT); the message format is documented in libfuji's docs/autosave.md.
///
/// 1. The camera broadcasts `DISCOVER` over UDP: to port 51542 while registering ("PC AutoSave Setting"),
///    to 51541 when it wants to send photos.
/// 2. The computer connects to the camera on TCP 51540 and sends `NOTIFY`, naming itself.
/// 3. The camera connects back to the computer on TCP 51542 (`REGISTER`) or 51541 (`IMPORT`).
/// 4. After an import request the computer opens a normal PTP session on the camera's port 55740.
public final class AutoSaveListener: @unchecked Sendable {
    public struct Ports: Sendable {
        public var notify: UInt16 = 51540
        public var register: UInt16 = 51542
        public var connect: UInt16 = 51541
        public init() {}
    }

    public enum Event: Sendable, Equatable {
        /// The camera registered this computer. It will offer photos from now on.
        case registered(camera: String, model: String)
        /// The camera wants to send photos; open a `FujiCamera` session to `host`.
        case importRequest(host: String, camera: String)
    }

    public let clientName: String
    public var log: (String) -> Void
    let ports: Ports
    private var registerSocket: Int32 = -1
    private var connectSocket: Int32 = -1

    /// `clientName` is shown on the camera; it is reduced to characters the camera's parser accepts.
    public init(clientName: String, ports: Ports = Ports(), log: @escaping (String) -> Void = { _ in }) {
        self.clientName = Self.importerName(clientName)
        self.ports = ports
        self.log = log
    }

    deinit { stop() }

    static func importerName(_ name: String) -> String {
        let allowed = name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" }
        let collapsed = String(allowed).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "FujiImport" : String(collapsed.prefix(32))
    }

    /// Opens the UDP ports the camera broadcasts to.
    public func start() throws {
        if registerSocket < 0 { registerSocket = try Self.udpSocket(port: ports.register) }
        if connectSocket < 0 { connectSocket = try Self.udpSocket(port: ports.connect) }
    }

    public func stop() {
        if registerSocket >= 0 { close(registerSocket) }
        if connectSocket >= 0 { close(connectSocket) }
        registerSocket = -1
        connectSocket = -1
    }

    /// Waits up to `timeout` for a camera; returns nil when none showed up.
    public func waitForCamera(timeout: TimeInterval) throws -> Event? {
        try start()
        var fds = [pollfd(fd: registerSocket, events: Int16(POLLIN), revents: 0),
                   pollfd(fd: connectSocket, events: Int16(POLLIN), revents: 0)]
        let n = poll(&fds, 2, Int32(timeout * 1000))
        guard n > 0 else {
            if n < 0 && errno != EINTR { throw FujiError.io("poll: \(String(cString: strerror(errno)))") }
            return nil
        }
        let isRegister = fds[0].revents & Int16(POLLIN) != 0
        let fd = isRegister ? registerSocket : connectSocket
        var buffer = [UInt8](repeating: 0, count: 1024)
        let len = recv(fd, &buffer, buffer.count, 0)
        guard len > 0 else { return nil }
        let greeting = String(decoding: buffer[0..<len], as: UTF8.self)
        log("AutoSave: \(isRegister ? "registration" : "import") request from the camera")
        return try handle(greeting: greeting, register: isRegister)
    }

    /// Answers a camera whose address is already known, as if its DISCOVER datagram had arrived.
    /// Useful when broadcasts don't reach the computer.
    public func respond(toCameraAt host: String, register: Bool) throws -> Event? {
        try handle(greeting: "DISCOVER \(register ? "*" : clientName) HTTP/1.1\r\nDSCADDR:\(host)\r\n", register: register)
    }

    private func handle(greeting: String, register: Bool) throws -> Event? {
        let fields = Self.parse(greeting)
        guard let cameraIP = fields["DSCADDR"] else {
            log("AutoSave: ignoring a datagram without DSCADDR")
            return nil
        }
        // The camera addresses an import to the name it registered; "*" while registering.
        let target = fields["DISCOVER"].flatMap { $0 == "*" ? nil : $0 } ?? clientName

        // Listen before announcing ourselves: the camera connects back shortly after NOTIFY.
        let invitePort = register ? ports.register : ports.connect
        let server = try Self.tcpListener(port: invitePort)
        defer { close(server) }

        let notify = try TCPSocket(host: cameraIP, port: ports.notify, connectTimeout: 5)
        defer { notify.close() }
        try notify.write(Data("NOTIFY * HTTP/1.1\r\nHOST: \(cameraIP):\(ports.notify)\r\nIMPORTER: \(target)\r\n".utf8))
        notify.readTimeout = 10
        let ack = try notify.readAvailable()
        guard ack.contains("200 OK") else {
            throw FujiError.protocolError("the camera rejected NOTIFY: \(ack)")
        }

        var pfd = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
        guard poll(&pfd, 1, 30_000) > 0 else { throw FujiError.timeout }
        let client = accept(server, nil, nil)
        guard client >= 0 else { throw FujiError.io("accept: \(String(cString: strerror(errno)))") }
        let invite = TCPSocket(fd: client)
        defer { invite.close() }
        invite.readTimeout = 10
        let request = Self.parse(try invite.readAvailable())
        let camera = request["DSCNAME"] ?? "camera"
        // Responses copied from libfuji, which was tested against real cameras.
        let response = register
            ? "HTTP/1.1 200 OK\r\nFOLDER: guest\r\nServiceName: PCAUTOSAVE/1.0\r\n"
            : "HTTP/1.1 200 OK\r\n"
        try invite.write(Data(response.utf8))

        if register {
            let model = request["DSCMODEL"] ?? ""
            log("AutoSave: registered with \(camera) \(model)")
            return .registered(camera: camera, model: model)
        }
        log("AutoSave: \(camera) at \(cameraIP) is ready to send photos")
        return .importRequest(host: cameraIP, camera: camera)
    }

    /// Parses `KEY:value` header lines; the first line's verb maps to its argument (`DISCOVER` → `*`).
    static func parse(_ message: String) -> [String: String] {
        var fields: [String: String] = [:]
        for (i, line) in message.components(separatedBy: "\r\n").enumerated() where !line.isEmpty {
            if i == 0 {
                let parts = line.split(separator: " ")
                if parts.count >= 2 { fields[String(parts[0])] = String(parts[1]) }
            } else if let colon = line.firstIndex(of: ":") {
                fields[String(line[..<colon]).trimmingCharacters(in: .whitespaces)] =
                    String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return fields
    }

    private static func udpSocket(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw FujiError.io("socket: \(String(cString: strerror(errno)))") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        try bindAny(fd, port: port)
        return fd
    }

    private static func tcpListener(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FujiError.io("socket: \(String(cString: strerror(errno)))") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        try bindAny(fd, port: port)
        guard listen(fd, 2) == 0 else {
            close(fd)
            throw FujiError.io("listen on \(port): \(String(cString: strerror(errno)))")
        }
        return fd
    }

    private static func bindAny(_ fd: Int32, port: UInt16) throws {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard rc == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw FujiError.io("port \(port) is in use (\(message)). Is Fujifilm's PC AutoSave app running?")
        }
    }
}
