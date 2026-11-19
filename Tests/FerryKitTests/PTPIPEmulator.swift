@testable import FerryKit
import Foundation

/// An in-process PTP/IP camera on 127.0.0.1, written from the public spec (CIPA DC-X005 for the transport,
/// ISO 15740 for the PTP datasets). It plays a Canon EOS, a Nikon or a plain PTP/IP camera, with the quirks real
/// cameras are reported to have switched on per test, and records what the client sent so tests can check it.
final class PTPIPEmulator: @unchecked Sendable {
    struct Object {
        var handle: UInt32
        var storage: UInt32 = 0x0001_0001
        /// 0: at the root of the card.
        var parent: UInt32 = 0
        var filename: String
        var data = Data()
        var thumbnail: Data?
        var captureDate = "20261120T101500"
        var isFolder = false

        var format: UInt16 {
            if isFolder { return 0x3001 }
            switch (filename as NSString).pathExtension.lowercased() {
            case "jpg": return 0x3801
            case "mp4", "mov": return 0x300B
            default: return 0x3000 // undefined: RAW files on most cameras
            }
        }

        static func folder(_ handle: UInt32, _ name: String, parent: UInt32 = 0, storage: UInt32 = 0x0001_0001) -> Object {
            Object(handle: handle, storage: storage, parent: parent, filename: name, isFolder: true)
        }

        static func file(_ handle: UInt32, _ name: String, size: Int, parent: UInt32 = 0, storage: UInt32 = 0x0001_0001,
                         thumbnail: Bool = true) -> Object {
            Object(handle: handle, storage: storage, parent: parent, filename: name, data: PTPIPEmulator.bytes(size, seed: handle),
                   thumbnail: thumbnail ? PTPIPEmulator.bytes(4096, seed: handle &+ 1000) : nil)
        }
    }

    struct Options {
        /// The friendly name in the InitCommandAck.
        var name = "EOS R6"
        var manufacturer = "Canon Inc."
        var model = "Canon EOS R6"
        var vendorExtensionID: UInt32 = 0x0B
        var operations: [UInt16] = PTPIPEmulator.standardOperations + [0x9114, 0x9115, 0x9116]
        /// Canon EOS: GetObjectHandles and GetStorageIDs answer DeviceBusy until SetRemoteMode(1).
        var requiresRemoteMode = false
        /// GetObjectHandles accepts storage 0xFFFFFFFF ("all storages").
        var listsAllStorages = true
        /// GetObjectHandles reads parent 0 as "the root folder" instead of "every object".
        var parentZeroIsRoot = false
        var supportsPartialObject = true
        /// Data phases are split into Data packets of this size.
        var dataChunk = 64 * 1024
        /// Waits this long before answering the init request, as a camera asking the user to allow a new device.
        var approvalDelay: TimeInterval = 0
        /// Answers the init request with InitFail and this reason.
        var initFailReason: UInt32?
        /// Sends a ProbeRequest on the event channel before answering each GetPartialObject.
        var probesDuringTransfer = false

        static func canonEOS() -> Options {
            var o = Options()
            o.requiresRemoteMode = true
            return o
        }

        static func nikon() -> Options {
            var o = Options()
            o.name = "D750"
            o.manufacturer = "Nikon Corporation"
            o.model = "D750"
            o.vendorExtensionID = 0x0A
            o.operations = PTPIPEmulator.standardOperations
            return o
        }
    }

    static let standardOperations: [UInt16] = [0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1007, 0x1008, 0x1009, 0x100A, 0x101B]
    static let guid: [UInt8] = Array(0..<16).map { UInt8($0) &* 17 }
    static let connectionNumber: UInt32 = 7

    /// What the client sent.
    struct Received {
        var clientGUID: [UInt8] = []
        var clientName = ""
        var protocolVersion: UInt32 = 0
        var eventConnectionNumber: UInt32?
        var operations: [UInt16] = []
        var params: [[UInt32]] = []
        var transactionIDs: [UInt32] = []
        var probeResponses = 0
        var remoteMode: UInt32?
        var eventMode: UInt32?
    }

    let port: UInt16
    var options: Options
    private var objects: [Object]
    private let lock = NSLock()
    private var received = Received()
    private var listener: Sys.Handle
    private var stopped = false
    private var command: TCPSocket?
    private var events: TCPSocket?
    private var sessionOpen = false

    init(objects: [Object], options: Options = Options()) throws {
        self.objects = objects
        self.options = options
        var bound: (Sys.Handle, UInt16)?
        for _ in 0..<50 {
            let port = UInt16.random(in: 20000...60000)
            let fd = Sys.tcpSocket()
            Sys.setReuseAddress(fd)
            if Sys.bind(fd, to: Sys.ipv4("127.0.0.1", port: port)!), Sys.listen(fd, backlog: 2) {
                bound = (fd, port)
                break
            }
            Sys.close(fd)
        }
        guard let bound else { throw FujiError.connectionFailed("no free port for the emulator") }
        (listener, port) = bound
        Thread.detachNewThread { [self] in serve() }
    }

    var log: Received { lock.withLock { received } }

    func stop() {
        lock.withLock { stopped = true }
        command?.close()
        events?.close()
        Sys.close(listener)
    }

    /// Puts a new photo on the card and announces it with an ObjectAdded event.
    func add(_ object: Object) {
        lock.withLock { objects.append(object) }
        var w = DataWriter()
        w.u16(0x4002)
        w.u32(0xFFFF_FFFF)
        w.u32(object.handle)
        try? events.map { try Self.send(8, w.data, on: $0) }
    }

    // MARK: - Connections

    private var isStopped: Bool { lock.withLock { stopped } }

    /// Waits for a connection in short steps, so `stop()` ends the thread.
    private func accept() -> TCPSocket? {
        while !isStopped {
            if Sys.wait([listener], timeout: 0.2).isEmpty { continue }
            let client = Sys.accept(listener)
            guard Sys.isValid(client) else { return nil }
            let socket = TCPSocket(handle: client)
            socket.readTimeout = 10
            return socket
        }
        return nil
    }

    private func serve() {
        guard let cmd = accept() else { return }
        command = cmd
        guard let (type, request) = try? Self.read(cmd), type == 1 else { return }
        var r = DataReader(request)
        var guid: [UInt8] = []
        for _ in 0..<16 { guid.append((try? r.u8()) ?? 0) }
        var units: [UInt16] = []
        while let u = try? r.u16(), u != 0 { units.append(u) }
        let version = (try? r.u32()) ?? 0
        lock.withLock {
            received.clientGUID = guid
            received.clientName = String(decoding: units, as: UTF16.self)
            received.protocolVersion = version
        }
        if let reason = options.initFailReason {
            var w = DataWriter()
            w.u32(reason)
            try? Self.send(5, w.data, on: cmd)
            return
        }
        if options.approvalDelay > 0 { Thread.sleep(forTimeInterval: options.approvalDelay) }

        var ack = DataWriter()
        ack.u32(Self.connectionNumber)
        ack.data.append(contentsOf: Self.guid)
        for unit in options.name.utf16 { ack.u16(unit) }
        ack.u16(0)
        ack.u32(0x0001_0000)
        guard (try? Self.send(2, ack.data, on: cmd)) != nil else { return }

        guard let evt = accept() else { return }
        events = evt
        guard let (eventType, eventRequest) = try? Self.read(evt), eventType == 3 else { return }
        var e = DataReader(eventRequest)
        let number = try? e.u32()
        lock.withLock { received.eventConnectionNumber = number }
        guard (try? Self.send(number == Self.connectionNumber ? 4 : 5, Data(), on: evt)) != nil else { return }
        Thread.detachNewThread { [self] in readEvents(evt) }

        while !isStopped, let (type, payload) = try? Self.read(cmd) {
            guard type == 6 else { continue } // only operation requests come from the client
            var p = DataReader(payload)
            guard let _ = try? p.u32(), let op = try? p.u16(), let tid = try? p.u32() else { return }
            var params: [UInt32] = []
            while let v = try? p.u32() { params.append(v) }
            lock.withLock {
                received.operations.append(op)
                received.params.append(params)
                received.transactionIDs.append(tid)
            }
            let (code, data, responseParams) = handle(op, params)
            if let data {
                guard (try? sendData(data, tid: tid, on: cmd)) != nil else { return }
            }
            var w = DataWriter()
            w.u16(code)
            w.u32(tid)
            responseParams.forEach { w.u32($0) }
            guard (try? Self.send(7, w.data, on: cmd)) != nil else { return }
        }
    }

    private func readEvents(_ evt: TCPSocket) {
        while !isStopped, let (type, _) = try? Self.read(evt) {
            if type == 14 { lock.withLock { received.probeResponses += 1 } }
        }
    }

    // MARK: - Operations

    private func handle(_ op: UInt16, _ params: [UInt32]) -> (UInt16, Data?, [UInt32]) {
        let ok: UInt16 = 0x2001
        guard options.operations.contains(op) else { return (0x2005, nil, []) }
        let remoteMode = lock.withLock { received.remoteMode }
        let busy = options.requiresRemoteMode && remoteMode != 1
        switch op {
        case 0x1001:
            return (ok, deviceInfo(), [])
        case 0x1002:
            defer { sessionOpen = true }
            return (sessionOpen ? 0x201E : ok, nil, [])
        case 0x1003:
            sessionOpen = false
            return (ok, nil, [])
        case 0x1004:
            if busy { return (0x2019, nil, []) }
            return (ok, Self.array(Array(Set(currentObjects.map(\.storage))).sorted()), [])
        case 0x1007:
            if busy { return (0x2019, nil, []) }
            let storage = params.first ?? 0, parent = params.count > 2 ? params[2] : 0
            if storage == 0xFFFF_FFFF && !options.listsAllStorages { return (0x2008, nil, []) }
            let matches = currentObjects.filter { object in
                guard storage == 0xFFFF_FFFF || object.storage == storage else { return false }
                switch parent {
                case 0 where !options.parentZeroIsRoot: return true
                case 0, 0xFFFF_FFFF: return object.parent == 0
                default: return object.parent == parent
                }
            }
            return (ok, Self.array(matches.map(\.handle)), [])
        case 0x1008:
            guard let object = object(params.first) else { return (0x2009, nil, []) }
            return (ok, objectInfo(object), [])
        case 0x1009:
            guard let object = object(params.first) else { return (0x2009, nil, []) }
            return (ok, object.data, [])
        case 0x100A:
            guard let object = object(params.first) else { return (0x2009, nil, []) }
            guard let thumb = object.thumbnail else { return (0x2010, nil, []) } // NoThumbnailPresent
            return (ok, thumb, [])
        case 0x101B:
            guard options.supportsPartialObject else { return (0x2005, nil, []) }
            guard let object = object(params.first), params.count >= 3 else { return (0x2009, nil, []) }
            if options.probesDuringTransfer, let events {
                try? Self.send(13, Data(), on: events)
            }
            let start = min(Int(params[1]), object.data.count)
            let end = min(start + Int(params[2]), object.data.count)
            let slice = object.data.subdata(in: start..<end)
            return (ok, slice, [UInt32(slice.count)])
        case 0x9114:
            lock.withLock { received.remoteMode = params.first }
            return (ok, nil, [])
        case 0x9115:
            lock.withLock { received.eventMode = params.first }
            return (ok, nil, [])
        case 0x9116:
            // An empty EOS event list: one record of size 8, type 0 (terminator).
            var w = DataWriter()
            w.u32(8)
            w.u32(0)
            return (ok, w.data, [])
        default:
            return (0x2005, nil, [])
        }
    }

    private var currentObjects: [Object] { lock.withLock { objects } }

    private func object(_ handle: UInt32?) -> Object? {
        currentObjects.first { $0.handle == handle }
    }

    private func deviceInfo() -> Data {
        var w = DataWriter()
        w.u16(100) // PTP 1.00
        w.u32(options.vendorExtensionID)
        w.u16(100)
        Self.string(options.vendorExtensionID == 0x0B ? "Canon" : "", into: &w)
        w.u16(0)
        w.data.append(Self.array16(options.operations))
        w.data.append(Self.array16([0x4002]))
        w.data.append(Self.array16([0x5001]))
        w.data.append(Self.array16([]))
        w.data.append(Self.array16([0x3801, 0x3000]))
        Self.string(options.manufacturer, into: &w)
        Self.string(options.model, into: &w)
        Self.string("1.0.0", into: &w)
        Self.string("0123456789", into: &w)
        return w.data
    }

    private func objectInfo(_ object: Object) -> Data {
        var w = DataWriter()
        w.u32(object.storage)
        w.u16(object.format)
        w.u16(0) // protection
        w.u32(UInt32(object.data.count))
        w.u16(object.thumbnail == nil ? 0 : 0x3801)
        w.u32(UInt32(object.thumbnail?.count ?? 0))
        w.u32(160)
        w.u32(120)
        w.u32(object.isFolder ? 0 : 6000)
        w.u32(object.isFolder ? 0 : 4000)
        w.u32(object.isFolder ? 0 : 24)
        w.u32(object.parent)
        w.u16(object.isFolder ? 1 : 0) // association type: generic folder
        w.u32(0)
        w.u32(0)
        Self.string(object.filename, into: &w)
        Self.string(object.isFolder ? "" : object.captureDate, into: &w)
        Self.string("", into: &w)
        Self.string("", into: &w)
        return w.data
    }

    // MARK: - Encoding

    /// StartData with the total length, then Data packets, the last piece in EndData.
    private func sendData(_ data: Data, tid: UInt32, on socket: TCPSocket) throws {
        var start = DataWriter()
        start.u32(tid)
        start.u32(UInt32(data.count))
        start.u32(0)
        try Self.send(9, start.data, on: socket)
        var offset = 0
        repeat {
            let end = min(offset + options.dataChunk, data.count)
            var w = DataWriter()
            w.u32(tid)
            w.data.append(data.subdata(in: offset..<end))
            try Self.send(end == data.count ? 12 : 10, w.data, on: socket)
            offset = end
        } while offset < data.count
    }

    static func send(_ type: UInt32, _ payload: Data, on socket: TCPSocket) throws {
        var w = DataWriter()
        w.u32(UInt32(8 + payload.count))
        w.u32(type)
        w.data.append(payload)
        try socket.write(w.data)
    }

    static func read(_ socket: TCPSocket) throws -> (UInt32, Data) {
        var h = DataReader(try socket.read(exactly: 8))
        let length = Int(try h.u32()), type = try h.u32()
        return (type, length > 8 ? try socket.read(exactly: length - 8) : Data())
    }

    static func array(_ values: [UInt32]) -> Data {
        var w = DataWriter()
        w.u32(UInt32(values.count))
        values.forEach { w.u32($0) }
        return w.data
    }

    static func array16(_ values: [UInt16]) -> Data {
        var w = DataWriter()
        w.u32(UInt32(values.count))
        values.forEach { w.u16($0) }
        return w.data
    }

    static func string(_ s: String, into w: inout DataWriter) {
        guard !s.isEmpty else { w.u8(0); return }
        let units = Array(s.utf16)
        w.u8(UInt8(units.count + 1))
        units.forEach { w.u16($0) }
        w.u16(0)
    }

    static func bytes(_ count: Int, seed: UInt32) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed) &* 7) })
    }
}
