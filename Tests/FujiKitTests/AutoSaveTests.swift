@testable import FujiKit
import Darwin
import XCTest

/// Plays the camera's side of the PC AutoSave handshake over loopback, following vcam's ssdp.c.
final class AutoSaveTests: XCTestCase {
    var ports = AutoSaveListener.Ports()

    override func setUp() {
        let base = UInt16.random(in: 40000...60000)
        ports.notify = base
        ports.register = base + 1
        ports.connect = base + 2
    }

    func testRegister() throws {
        let listener = AutoSaveListener(clientName: "Marijn’s MacBook Pro", ports: ports)
        try listener.start()
        let camera = fakeCamera(discoverPort: ports.register, target: "*",
                                request: "REGISTER * HTTP/1.1\r\nHOST:127.0.0.1:\(ports.register)\r\nDSCNAME:FUJIFILM-X-H1-CA2A\r\nDSCMODEL:X-H1\r\n")
        let event = try listener.waitForCamera(timeout: 5)
        XCTAssertEqual(event, .registered(camera: "FUJIFILM-X-H1-CA2A", model: "X-H1"))
        let result = camera.wait()
        XCTAssertEqual(result.importer, "Marijn-s-MacBook-Pro")
        XCTAssertTrue(result.response.hasPrefix("HTTP/1.1 200 OK\r\nFOLDER: guest"))
    }

    func testImportRequest() throws {
        let listener = AutoSaveListener(clientName: "Mac", ports: ports)
        try listener.start()
        let camera = fakeCamera(discoverPort: ports.connect, target: "desktop",
                                request: "IMPORT /guest HTTP/1.1\r\nHOST:127.0.0.1:\(ports.connect)\r\nDSCNAME:VCAM\r\nDSCPORT:$\r\n")
        let event = try listener.waitForCamera(timeout: 5)
        XCTAssertEqual(event, .importRequest(host: "127.0.0.1", camera: "VCAM"))
        let result = camera.wait()
        XCTAssertEqual(result.importer, "desktop")
        XCTAssertEqual(result.response, "HTTP/1.1 200 OK\r\n")
    }

    func testParse() {
        let f = AutoSaveListener.parse("DISCOVER desktop HTTP/1.1\r\nMX:3\r\nHOST:192.168.1.255:|\r\nDSCADDR:192.168.1.32\r\n")
        XCTAssertEqual(f["DISCOVER"], "desktop")
        XCTAssertEqual(f["DSCADDR"], "192.168.1.32")
        XCTAssertEqual(f["HOST"], "192.168.1.255:|")
    }

    // MARK: - Fake camera

    final class Result: @unchecked Sendable {
        var importer = ""
        var response = ""
        let done = DispatchSemaphore(value: 0)
        func wait() -> Result {
            _ = done.wait(timeout: .now() + 10)
            return self
        }
    }

    private func fakeCamera(discoverPort: UInt16, target: String, request: String) -> Result {
        let result = Result()
        let ports = self.ports
        Thread.detachNewThread {
            defer { result.done.signal() }
            let notifyServer = Self.listen(port: ports.notify)
            defer { close(notifyServer) }
            Self.sendUDP("DISCOVER \(target) HTTP/1.1\r\nMX:3\r\nHOST:192.168.1.255:|\r\nDSCADDR:127.0.0.1\r\nSERVICE:PCAUTOSAVE/1.0\r\n",
                         port: discoverPort)
            let client = accept(notifyServer, nil, nil)
            let notify = TCPSocket(fd: client)
            guard let message = try? notify.readAvailable() else { return }
            result.importer = AutoSaveListener.parse(message)["IMPORTER"] ?? ""
            try? notify.write(Data("HTTP/1.1 200 OK\r\n".utf8))
            notify.close()

            guard let invite = try? TCPSocket(host: "127.0.0.1", port: discoverPort, connectTimeout: 5) else { return }
            try? invite.write(Data(request.utf8))
            result.response = (try? invite.readAvailable()) ?? ""
        }
        return result
    }

    private static func listen(port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        Darwin.listen(fd, 1)
        return fd
    }

    private static func sendUDP(_ message: String, port: UInt16) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bytes = Array(message.utf8)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
}
