@testable import FerryKit
import XCTest

/// Connects `PTPIPCamera` to a fake camera on 127.0.0.1:15740 that reads the init request and then does `answer`.
final class PTPIPConnectTests: XCTestCase {
    /// `accepted` is signalled once the fake took a connection: close the listener only after that, or a late
    /// `accept` picks up the next test's listener when it reuses the descriptor number.
    private func fakeCamera(
        accepted: DispatchSemaphore? = nil, _ answer: @escaping @Sendable (TCPSocket) -> Void
    ) throws -> Sys.Handle {
        let fd = Sys.tcpSocket()
        Sys.setReuseAddress(fd)
        guard Sys.bind(fd, to: Sys.ipv4("127.0.0.1", port: PTPIPCamera.port)!), Sys.listen(fd, backlog: 1) else {
            Sys.close(fd)
            throw XCTSkip("port \(PTPIPCamera.port) is in use")
        }
        let listener = fd
        Thread.detachNewThread {
            let client = Sys.accept(listener)
            accepted?.signal()
            guard Sys.isValid(client) else { return }
            let socket = TCPSocket(handle: client)
            socket.readTimeout = 5
            guard let header = try? socket.read(exactly: 8) else { return }
            var r = DataReader(header)
            let length = Int((try? r.u32()) ?? 8)
            _ = try? socket.read(exactly: length - 8)
            answer(socket)
        }
        return fd
    }

    func testInitFailIsItsOwnError() throws {
        let listener = try fakeCamera { socket in
            var w = DataWriter()
            w.u32(12)
            w.u32(5) // InitFail
            w.u32(0x0000_0001)
            try? socket.write(w.data)
            Thread.sleep(forTimeInterval: 1)
        }
        defer { Sys.close(listener) }
        let camera = PTPIPCamera(host: "127.0.0.1")
        XCTAssertThrowsError(try camera.connect()) { XCTAssertEqual($0 as? FujiError, .initRejected) }
    }

    func testWaitingIsReportedAndCancelStopsIt() async throws {
        let listener = try fakeCamera { _ in Thread.sleep(forTimeInterval: 10) }
        defer { Sys.close(listener) }
        let waiting = expectation(description: "waiting for approval")
        let task = Task.detached {
            try PTPIPCamera(host: "127.0.0.1").connect { waiting.fulfill() }
        }
        await fulfillment(of: [waiting], timeout: 5)
        let started = Date()
        task.cancel()
        do {
            try await task.value
            XCTFail("connected")
        } catch {
            XCTAssertEqual(error as? FujiError, .cancelled)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testAddressAnswers() throws {
        let accepted = DispatchSemaphore(value: 0)
        let listener = try fakeCamera(accepted: accepted) { _ in }
        let address = PTPIPCamera(host: "127.0.0.1").address
        XCTAssertEqual(address, CameraAddress(host: "127.0.0.1", port: PTPIPCamera.port))
        XCTAssertTrue(address!.answers(timeout: 1))
        XCTAssertEqual(accepted.wait(timeout: .now() + 5), .success)
        Sys.close(listener)
        XCTAssertFalse(address!.answers(timeout: 1))
    }
}
