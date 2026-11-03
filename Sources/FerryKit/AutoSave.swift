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
    private var registerSocket = Sys.invalid
    private var connectSocket = Sys.invalid

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
        return collapsed.isEmpty ? "Ferry" : String(collapsed.prefix(32))
    }

    /// Opens the UDP ports the camera broadcasts to.
    public func start() throws {
        if !Sys.isValid(registerSocket) { registerSocket = try Self.udpSocket(port: ports.register) }
        if !Sys.isValid(connectSocket) { connectSocket = try Self.udpSocket(port: ports.connect) }
    }

    public func stop() {
        if Sys.isValid(registerSocket) { Sys.close(registerSocket) }
        if Sys.isValid(connectSocket) { Sys.close(connectSocket) }
        registerSocket = Sys.invalid
        connectSocket = Sys.invalid
    }

    /// Waits up to `timeout` for a camera; returns nil when none showed up.
    public func waitForCamera(timeout: TimeInterval) throws -> Event? {
        try start()
        let ready = Sys.wait([registerSocket, connectSocket], timeout: timeout)
        guard !ready.isEmpty else { return nil }
        let isRegister = ready[0]
        let fd = isRegister ? registerSocket : connectSocket
        var buffer = [UInt8](repeating: 0, count: 1024)
        let len = buffer.withUnsafeMutableBytes { Sys.receive(fd, $0.baseAddress!, $0.count) }
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
        defer { Sys.close(server) }

        let notify = try TCPSocket(host: cameraIP, port: ports.notify, connectTimeout: 5)
        defer { notify.close() }
        try notify.write(Data("NOTIFY * HTTP/1.1\r\nHOST: \(cameraIP):\(ports.notify)\r\nIMPORTER: \(target)\r\n".utf8))
        notify.readTimeout = 10
        let ack = try notify.readAvailable()
        guard ack.contains("200 OK") else {
            throw FujiError.protocolError("the camera rejected NOTIFY: \(ack)")
        }

        guard !Sys.wait([server], timeout: 30).isEmpty else { throw FujiError.timeout }
        let client = Sys.accept(server)
        guard Sys.isValid(client) else { throw FujiError.io("accept: \(Sys.describe(Sys.lastError()))") }
        let invite = TCPSocket(handle: client)
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

    private static func udpSocket(port: UInt16) throws -> Sys.Handle {
        let fd = Sys.udpSocket()
        guard Sys.isValid(fd) else { throw FujiError.io("socket: \(Sys.describe(Sys.lastError()))") }
        Sys.setReuseAddress(fd, port: true)
        try bindAny(fd, port: port)
        return fd
    }

    private static func tcpListener(port: UInt16) throws -> Sys.Handle {
        let fd = Sys.tcpSocket()
        guard Sys.isValid(fd) else { throw FujiError.io("socket: \(Sys.describe(Sys.lastError()))") }
        Sys.setReuseAddress(fd)
        try bindAny(fd, port: port)
        guard Sys.listen(fd, backlog: 2) else {
            let message = Sys.describe(Sys.lastError())
            Sys.close(fd)
            throw FujiError.io("listen on \(port): \(message)")
        }
        return fd
    }

    private static func bindAny(_ fd: Sys.Handle, port: UInt16) throws {
        guard Sys.bind(fd, to: Sys.anyIPv4(port: port)) else {
            let message = Sys.describe(Sys.lastError())
            Sys.close(fd)
            throw FujiError.io("port \(port) is in use (\(message)). Is Fujifilm's PC AutoSave app running?")
        }
    }
}
