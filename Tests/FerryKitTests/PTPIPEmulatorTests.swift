@testable import FerryKit
import XCTest

/// The whole import flow (connect, list, thumbnails, download) against `PTPIPEmulator` playing Canon and Nikon.
final class PTPIPEmulatorTests: XCTestCase {
    /// A card as Canon and Nikon write it: DCIM, one folder of photos, a JPEG bigger than one GetPartialObject
    /// piece, a RAW file and a video.
    static func card(folder: String = "100CANON", storage: UInt32 = 0x0001_0001, base: UInt32 = 1) -> [PTPIPEmulator.Object] {
        [
            .folder(base, "DCIM", storage: storage),
            .folder(base + 1, folder, parent: base, storage: storage),
            .file(base + 2, "IMG_0001.JPG", size: Int(PTP.maxPartialObject) * 2 + 12345, parent: base + 1, storage: storage),
            .file(base + 3, "IMG_0002.CR3", size: 300_000, parent: base + 1, storage: storage),
            .file(base + 4, "MVI_0003.MP4", size: 70_000, parent: base + 1, storage: storage, thumbnail: false),
        ]
    }

    private var emulators: [PTPIPEmulator] = []
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("ptpip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        emulators.forEach { $0.stop() }
        try? FileManager.default.removeItem(at: temp)
    }

    private func emulator(_ options: PTPIPEmulator.Options, objects: [PTPIPEmulator.Object] = card()) throws -> PTPIPEmulator {
        let e = try PTPIPEmulator(objects: objects, options: options)
        emulators.append(e)
        return e
    }

    private func makeCamera(_ emulator: PTPIPEmulator) -> PTPIPCamera {
        PTPIPCamera(host: "127.0.0.1", port: emulator.port, clientName: "Ferry test")
    }

    /// The files the app would show: everything listed except folders.
    private func files(_ camera: PTPIPCamera) throws -> [ObjectInfo] {
        try camera.objectHandles.map { try camera.objectInfo($0) }.filter { !$0.isFolder }
    }

    func testCanonEOSFlow() throws {
        let e = try emulator(PTPIPEmulator.Options.canonEOS())
        let camera = makeCamera(e)
        try camera.connect()
        defer { camera.disconnect() }

        // Handshake: our GUID, name and protocol version 1.0; the event channel names the same connection.
        XCTAssertEqual(e.log.clientGUID, PTPIPCamera.guid)
        XCTAssertEqual(e.log.clientName, "Ferry test")
        XCTAssertEqual(e.log.protocolVersion, 0x0001_0000)
        XCTAssertEqual(e.log.eventConnectionNumber, PTPIPEmulator.connectionNumber)
        XCTAssertEqual(camera.cameraName, "EOS R6")
        XCTAssertEqual(camera.vendor, .canon)

        // EOS lists files only in remote mode.
        XCTAssertEqual(e.log.remoteMode, 1)
        XCTAssertEqual(e.log.eventMode, 1)
        XCTAssertEqual(e.log.operations.prefix(3), [PTP.Op.openSession, PTP.Op.getDeviceInfo, PTPIPCamera.Op.canonEOSSetRemoteMode])

        let infos = try files(camera)
        XCTAssertEqual(infos.map(\.filename), ["IMG_0001.JPG", "IMG_0002.CR3", "MVI_0003.MP4"])
        XCTAssertEqual(infos.map(\.kind), [.jpeg, .raw, .video])
        XCTAssertEqual(infos[0].date, ISO8601DateFormatter.local("2026-11-20T10:15:00"))

        XCTAssertEqual(try camera.thumbnail(3), PTPIPEmulator.bytes(4096, seed: 1003))
        XCTAssertNil(try camera.thumbnail(5))

        let photo = temp.appendingPathComponent("IMG_0001.JPG")
        var last: (Int64, Int64) = (0, 0)
        try camera.download(3, to: photo) { last = ($0, $1) }
        let expected = PTPIPEmulator.bytes(Int(PTP.maxPartialObject) * 2 + 12345, seed: 3)
        XCTAssertEqual(try Data(contentsOf: photo), expected)
        XCTAssertEqual(last.0, Int64(expected.count))
        XCTAssertEqual(last.1, Int64(expected.count))
        XCTAssertEqual(e.log.operations.filter { $0 == PTP.Op.getPartialObject }.count, 3)

        camera.disconnect()
        XCTAssertEqual(e.log.operations.last, PTP.Op.closeSession)
        // OpenSession is transaction 0, then 1, 2, 3, …
        XCTAssertEqual(e.log.transactionIDs, Array(0..<UInt32(e.log.transactionIDs.count)))
    }

    func testNikonWithoutPartialObjectUsesGetObject() throws {
        var options = PTPIPEmulator.Options.nikon()
        options.operations.removeAll { $0 == PTP.Op.getPartialObject }
        options.supportsPartialObject = false
        let e = try emulator(options, objects: Self.card(folder: "100D750"))
        let camera = makeCamera(e)
        try camera.connect()
        defer { camera.disconnect() }

        XCTAssertEqual(camera.vendor, .nikon)
        XCTAssertNil(e.log.remoteMode)
        XCTAssertEqual(try files(camera).count, 3)
        let raw = temp.appendingPathComponent("IMG_0002.NEF")
        try camera.download(4, to: raw)
        XCTAssertEqual(try Data(contentsOf: raw), PTPIPEmulator.bytes(300_000, seed: 4))
        XCTAssertFalse(e.log.operations.contains(PTP.Op.getPartialObject))
        XCTAssertTrue(e.log.operations.contains(PTP.Op.getObject))
    }

    /// A camera whose operation list claims GetPartialObject but refuses it: dropped after the first refusal.
    func testRefusedPartialObjectFallsBackToGetObject() throws {
        var options = PTPIPEmulator.Options.nikon()
        options.supportsPartialObject = false
        let e = try emulator(options)
        let camera = makeCamera(e)
        try camera.connect()
        defer { camera.disconnect() }

        for handle: UInt32 in [4, 5] {
            try camera.download(handle, to: temp.appendingPathComponent("\(handle)"))
        }
        XCTAssertEqual(try Data(contentsOf: temp.appendingPathComponent("5")), PTPIPEmulator.bytes(70_000, seed: 5))
        XCTAssertEqual(e.log.operations.filter { $0 == PTP.Op.getPartialObject }.count, 1)
    }

    /// Two card slots, and a camera that won't list "all storages" at once.
    func testListsEachStorageWhenAllStoragesIsRefused() throws {
        var options = PTPIPEmulator.Options.nikon()
        options.listsAllStorages = false
        let objects = Self.card(folder: "100D750") + Self.card(folder: "100D750", storage: 0x0002_0001, base: 11)
        let e = try emulator(options, objects: objects)
        let camera = makeCamera(e)
        try camera.connect()
        defer { camera.disconnect() }

        XCTAssertEqual(try files(camera).count, 6)
        XCTAssertTrue(e.log.operations.contains(PTPIPCamera.Op.getStorageIDs))
    }

    func testWalksFoldersWhenParentZeroMeansRoot() throws {
        var options = PTPIPEmulator.Options.canonEOS()
        options.parentZeroIsRoot = true
        let e = try emulator(options)
        let camera = makeCamera(e)
        try camera.connect()
        defer { camera.disconnect() }

        XCTAssertEqual(try files(camera).map(\.filename), ["IMG_0001.JPG", "IMG_0002.CR3", "MVI_0003.MP4"])
    }

    func testProbesDuringDownloadAreAnswered() throws {
        var options = PTPIPEmulator.Options.canonEOS()
        options.probesDuringTransfer = true
        let e = try emulator(options)
        let camera = makeCamera(e)
        try camera.connect()
        defer { camera.disconnect() }

        try camera.download(3, to: temp.appendingPathComponent("a.jpg"))
        let deadline = Date().addingTimeInterval(2)
        while e.log.probeResponses < 2 && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertGreaterThanOrEqual(e.log.probeResponses, 2)
    }

    func testNewPhotoShowsUpOnRefresh() throws {
        let e = try emulator(PTPIPEmulator.Options.canonEOS())
        let camera = makeCamera(e)
        try camera.connect()
        defer { camera.disconnect() }

        XCTAssertEqual(try camera.refreshObjectCount(), 5)
        e.add(.file(6, "IMG_0004.JPG", size: 1000, parent: 2))
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(try camera.refreshObjectCount(), 6)
        XCTAssertTrue(e.log.operations.contains(PTPIPCamera.Op.canonEOSGetEvent))
    }

    func testBusyCameraIsRejected() throws {
        var options = PTPIPEmulator.Options.nikon()
        options.initFailReason = 2
        let e = try emulator(options)
        XCTAssertThrowsError(try makeCamera(e).connect()) { XCTAssertEqual($0 as? FujiError, .initRejected) }
    }

    func testWaitsWhileTheCameraAsksTheUser() throws {
        var options = PTPIPEmulator.Options.canonEOS()
        options.approvalDelay = 1.5
        let e = try emulator(options)
        let camera = makeCamera(e)
        var asked = false
        try camera.connect { asked = true }
        defer { camera.disconnect() }
        XCTAssertTrue(asked)
        XCTAssertTrue(camera.isConnected)
    }

    func testAddressUsesTheCameraPort() throws {
        let e = try emulator(PTPIPEmulator.Options.nikon())
        XCTAssertEqual(makeCamera(e).address, CameraAddress(host: "127.0.0.1", port: e.port))
    }
}

private extension ISO8601DateFormatter {
    static func local(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        f.timeZone = .current
        return f.date(from: string)
    }
}
