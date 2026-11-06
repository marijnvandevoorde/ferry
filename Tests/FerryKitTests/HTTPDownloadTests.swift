@testable import FerryKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// Serves `StubCamera.body` in chunks, with a pause between them; `/stall` sends one chunk and never finishes,
/// `/missing` answers 404.
final class StubCamera: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    static let chunks = 10
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let body = Self.body
        let stall = url.path.hasSuffix("/stall")
        let status = url.path.hasSuffix("/missing") ? 404 : 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "\(status == 200 ? body.count : 0)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard status == 200 else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        DispatchQueue.global().async { [self] in
            let size = body.count / Self.chunks
            for i in 0..<Self.chunks {
                if isStopped { return }
                client?.urlProtocol(self, didLoad: body.subdata(in: i * size..<(i == Self.chunks - 1 ? body.count : (i + 1) * size)))
                if stall { return }
                Thread.sleep(forTimeInterval: 0.05)
            }
            if !isStopped { client?.urlProtocolDidFinishLoading(self) }
        }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

final class HTTPDownloadTests: XCTestCase {
    private var saved: URLSessionConfiguration!
    private var dir: URL!

    override func setUp() {
        saved = HTTPCamera.downloadConfiguration
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubCamera.self]
        HTTPCamera.downloadConfiguration = config
        StubCamera.body = Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        HTTPCamera.downloadConfiguration = saved
        try? FileManager.default.removeItem(at: dir)
    }

    private func camera(path: String, size: UInt32) -> GoProCamera {
        let camera = GoProCamera(host: "camera.test:8080")
        camera.files = [(path, HTTPCamera.info(index: 0, filename: "GX010001.MP4", size: size, date: nil))]
        return camera
    }

    func testProgressWhileDownloading() throws {
        let size = Int64(StubCamera.body.count)
        let camera = camera(path: "/videos/DCIM/100GOPRO/GX010001.MP4", size: UInt32(size))
        let file = dir.appendingPathComponent("GX010001.MP4")
        var reports: [(Int64, Int64)] = []
        let info = try camera.download(1, to: file) { reports.append(($0, $1)) }

        XCTAssertEqual(try Data(contentsOf: file), StubCamera.body)
        XCTAssertEqual(Int64(info.compressedSize), size)
        // Reports come while the bytes arrive, not just once at the end.
        let partial = reports.filter { $0.0 < size }
        XCTAssertGreaterThanOrEqual(partial.count, 2, "\(reports)")
        XCTAssertTrue(reports.allSatisfy { $0.1 == size }, "\(reports)")
        XCTAssertEqual(reports.map(\.0), reports.map(\.0).sorted())
        XCTAssertEqual(reports.last?.0, size)
    }

    func testUnknownSizeUsesContentLength() throws {
        let camera = camera(path: "/videos/DCIM/100GOPRO/GX010001.MP4", size: 0)
        var totals: Set<Int64> = []
        let info = try camera.download(1, to: dir.appendingPathComponent("a.MP4")) { totals.insert($1) }
        XCTAssertEqual(totals, [Int64(StubCamera.body.count)])
        XCTAssertEqual(Int(info.compressedSize), StubCamera.body.count)
    }

    func testHTTPErrorFails() {
        let camera = camera(path: "/videos/DCIM/100GOPRO/missing", size: 0)
        let file = dir.appendingPathComponent("missing")
        XCTAssertThrowsError(try camera.download(1, to: file))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
    }

    func testCancellingTheTaskStopsTheDownload() async throws {
        let serial = SerialCamera(camera(path: "/videos/DCIM/100GOPRO/stall", size: UInt32(StubCamera.body.count)))
        let file = dir.appendingPathComponent("stall")
        let started = expectation(description: "first bytes")
        nonisolated(unsafe) var fulfilled = false
        let task = Task {
            try await serial.run { camera in
                try camera.download(1, to: file) { _, _ in
                    if !fulfilled {
                        fulfilled = true
                        started.fulfill()
                    }
                }
            }
        }
        await fulfillment(of: [started], timeout: 10)
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("download finished")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [], "partial file left behind")
    }

    func testCancellingAnotherCallerLeavesTheDownloadAlone() async throws {
        let serial = SerialCamera(camera(path: "/videos/DCIM/100GOPRO/GX010001.MP4", size: UInt32(StubCamera.body.count)))
        let file = dir.appendingPathComponent("GX010001.MP4")
        let download = Task { try await serial.run { try $0.download(1, to: file) } }
        // Queued behind the download, then cancelled: must not stop it.
        let waiting = Task { try await serial.run { $0.objectHandles } }
        waiting.cancel()
        _ = try await waiting.value
        _ = try await download.value
        XCTAssertEqual(try Data(contentsOf: file), StubCamera.body)
    }
}
