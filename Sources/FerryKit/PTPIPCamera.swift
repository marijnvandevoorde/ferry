import Foundation

/// A camera speaking standard PTP/IP (ISO 15740 over TCP port 15740), as Canon, Nikon, Sony and others do
/// when connected to a computer or phone app over Wi-Fi.
///
/// Only the standard operations needed for importing are used: OpenSession, GetObjectHandles, GetObjectInfo,
/// GetThumb and GetPartialObject (or GetObject when partial transfers aren't supported).
/// Brand-specific pairing (Canon's "connect to smartphone" approval, Nikon SnapBridge, Sony's authentication)
/// is not handled yet; this works with cameras that accept a plain PTP/IP session.
public final class PTPIPCamera: @unchecked Sendable {
    public static let port: UInt16 = 15740

    public let host: String
    public let interface: String?
    public let clientName: String
    public var log: (String) -> Void

    public private(set) var cameraName = ""
    public private(set) var isConnected = false
    public private(set) var objectHandles: [UInt32] = []

    private var cmd: TCPSocket?
    private var events: TCPSocket?
    private var transaction: UInt32 = 0
    private var supportsPartialObject = true

    /// Fixed client GUID, so cameras that remember paired clients recognize us next time.
    static let guid: [UInt8] = [0x46, 0x75, 0x6A, 0x69, 0x49, 0x6D, 0x70, 0x6F, 0x72, 0x74, 0x00, 0x01, 0x8A, 0x3C, 0x5E, 0x21]

    enum PacketType: UInt32 {
        case initCommandRequest = 1, initCommandAck, initEventRequest, initEventAck, initFail
        case operationRequest, operationResponse, event, startData, data, cancel, endData
    }

    public init(host: String, interface: String? = nil, clientName: String = "Ferry",
                log: @escaping (String) -> Void = { _ in }) {
        self.host = host
        self.interface = interface
        self.clientName = clientName
        self.log = log
    }

    // MARK: - Connection

    /// How long to wait for the camera to answer the init request; cameras that ask the user to accept a new
    /// device answer only after that.
    static let approvalTimeout: TimeInterval = 120

    /// `onWaitingForApproval` is called when the camera doesn't answer the init request right away: it may be
    /// asking the user whether to allow this computer. Throws `FujiError.cancelled` when the calling task is
    /// cancelled while waiting, and `FujiError.initRejected` when the camera refuses the connection.
    public func connect(onWaitingForApproval: () -> Void = {}) throws {
        log("Connecting to \(host):\(Self.port) (PTP/IP)" + (interface.map { " via \($0)" } ?? ""))
        let cmd = try TCPSocket(host: host, port: Self.port, interface: interface, connectTimeout: 5)
        self.cmd = cmd

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
        if type == .initFail {
            var r = DataReader(ack)
            let reason = (try? r.u32()).map { String(format: "0x%08X", $0) } ?? "none"
            log("The camera refused the connection (PTP/IP InitFail, reason \(reason))")
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

        // The event channel: a second connection announcing the same connection number.
        let events = try TCPSocket(host: host, port: Self.port, interface: interface, connectTimeout: 5)
        self.events = events
        var e = DataWriter()
        e.u32(connectionNumber)
        try writePacket(.initEventRequest, e.data, to: events)
        events.readTimeout = 10
        let (eventAck, _) = try readPacket(from: events)
        guard eventAck == .initEventAck else { throw FujiError.protocolError("expected event ack, got \(eventAck)") }

        transaction = 0
        let open = try transact(PTP.Op.openSession, [1], allowFailure: true)
        guard open.code == PTP.Response.ok || open.code == PTP.Response.sessionAlreadyOpen else {
            throw FujiError.response(op: PTP.Op.openSession, code: open.code)
        }
        isConnected = true
        try loadHandles()
        log("Ready: \(objectHandles.count) objects")
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

    /// Reloads the object list (all storages, all formats).
    public func loadHandles() throws {
        let r = try transact(PTP.Op.getObjectHandles, [0xFFFF_FFFF, 0, 0])
        var reader = DataReader(r.data)
        let count = Int(try reader.u32())
        objectHandles = try (0..<count).map { _ in try reader.u32() }
    }

    // MARK: - Objects

    public func objectInfo(_ handle: UInt32) throws -> ObjectInfo {
        try ObjectInfo.parse(handle: handle, payload: try transact(PTP.Op.getObjectInfo, [handle]).data)
    }

    public func thumbnail(_ handle: UInt32) throws -> Data? {
        let r = try transact(PTP.Op.getThumb, [handle], allowFailure: true)
        guard r.code == PTP.Response.ok, r.data.count >= 100 else { return nil }
        return r.data
    }

    @discardableResult
    public func download(_ handle: UInt32, to destination: URL, progress: (Int64, Int64) -> Void = { _, _ in }) throws -> ObjectInfo {
        let info = try objectInfo(handle)
        log("Downloading \(info.filename) (\(info.compressedSize) bytes)")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let file = try FileHandle(forWritingTo: destination)
        defer { try? file.close() }

        let total = info.compressedSize
        var offset: UInt32 = 0
        if supportsPartialObject {
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
            }
        }
        if !supportsPartialObject {
            let r = try transact(PTP.Op.getObject, [handle], timeout: 120)
            try file.write(contentsOf: r.data)
            progress(Int64(r.data.count), Int64(total))
        }
        try file.synchronize()
        try verifySize(destination, expected: total)
        return info
    }

    // MARK: - Transport

    struct Reply {
        var code: UInt16
        var data: Data
    }

    @discardableResult
    func transact(_ op: UInt16, _ params: [UInt32], timeout: TimeInterval = 10, allowFailure: Bool = false) throws -> Reply {
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
                    break
                case .data, .endData:
                    _ = try r.u32() // transaction id
                    data.append(payload.dropFirst(4))
                case .operationResponse:
                    let code = try r.u16()
                    if code != PTP.Response.ok && !allowFailure { throw FujiError.response(op: op, code: code) }
                    return Reply(code: code, data: data)
                default:
                    throw FujiError.protocolError("unexpected PTP/IP packet \(type)")
                }
            }
        } catch let error as FujiError {
            if error.isConnectionLoss { isConnected = false }
            throw error
        }
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
        try loadHandles()
        return objectHandles.count
    }
}
