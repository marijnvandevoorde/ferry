import Foundation

/// A camera speaking standard PTP/IP (CIPA DC-X005, PTP over TCP port 15740), as Canon, Nikon, Sony and others do
/// when connected to a computer or phone app over Wi-Fi.
///
/// Only the standard operations needed for importing are used: OpenSession, GetObjectHandles, GetObjectInfo,
/// GetThumb and GetPartialObject (or GetObject when partial transfers aren't supported), plus Canon EOS's
/// SetRemoteMode/SetEventMode/GetEvent, which EOS cameras expect from a computer before they hand over their files.
/// Brand-specific pairing (Canon's EOS Utility pairing, Nikon SnapBridge, Sony's authentication) is not handled;
/// this works with cameras that accept a plain PTP/IP session, possibly after the user confirms it on the camera.
/// Experimental: tested against emulators only (`PTPIPEmulator` in the tests, vcam), never on a real Canon or Nikon.
public final class PTPIPCamera: @unchecked Sendable {
    public static let port: UInt16 = 15740

    public let host: String
    public let port: UInt16
    public let interface: String?
    public let clientName: String
    public var log: (String) -> Void

    public private(set) var cameraName = ""
    public private(set) var isConnected = false
    public private(set) var objectHandles: [UInt32] = []
    /// What the camera said about itself at connect time, when it answered GetDeviceInfo.
    private(set) var deviceInfo: DeviceInfo?

    /// The camera maker, from its PTP vendor extension or manufacturer name.
    public enum Vendor: String, Sendable {
        case canon, nikon, sony, other

        /// PTP vendor extension IDs (PIMA 15740 registry).
        static let nikonID: UInt32 = 0x0A
        static let canonID: UInt32 = 0x0B
        static let sonyID: UInt32 = 0x11
    }

    public var vendor: Vendor {
        guard let info = deviceInfo else { return .other }
        switch info.vendorExtensionID {
        case Vendor.canonID: return .canon
        case Vendor.nikonID: return .nikon
        case Vendor.sonyID: return .sony
        default:
            let maker = info.manufacturer.lowercased()
            if maker.contains("canon") { return .canon }
            if maker.contains("nikon") { return .nikon }
            if maker.contains("sony") { return .sony }
            return .other
        }
    }

    private var cmd: TCPSocket?
    private var events: TCPSocket?
    private var transaction: UInt32 = 0
    private var supportsPartialObject = true
    /// Canon EOS cameras queue their events until the computer asks with GetEvent.
    private var pollsCanonEvents = false

    /// Fixed client GUID, so cameras that remember paired clients recognize us next time.
    static let guid: [UInt8] = [0x46, 0x75, 0x6A, 0x69, 0x49, 0x6D, 0x70, 0x6F, 0x72, 0x74, 0x00, 0x01, 0x8A, 0x3C, 0x5E, 0x21]

    enum PacketType: UInt32 {
        case initCommandRequest = 1, initCommandAck, initEventRequest, initEventAck, initFail
        case operationRequest, operationResponse, event, startData, data, cancel, endData
        /// Either side may ask whether the other is still there; the answer is a ProbeResponse.
        case probeRequest, probeResponse
    }

    /// Operations beyond the ones in `PTP.Op`.
    enum Op {
        static let getStorageIDs: UInt16 = 0x1004
        static let canonEOSSetRemoteMode: UInt16 = 0x9114
        static let canonEOSSetEventMode: UInt16 = 0x9115
        static let canonEOSGetEvent: UInt16 = 0x9116
    }

    /// PTP event: a new object (photo) is on the card.
    static let objectAddedEvent: UInt16 = 0x4002

    public init(host: String, port: UInt16 = PTPIPCamera.port, interface: String? = nil, clientName: String = "Ferry",
                log: @escaping (String) -> Void = { _ in }) {
        self.host = host
        self.port = port
        self.interface = interface
        self.clientName = clientName
        self.log = { Trace.shared.note($0); log($0) }
    }

    // MARK: - Connection

    /// How long to wait for the camera to answer the init request; cameras that ask the user to accept a new
    /// device answer only after that.
    static let approvalTimeout: TimeInterval = 120

    /// `onWaitingForApproval` is called when the camera doesn't answer the init request right away: it may be
    /// asking the user whether to allow this computer. Throws `FujiError.cancelled` when the calling task is
    /// cancelled while waiting, and `FujiError.initRejected` when the camera refuses the connection.
    public func connect(onWaitingForApproval: () -> Void = {}) throws {
        try Trace.shared.connecting("ptpip", host: host, port: Int(port)) {
            try connectSteps(onWaitingForApproval: onWaitingForApproval)
        }
    }

    private func connectSteps(onWaitingForApproval: () -> Void) throws {
        log("Connecting to \(host):\(port) (PTP/IP)" + (interface.map { " via \($0)" } ?? ""))
        let cmd = try TCPSocket(host: host, port: port, interface: interface, connectTimeout: 5)
        self.cmd = cmd
        Trace.shared.stage(.reached)

        // Init command request: GUID, friendly name (UTF-16LE, NUL-terminated), protocol version 1.0.
        var w = DataWriter()
        w.data.append(contentsOf: Self.guid)
        for unit in clientName.prefix(39).utf16 { w.u16(unit) }
        w.u16(0)
        w.u32(0x0001_0000)
        try writePacket(.initCommandRequest, w.data, to: cmd)
        try waitForInitAnswer(on: cmd, onWaitingForApproval: onWaitingForApproval)
        cmd.readTimeout = 10
        let (type, ack) = try readPacket(from: cmd)
        Trace.shared.raw("ptpip", channel: type == .initFail ? "initFail" : "initCommandAck", received: ack)
        if type == .initFail {
            var r = DataReader(ack)
            let reason = try? r.u32()
            log("The camera refused the connection (PTP/IP InitFail, reason \(Self.describeInitFail(reason)))")
            throw FujiError.initRejected
        }
        guard type == .initCommandAck else { throw FujiError.protocolError("expected init ack, got \(type)") }
        var r = DataReader(ack)
        let connectionNumber = try r.u32()
        r.offset += 16 // camera GUID
        var units: [UInt16] = []
        while r.remaining >= 2, let u = try? r.u16(), u != 0 { units.append(u) }
        cameraName = String(decoding: units, as: UTF16.self)
        log("Connected to \(cameraName)")
        Trace.shared.identified(camera: cameraName, protocolName: "ptpip")

        // The event channel: a second connection announcing the same connection number.
        let events = try TCPSocket(host: host, port: port, interface: interface, connectTimeout: 5)
        self.events = events
        var e = DataWriter()
        e.u32(connectionNumber)
        try writePacket(.initEventRequest, e.data, to: events)
        events.readTimeout = 10
        let (eventAck, eventPayload) = try readPacket(from: events)
        if eventAck == .initFail {
            var r = DataReader(eventPayload)
            log("The camera refused the event channel (PTP/IP InitFail, reason \(Self.describeInitFail(try? r.u32())))")
            throw FujiError.initRejected
        }
        guard eventAck == .initEventAck else { throw FujiError.protocolError("expected event ack, got \(eventAck)") }

        // The PTP transaction ID starts at 0 for OpenSession; the camera expects 1, 2, … after that.
        transaction = 0
        let open = try transact(PTP.Op.openSession, [1], allowFailure: true)
        guard open.code == PTP.Response.ok || open.code == PTP.Response.sessionAlreadyOpen else {
            throw FujiError.response(op: PTP.Op.openSession, code: open.code)
        }
        isConnected = true
        Trace.shared.stage(.session)
        // What the camera is and which operations it supports. Every PTP camera must answer this.
        let info = try transact(PTP.Op.getDeviceInfo, [], allowFailure: true)
        if info.code == PTP.Response.ok, let parsed = try? DeviceInfo.parse(info.data) {
            deviceInfo = parsed
            log("Camera: \(parsed.manufacturer) \(parsed.model), firmware \(parsed.version)")
            if cameraName.isEmpty { cameraName = parsed.model }
            // An empty list means the camera didn't say; then GetPartialObject is tried and dropped if refused.
            if !parsed.operations.isEmpty, !parsed.operations.contains(PTP.Op.getPartialObject) {
                supportsPartialObject = false
            }
        }
        try prepareVendorSession()
        try loadHandles()
        log("Ready: \(objectHandles.count) objects")
        Trace.shared.stage(.approved, "\(objectHandles.count) objects")
    }

    /// Canon EOS cameras only list their files to a computer in "remote mode", and queue events until asked.
    /// EOS Utility and libgphoto2 both switch these on right after OpenSession; refusals are logged, not fatal.
    private func prepareVendorSession() throws {
        guard vendor == .canon, let ops = deviceInfo?.operations else { return }
        if ops.contains(Op.canonEOSSetRemoteMode) {
            let r = try transact(Op.canonEOSSetRemoteMode, [1], allowFailure: true)
            if r.code != PTP.Response.ok { log(String(format: "Canon SetRemoteMode answered 0x%04X", r.code)) }
        }
        if ops.contains(Op.canonEOSSetEventMode) {
            let r = try transact(Op.canonEOSSetEventMode, [1], allowFailure: true)
            if r.code != PTP.Response.ok { log(String(format: "Canon SetEventMode answered 0x%04X", r.code)) }
        }
        pollsCanonEvents = ops.contains(Op.canonEOSGetEvent)
        try pollCanonEvents()
    }

    /// Fetches (and drops) Canon EOS's queued events: property changes and new objects, which a reload picks up.
    private func pollCanonEvents() throws {
        guard pollsCanonEvents else { return }
        _ = try transact(Op.canonEOSGetEvent, [], allowFailure: true)
    }

    static func describeInitFail(_ reason: UInt32?) -> String {
        switch reason {
        case 1: "0x00000001, this computer was rejected; the camera may need it paired first"
        case 2: "0x00000002, the camera is busy, perhaps connected to another device"
        case let code?: String(format: "0x%08X", code)
        case nil: "none"
        }
    }

    /// Waits for the answer to the init request in short steps, so a cancelled task stops waiting. Reports
    /// waiting for approval when the answer doesn't come within a second.
    private func waitForInitAnswer(on cmd: TCPSocket, onWaitingForApproval: () -> Void) throws {
        let deadline = Date().addingTimeInterval(Self.approvalTimeout)
        var reported = false
        while !cmd.waitReadable(timeout: 1) {
            if Task.isCancelled {
                log("Stopped waiting for the camera")
                throw FujiError.cancelled
            }
            guard Date() < deadline else { throw FujiError.timeout }
            if !reported {
                reported = true
                log("Waiting for the camera to answer; it may be asking whether to allow this computer")
                onWaitingForApproval()
            }
        }
        if Task.isCancelled { throw FujiError.cancelled }
    }

    public func disconnect() {
        if isConnected {
            cmd?.readTimeout = 2
            _ = try? transact(PTP.Op.closeSession, [], allowFailure: true)
        }
        cmd?.close()
        events?.close()
        cmd = nil
        events = nil
        isConnected = false
        log("Disconnected")
    }

    /// Reloads the object list (all storages, all formats). Folders stay in the list; callers skip them.
    public func loadHandles() throws {
        let all = try transact(PTP.Op.getObjectHandles, [0xFFFF_FFFF, 0, 0], allowFailure: true)
        var handles: [UInt32]
        if all.code == PTP.Response.ok {
            handles = try Self.handleArray(all.data)
        } else {
            // Not every camera takes "all storages": ask each card slot.
            log(String(format: "GetObjectHandles for all storages answered 0x%04X; listing each storage", all.code))
            handles = []
            for storage in try storageIDs() {
                handles += try Self.handleArray(try transact(PTP.Op.getObjectHandles, [storage, 0, 0]).data)
            }
        }
        objectHandles = try withFolderContents(handles)
    }

    private func storageIDs() throws -> [UInt32] {
        try Self.handleArray(try transact(Op.getStorageIDs, []).data)
    }

    /// Parent 0 means "every object" in PTP, but some cameras read it as "the root folder" and list only DCIM.
    /// A short list of nothing but folders gives that away: then the folders are walked, a few levels deep.
    private func withFolderContents(_ handles: [UInt32], depth: Int = 0) throws -> [UInt32] {
        guard !handles.isEmpty, handles.count <= 16, depth < 4 else { return handles }
        var formats: [UInt32: UInt16] = [:]
        for handle in handles {
            let r = try transact(PTP.Op.getObjectInfo, [handle], allowFailure: true)
            guard r.code == PTP.Response.ok, let info = try? ObjectInfo.parse(handle: handle, payload: r.data) else { return handles }
            formats[handle] = info.format
        }
        guard formats.values.allSatisfy({ $0 == Self.associationFormat }) else { return handles }
        var result = handles
        for folder in handles {
            let inside = try transact(PTP.Op.getObjectHandles, [0xFFFF_FFFF, 0, folder], allowFailure: true)
            guard inside.code == PTP.Response.ok else { continue }
            let children = try Self.handleArray(inside.data).filter { !result.contains($0) }
            result += try withFolderContents(children, depth: depth + 1)
        }
        return result
    }

    static let associationFormat: UInt16 = 0x3001

    static func handleArray(_ data: Data) throws -> [UInt32] {
        var reader = DataReader(data)
        let count = Int(try reader.u32())
        guard count <= reader.remaining / 4 else { throw FujiError.protocolError("bad handle list (\(count) entries)") }
        return try (0..<count).map { _ in try reader.u32() }
    }

    // MARK: - Objects

    public func objectInfo(_ handle: UInt32) throws -> ObjectInfo {
        let info = try ObjectInfo.parse(handle: handle, payload: try transact(PTP.Op.getObjectInfo, [handle]).data)
        Trace.shared.stage(.listed)
        return info
    }

    public func thumbnail(_ handle: UInt32) throws -> Data? {
        let r = try transact(PTP.Op.getThumb, [handle], allowFailure: true)
        guard r.code == PTP.Response.ok, r.data.count >= 100 else { return nil }
        Trace.shared.stage(.thumbnail)
        return r.data
    }

    @discardableResult
    public func download(_ handle: UInt32, to destination: URL, progress: (Int64, Int64) -> Void = { _, _ in }) throws -> ObjectInfo {
        do {
            let info = try downloadSteps(handle, to: destination, progress: progress)
            Trace.shared.stage(.downloaded, info.filename)
            return info
        } catch {
            Trace.shared.failed(error, during: "download")
            throw error
        }
    }

    private func downloadSteps(_ handle: UInt32, to destination: URL, progress: (Int64, Int64) -> Void) throws -> ObjectInfo {
        let info = try objectInfo(handle)
        log("Downloading \(info.filename) (\(info.compressedSize) bytes)")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }

        // 0xFFFFFFFF: larger than 4 GB, too big for GetPartialObject's 32-bit offsets.
        let total = info.compressedSize
        let sizeKnown = total != UInt32.max
        var offset: UInt32 = 0
        if supportsPartialObject && sizeKnown {
            while offset < total {
                let chunk = min(total - offset, PTP.maxPartialObject)
                let r = try transact(PTP.Op.getPartialObject, [handle, offset, chunk], timeout: 30, allowFailure: true)
                if r.code == PTP.Response.operationNotSupported && offset == 0 {
                    supportsPartialObject = false
                    break
                }
                guard r.code == PTP.Response.ok else { throw FujiError.response(op: PTP.Op.getPartialObject, code: r.code) }
                guard !r.data.isEmpty else { throw FujiError.protocolError("empty chunk at offset \(offset)") }
                try file.write(contentsOf: r.data)
                offset += UInt32(r.data.count)
                progress(Int64(offset), Int64(total))
                // A long download mustn't leave the camera's "are you there?" probes unanswered.
                serviceEvents()
            }
        }
        if !supportsPartialObject || !sizeKnown {
            let r = try transact(PTP.Op.getObject, [handle], timeout: 120)
            try file.write(contentsOf: r.data)
            progress(Int64(r.data.count), Int64(sizeKnown ? total : UInt32(clamping: r.data.count)))
        }
        try file.synchronize()
        if sizeKnown { try verifySize(destination, expected: total) }
        return info
    }

    // MARK: - Transport

    struct Reply {
        var code: UInt16
        var data: Data
    }

    /// One transaction, recorded in the diagnostics trace.
    @discardableResult
    func transact(_ op: UInt16, _ params: [UInt32], timeout: TimeInterval = 10, allowFailure: Bool = false) throws -> Reply {
        let started = Date()
        let reply: Reply
        do {
            reply = try exchange(op, params, timeout: timeout)
        } catch {
            Trace.shared.ptp("ptpip", op: op, params: params, code: nil, dataIn: nil,
                             ms: Int(Date().timeIntervalSince(started) * 1000), error: error)
            throw error
        }
        Trace.shared.ptp("ptpip", op: op, params: params, code: reply.code, dataIn: reply.data,
                         ms: Int(Date().timeIntervalSince(started) * 1000))
        if reply.code != PTP.Response.ok && !allowFailure { throw FujiError.response(op: op, code: reply.code) }
        return reply
    }

    private func exchange(_ op: UInt16, _ params: [UInt32], timeout: TimeInterval) throws -> Reply {
        guard let cmd else { throw FujiError.disconnected }
        cmd.readTimeout = timeout
        let tid = transaction
        transaction += 1
        do {
            var w = DataWriter()
            w.u32(1) // data phase: none or camera-to-host
            w.u16(op)
            w.u32(tid)
            params.forEach { w.u32($0) }
            try writePacket(.operationRequest, w.data, to: cmd)

            var data = Data()
            while true {
                let (type, payload) = try readPacket(from: cmd)
                var r = DataReader(payload)
                switch type {
                case .startData:
                    // Transaction ID, then the total length as a 64-bit value (all ones when unknown).
                    _ = try r.u32()
                    let low = UInt64(try r.u32()), high = UInt64(try r.u32())
                    let length = high << 32 | low
                    if length < 256 << 20 { data.reserveCapacity(Int(length)) }
                case .data, .endData:
                    _ = try r.u32() // transaction id
                    data.append(payload.dropFirst(4))
                case .operationResponse:
                    let code = try r.u16()
                    if let answered = try? r.u32(), answered != tid { log("Response for transaction \(answered), expected \(tid)") }
                    return Reply(code: code, data: data)
                case .probeRequest:
                    try writePacket(.probeResponse, Data(), to: cmd)
                case .event, .probeResponse:
                    break // belongs on the event channel; harmless here
                default:
                    throw FujiError.protocolError("unexpected PTP/IP packet \(type)")
                }
            }
        } catch let error as FujiError {
            if error.isConnectionLoss { isConnected = false }
            throw error
        }
    }

    /// Answers probes and reads events waiting on the event channel, without blocking. True when the camera
    /// announced a new object. A broken event channel is logged and dropped: the command channel is what counts.
    @discardableResult
    func serviceEvents() -> Bool {
        guard let events else { return false }
        var objectAdded = false
        while events.waitReadable(timeout: 0) {
            let packet: (PacketType, Data)
            do {
                packet = try readPacket(from: events)
                if packet.0 == .probeRequest { try writePacket(.probeResponse, Data(), to: events) }
            } catch {
                log("Event channel closed: \(error.localizedDescription)")
                events.close()
                self.events = nil
                break
            }
            let (type, payload) = packet
            switch type {
            case .event:
                var r = DataReader(payload)
                if let code = try? r.u16() {
                    Trace.shared.raw("ptpip", channel: "event", received: payload)
                    if code == Self.objectAddedEvent { objectAdded = true }
                }
            default:
                break
            }
        }
        return objectAdded
    }

    private func writePacket(_ type: PacketType, _ payload: Data, to socket: TCPSocket) throws {
        var w = DataWriter()
        w.u32(UInt32(8 + payload.count))
        w.u32(type.rawValue)
        w.data.append(payload)
        try socket.write(w.data)
    }

    private func readPacket(from socket: TCPSocket) throws -> (PacketType, Data) {
        var h = DataReader(try socket.read(exactly: 8))
        let length = Int(try h.u32())
        let rawType = try h.u32()
        guard length >= 8, length < 64 << 20, let type = PacketType(rawValue: rawType) else {
            throw FujiError.protocolError("bad PTP/IP packet (length \(length), type \(rawType))")
        }
        return (type, length > 8 ? try socket.read(exactly: length - 8) : Data())
    }
}

extension PTPIPCamera: WirelessCamera {
    public func refreshObjectCount() throws -> Int {
        serviceEvents()
        try pollCanonEvents()
        try loadHandles()
        return objectHandles.count
    }
}
