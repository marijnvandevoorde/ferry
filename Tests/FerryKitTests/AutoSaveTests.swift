@testable import FerryKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif
import XCTest

/// Plays the camera's side of the PC AutoSave handshake over loopback, following vcam's ssdp.c.
final class AutoSaveTests: XCTestCase {
    var ports = AutoSaveListener.Ports()

    /// Starts a listener on random ports, below Windows' dynamic range (49152 and up), where Windows reserves
    /// blocks of ports for itself. Tries other ports when these are taken anyway.
    func startListener(clientName: String) throws -> AutoSaveListener {
        for attempt in 1...5 {
            let base = UInt16.random(in: 20000...45000)
            ports.notify = base
            ports.register = base + 1
            ports.connect = base + 2
            let listener = AutoSaveListener(clientName: clientName, ports: ports)
            do {
                try listener.start()
                return listener
            } catch where attempt < 5 {
                listener.stop()
            }
        }
        fatalError("unreachable")
    }

    func testRegister() throws {
        let listener = try startListener(clientName: "Marijn’s MacBook Pro")
        let camera = fakeCamera(discoverPort: ports.register, target: "*",
                                request: "REGISTER * HTTP/1.1\r\nHOST:127.0.0.1:\(ports.register)\r\nDSCNAME:FUJIFILM-X-H1-CA2A\r\nDSCMODEL:X-H1\r\n")
        let event = try listener.waitForCamera(timeout: 5)
        XCTAssertEqual(event, .registered(camera: "FUJIFILM-X-H1-CA2A", model: "X-H1"))
        let result = camera.wait()
        XCTAssertEqual(result.importer, "Marijn-s-MacBook-Pro")
        XCTAssertTrue(result.response.hasPrefix("HTTP/1.1 200 OK\r\nFOLDER: guest"))
    }

    func testImportRequest() throws {
        let listener = try startListener(clientName: "Mac")
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
            defer { Sys.close(notifyServer) }
            Self.sendUDP("DISCOVER \(target) HTTP/1.1\r\nMX:3\r\nHOST:192.168.1.255:|\r\nDSCADDR:127.0.0.1\r\nSERVICE:PCAUTOSAVE/1.0\r\n",
                         port: discoverPort)
            let notify = TCPSocket(handle: Sys.accept(notifyServer))
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

    private static func listen(port: UInt16) -> Sys.Handle {
        let fd = Sys.tcpSocket()
        Sys.setReuseAddress(fd)
        _ = Sys.bind(fd, to: Sys.ipv4("127.0.0.1", port: port)!)
        _ = Sys.listen(fd, backlog: 1)
        return fd
    }

    private static func sendUDP(_ message: String, port: UInt16) {
        let fd = Sys.udpSocket()
        defer { Sys.close(fd) }
        var addr = Sys.ipv4("127.0.0.1", port: port)!
        let bytes = Array(message.utf8)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, bytes, .init(bytes.count), 0, $0, .init(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
}
