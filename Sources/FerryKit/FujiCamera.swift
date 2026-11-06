import Foundation

/// A Wi-Fi session with a Fujifilm X camera in "Wireless Communication" mode (the mode used by
/// Fujifilm Camera Remote). The connection sequence follows libfuji's `fuji_setup()`
/// (MIT, github.com/petabyt/libfuji), which was derived from packet captures of Fuji's apps.
///
/// All calls are blocking and serialized; use `run(_:)` from async code.
public final class FujiCamera: @unchecked Sendable {
    public let host: String
    /// Network interface to connect through (e.g. "en0"); nil lets the system route.
    public let interface: String?
    public let clientName: String
    /// True when the Wi-Fi network was started over Bluetooth (see `FujiBluetooth`). Newer cameras then expect
    /// the gallery mode of Fujifilm's XApp instead of Camera Remote's.
    public let afterBluetoothHandoff: Bool
    public var log: (String) -> Void

    public private(set) var cameraName: String = ""
    public private(set) var objectCount: Int = 0
    public private(set) var isConnected = false
    /// Known after `connect()`.
    public private(set) var profile = CameraProfile(model: "")

    private var cmd: TCPSocket?
    private var eventSocket: TCPSocket?
    private var videoSocket: TCPSocket?
    private var transaction: UInt32 = 0
    private var cameraState: UInt32?
    /// Set when the camera announces an image in selection mode.
    private var selectionOffered = false
    /// XApp gallery mode: the camera lists its photos by handle (D621) instead of numbering them 1...count.
    public private(set) var usesXAppGallery = false
    private var xappHandles: [UInt32] = []
    private let queue = DispatchQueue(label: "fujikit.camera")

    public init(host: String = "192.168.0.1", interface: String? = nil, clientName: String = "Ferry",
                afterBluetoothHandoff: Bool = false, log: @escaping (String) -> Void = { _ in }) {
        self.host = host
        self.interface = interface
        self.clientName = clientName
        self.afterBluetoothHandoff = afterBluetoothHandoff
        self.log = log
    }

    /// Runs `body` on the camera's serial queue.
    public func run<T: Sendable>(_ body: @escaping @Sendable (FujiCamera) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                cont.resume(with: Result { try body(self) })
            }
        }
    }

    // MARK: - Connection

    /// Connects and configures the camera for browsing and downloading.
    /// `onWaitingForApproval` is called if the user has to press OK on the camera.
    public func connect(onWaitingForApproval: () -> Void = {}) throws {
        log("Connecting to \(host):\(PTP.commandPort)" + (interface.map { " via \($0)" } ?? ""))
        let socket = try TCPSocket(host: host, port: PTP.commandPort, interface: interface, connectTimeout: 5)
        cmd = socket

        do {
            try handshake()
        } catch FujiError.handshakeRejected {
            // libfuji retries once; cameras sometimes reject the first attempt after waking up.
            log("Handshake rejected, retrying")
            Thread.sleep(forTimeInterval: 0.5)
            try handshake()
        }
        log("Connected to \(cameraName)")

        // Fuji cameras need at least 50ms before OpenSession.
        Thread.sleep(forTimeInterval: 0.05)

        // Fuji starts OpenSession with transaction ID 1 rather than 0.
        transaction = 1
        let open = try transact(PTP.Op.openSession, [1], allowFailure: true)
        guard open.code == PTP.Response.ok || open.code == PTP.Response.sessionAlreadyOpen else {
            throw FujiError.response(op: PTP.Op.openSession, code: open.code)
        }
        isConnected = true

        try pollEvents()
        // State events may only be sent on the first connection after the camera's Wi-Fi starts,
        // so read the properties directly when they didn't arrive.
        if cameraState == nil {
            cameraState = try propU32(PTP.FujiProp.cameraState)
        }
        if objectCount == 0, let count = try propU32(PTP.FujiProp.objectCount) {
            objectCount = Int(count)
        }
        if cameraState == nil || cameraState == PTP.CameraState.waitForAccess {
            log("Waiting for the user to press OK on the camera")
            onWaitingForApproval()
            let deadline = Date().addingTimeInterval(120)
            while cameraState == nil || cameraState == PTP.CameraState.waitForAccess {
                guard Date() < deadline else { throw FujiError.timeout }
                if Task.isCancelled { throw FujiError.cancelled }
                Thread.sleep(forTimeInterval: 0.2)
                try pollEvents()
                if cameraState == nil || cameraState == PTP.CameraState.waitForAccess {
                    cameraState = try propU32(PTP.FujiProp.cameraState)
                }
            }
        }

        profile = CameraProfile(model: cameraName,
                                getObjectVersion: try propU32(PTP.FujiProp.getObjectVersion),
                                remoteImageViewVersion: try propU32(PTP.FujiProp.remoteGetObjectVersion),
                                imageGetVersion: try propU32(PTP.FujiProp.imageGetVersion),
                                remoteVersion: try propU32(PTP.FujiProp.remoteVersion))
        log("Camera profile: \(profile.summary), state \(hex(cameraState))")
        if let battery = try propU32(PTP.FujiProp.batteryLevel) { log("Battery level (raw): \(battery)") }

        // libfuji: after a Bluetooth hand-off, cameras before remote version 0x20007 still speak Camera Remote.
        usesXAppGallery = afterBluetoothHandoff && profile.generation == .remoteNew
        try configureInitialMode()
        if usesXAppGallery {
            log("Configuring the XApp gallery")
            try configureXAppGallery()
            log("Ready: \(objectCount) objects on the card")
            return
        }

        if isSendingSelection {
            // libfuji skips the rest of the setup in this mode.
            log("Ready: the camera is sending images selected on the camera")
            return
        }

        try configureVersion()
        if isAutoSave {
            // libfuji: in PC AutoSave mode the correct file size is enabled once, not per download.
            try setProp(PTP.FujiProp.enableCorrectFileSize, u16: 1, timeout: 30)
        }
        _ = try? prop(PTP.FujiProp.storageID)

        if profile.hasRemoteMode && cameraState == PTP.CameraState.remoteAccess {
            // libfuji: entering and leaving liveview once during setup is needed, otherwise the camera stops responding.
            log("Configuring remote mode")
            let openCaptureTransaction = transaction
            try transact(PTP.Op.initiateOpenCapture, [0, 0])
            try pollEvents()
            Thread.sleep(forTimeInterval: 0.05)
            eventSocket = try TCPSocket(host: host, port: PTP.eventPort, interface: interface, connectTimeout: 5)
            videoSocket = try TCPSocket(host: host, port: PTP.liveviewPort, interface: interface, connectTimeout: 5)
            try pollEvents()
            try transact(PTP.Op.terminateOpenCapture, [openCaptureTransaction])

            log("Configuring image gallery")
            try configureImageGallery()
        }

        log("Ready: \(objectCount) objects on the card")
    }

    public func disconnect() {
        if isConnected, let cmd {
            cmd.readTimeout = 2
            _ = try? transact(PTP.Op.closeSession, [], allowFailure: true)
            // Fuji's goodbye packet
            try? cmd.write(Data([0x08, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]))
        }
        cmd?.close()
        eventSocket?.close()
        videoSocket?.close()
        cmd = nil
        eventSocket = nil
        videoSocket = nil
        isConnected = false
        log("Disconnected")
    }

    // MARK: - Browsing and downloading

    /// True when the camera connected through PC AutoSave (see `AutoSaveListener`).
    public var isAutoSave: Bool { cameraState == PTP.CameraState.pcAutoSave }

    /// True when the user chose images on the camera and started sending them, instead of browsing from the computer.
    /// The camera then offers one image at a time; use `nextSelectedImage(after:)` instead of `objectHandles`.
    public var isSendingSelection: Bool { cameraState == PTP.CameraState.multipleTransfer }

    /// The handle the camera uses for the image it is currently sending in selection mode.
    public static let selectedImageHandle: UInt32 = 1

    /// In selection mode the camera announces each image by re-sending camera state 1, and offers it as handle 1.
    /// Returns the next image's info, or nil once the camera stops offering images or ends the transfer.
    public func nextSelectedImage(timeout: TimeInterval = 15) throws -> ObjectInfo? {
        do {
            let deadline = Date().addingTimeInterval(timeout)
            while !selectionOffered {
                guard Date() < deadline else {
                    log("The camera has no more images to send")
                    return nil
                }
                Thread.sleep(forTimeInterval: 0.2)
                try pollEvents()
            }
            selectionOffered = false
            return try objectInfo(Self.selectedImageHandle)
        } catch FujiError.disconnected {
            log("The camera ended the transfer")
            return nil
        }
    }

    /// Fuji doesn't support GetObjectHandles over Wi-Fi; objects are numbered 1...count.
    public var objectHandles: [UInt32] {
        if usesXAppGallery { return xappHandles }
        return objectCount > 0 ? Array(1...UInt32(objectCount)) : []
    }

    public func objectInfo(_ handle: UInt32) throws -> ObjectInfo {
        let r = try transact(PTP.Op.getObjectInfo, [handle])
        return try ObjectInfo.parse(handle: handle, payload: r.data)
    }

    /// Returns the embedded JPEG thumbnail, or nil if the camera has none for this object.
    public func thumbnail(_ handle: UInt32) throws -> Data? {
        // libfuji: GetThumb blocks forever on newer cameras unless GetObjectInfo is called first.
        if profile.thumbnailNeedsObjectInfo {
            _ = try? objectInfo(handle)
        }
        let r = try transact(PTP.Op.getThumb, [handle], allowFailure: true)
        guard r.code == PTP.Response.ok, r.data.count >= 100 else { return nil }
        return r.data
    }

    /// Downloads an object to `destination`. Returns the object's info.
    @discardableResult
    public func download(_ handle: UInt32, to destination: URL, progress: (Int64, Int64) -> Void = { _, _ in }) throws -> ObjectInfo {
        let perDownloadSetup = !isAutoSave && !usesXAppGallery
        if usesXAppGallery {
            // libfuji: 2 asks for the full-size file (1 would be the smartphone-sized copy).
            try setProp(PTP.FujiProp.compressSmall, u16: 2)
        }
        if perDownloadSetup {
            try pollEvents()
            // Without this the camera reports a fake 100kb size in ObjectInfo.
            try setProp(PTP.FujiProp.enableCorrectFileSize, u16: 1, timeout: 30)
        }

        var result: Result<ObjectInfo, Error>
        do {
            let info = try objectInfo(handle)
            log("Downloading \(info.filename) (\(info.compressedSize) bytes)")
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            let file = try FileHandle(forWritingTo: destination)
            defer { try? file.close() }

            var offset: UInt32 = 0
            let total = info.compressedSize
            while offset < total {
                let chunk = min(total - offset, PTP.maxPartialObject)
                let r = try transact(PTP.Op.getPartialObject, [handle, offset, chunk], timeout: 30)
                guard !r.data.isEmpty else { throw FujiError.protocolError("empty chunk at offset \(offset)") }
                try file.write(contentsOf: r.data)
                offset += UInt32(r.data.count)
                progress(Int64(offset), Int64(total))
            }
            try verifySize(destination, expected: total)
            result = .success(info)
        } catch {
            result = .failure(error)
        }

        do {
            if perDownloadSetup {
                try pollEvents()
                try setProp(PTP.FujiProp.enableCorrectFileSize, u16: 0)
            }
        } catch {
            // The file is complete; in selection mode the camera may hang up right after the last one.
            guard case .success = result else { throw error }
            log("After download: \(error.localizedDescription)")
        }
        return try result.get()
    }

    /// Polls the camera's event list; keeps the connection alive and picks up new photos.
    public func pollEvents() throws {
        guard let data = try prop(PTP.FujiProp.eventsList), data.count >= 2 else { return }
        var r = DataReader(data)
        let count = Int(try r.u16())
        for _ in 0..<count {
            guard r.remaining >= 6 else { break }
            let code = try r.u16()
            let value = try r.u32()
            switch code {
            case PTP.FujiProp.cameraState:
                if cameraState != value { log("Camera state -> \(value)") }
                cameraState = value
                if value == PTP.CameraState.multipleTransfer { selectionOffered = true }
            case PTP.FujiProp.batteryLevel:
                log("Battery level (raw) -> \(value)")
            case PTP.FujiProp.objectCount where !usesXAppGallery:
                if objectCount != Int(value) { log("Object count -> \(value)") }
                objectCount = Int(value)
            default:
                break
            }
        }
    }

    // MARK: - Setup steps

    private func configureInitialMode() throws {
        let mode: UInt16
        if usesXAppGallery {
            mode = PTP.ClientState.remoteImageViewXApp
        } else if cameraState == PTP.CameraState.multipleTransfer {
            mode = PTP.ClientState.viewMultiple
        } else if profile.hasRemoteMode || cameraState == PTP.CameraState.remoteAccess {
            mode = PTP.ClientState.remoteMode
        } else if cameraState == PTP.CameraState.pcAutoSave {
            mode = PTP.ClientState.oldRemote
        } else {
            mode = PTP.ClientState.viewAllImages
        }
        log("Setting client mode \(mode)")
        // Newer cameras show an accept dialog here, so allow a long wait.
        try setProp(PTP.FujiProp.clientState, u16: mode, timeout: 120)
        try pollEvents()
    }

    private func configureVersion() throws {
        if cameraState == PTP.CameraState.pcAutoSave {
            if let v = try propU32(PTP.FujiProp.autoSaveVersion) {
                try setProp(PTP.FujiProp.autoSaveVersion, u32: v)
            }
        } else if !profile.hasRemoteMode {
            if let v = try propU32(PTP.FujiProp.getObjectVersion) {
                try setProp(PTP.FujiProp.getObjectVersion, u32: v)
            }
        } else {
            // Fuji's own app sets the highest remote version it supports (X-T20 reports 0x20004).
            try setProp(PTP.FujiProp.remoteVersion, u32: PTP.camConnectRemoteVersion)
        }
    }

    private func configureImageGallery() throws {
        guard profile.remoteImageViewVersion != nil else { return }
        try pollEvents()
        try setProp(PTP.FujiProp.cameraState, u16: UInt16(PTP.CameraState.remoteAccess))
        try pollEvents()
        try pollEvents()
        try setProp(PTP.FujiProp.clientState, u16: PTP.ClientState.remoteImageView)
        try pollEvents()
        profile.remoteImageViewVersion = try propU32(PTP.FujiProp.remoteGetObjectVersion)
        // libfuji sets this to 5 for all cameras (X-S10 and X-H1 want at least 4).
        try setProp(PTP.FujiProp.remoteGetObjectVersion, u32: 5)
        try pollEvents()
    }

    /// The XApp gallery setup, as libfuji's `fuji_xapp_config_gallery` and vcam's GFX100 II regression test do it.
    private func configureXAppGallery() throws {
        if let version = try propU32(PTP.FujiProp.remotePhotoViewExVersion) {
            try setProp(PTP.FujiProp.remotePhotoViewExVersion, u32: version)
        }
        try setProp(PTP.FujiProp.compressSmall, u16: 0)
        try setProp(PTP.FujiProp.enableCorrectFileSize, u16: 0)
        _ = try? prop(PTP.FujiProp.storageID)
        // The app asks for the current object and its thumbnail, then the folders and dates, before the list.
        try transact(PTP.Op.fujiGetExtensionObjectInfo, [PTP.xappCurrentObject], allowFailure: true)
        try transact(PTP.Op.fujiGetExtensionThumb, [PTP.xappCurrentObject], allowFailure: true)
        try transact(PTP.Op.fujiGetImageImportFolders, [], allowFailure: true)
        try transact(PTP.Op.fujiGetImageImportDates, [0, 30000], allowFailure: true)

        guard let data = try prop(PTP.FujiProp.imageImportObjectHandles), data.count >= 4 else {
            throw FujiError.protocolError("the camera sent no image list")
        }
        var r = DataReader(data)
        let count = Int(try r.u32())
        xappHandles = []
        for _ in 0..<count where r.remaining >= 4 {
            xappHandles.append(try r.u32())
        }
        objectCount = xappHandles.count
    }

    private func handshake() throws {
        guard let cmd else { throw FujiError.disconnected }
        var w = DataWriter()
        w.u32(0x52)
        w.u32(1) // init command request
        w.u32(PTP.fujiProtocolVersion)
        // Fixed client GUID, same as libfuji
        w.u32(0x5D48_A5AD)
        w.u32(0x0B7F_B287)
        w.u32(0xD0DE_D5D3)
        w.u32(0)
        var name = Data()
        for unit in clientName.prefix(26).utf16 {
            name.append(UInt8(unit & 0xFF))
            name.append(UInt8(unit >> 8))
        }
        name.append(contentsOf: [UInt8](repeating: 0, count: 54 - name.count))
        w.data.append(name)
        try cmd.write(w.data)

        cmd.readTimeout = 30
        let lengthData = try cmd.read(exactly: 4)
        var lr = DataReader(lengthData)
        let length = Int(try lr.u32())
        guard length >= 8, length < 4096 else { throw FujiError.protocolError("bad init response length \(length)") }
        let rest = try cmd.read(exactly: length - 4)
        var r = DataReader(rest)
        let type = try r.u32()
        if type == 5 { throw FujiError.handshakeRejected }
        guard type == 2 else { throw FujiError.protocolError("unexpected init response type \(type)") }

        // Camera name: UTF-16LE starting at offset 28 of the packet
        var units: [UInt16] = []
        var nr = DataReader(lengthData + rest, offset: 28)
        while nr.remaining >= 2, let u = try? nr.u16(), u != 0 { units.append(u) }
        cameraName = String(decoding: units, as: UTF16.self)
    }

    // MARK: - Properties

    /// Returns the raw property value, or nil if the camera doesn't have it.
    private func prop(_ code: UInt16) throws -> Data? {
        let r = try transact(PTP.Op.getDevicePropValue, [UInt32(code)], allowFailure: true)
        guard r.code == PTP.Response.ok, !r.data.isEmpty else { return nil }
        return r.data
    }

    private func propU32(_ code: UInt16) throws -> UInt32? {
        guard let d = try prop(code) else { return nil }
        var r = DataReader(d)
        switch d.count {
        case 1: return UInt32(try r.u8())
        case 2, 3: return UInt32(try r.u16())
        default: return try r.u32()
        }
    }

    private func setProp(_ code: UInt16, u16 value: UInt16, timeout: TimeInterval = 10) throws {
        var w = DataWriter()
        w.u16(value)
        try transact(PTP.Op.setDevicePropValue, [UInt32(code)], dataOut: w.data, timeout: timeout)
    }

    private func setProp(_ code: UInt16, u32 value: UInt32, timeout: TimeInterval = 10) throws {
        var w = DataWriter()
        w.u32(value)
        try transact(PTP.Op.setDevicePropValue, [UInt32(code)], dataOut: w.data, timeout: timeout)
    }

    // MARK: - Transport

    struct Reply {
        var code: UInt16
        var data: Data
    }

    @discardableResult
    func transact(_ op: UInt16, _ params: [UInt32], dataOut: Data? = nil, timeout: TimeInterval = 10, allowFailure: Bool = false) throws -> Reply {
        guard let cmd else { throw FujiError.disconnected }
        cmd.readTimeout = timeout
        let tid = transaction
        do {
            try cmd.write(Container.command(op, transaction: tid, params: params).encoded())
            if let dataOut {
                try cmd.write(Container(type: .data, code: op, transaction: tid, payload: dataOut).encoded())
            }

            var data = Data()
            var container = try readContainer()
            if container.type == .data {
                data = container.payload
                container = try readContainer()
            }
            guard container.type == .response else {
                throw FujiError.protocolError("expected response, got container type \(container.type)")
            }
            transaction += 1
            videoSocket?.drain()
            eventSocket?.drain()

            if container.code == 0xFFFF {
                // Fuji's nonstandard 'goodbye' response
                throw FujiError.disconnected
            }
            if container.code != PTP.Response.ok && !allowFailure {
                throw FujiError.response(op: op, code: container.code)
            }
            return Reply(code: container.code, data: data)
        } catch let error as FujiError {
            switch error {
            case .disconnected, .timeout, .io:
                isConnected = false
            default:
                break
            }
            throw error
        }
    }

    private func readContainer() throws -> Container {
        guard let cmd else { throw FujiError.disconnected }
        var h = DataReader(try cmd.read(exactly: 12))
        let length = try h.u32()
        let rawType = try h.u16()
        let code = try h.u16()
        let tid = try h.u32()
        guard length >= 12, let type = PTP.ContainerType(rawValue: rawType) else {
            throw FujiError.protocolError("bad container header (length \(length), type \(rawType))")
        }
        let payload = length > 12 ? try cmd.read(exactly: Int(length) - 12) : Data()
        return Container(type: type, code: code, transaction: tid, payload: payload)
    }

    private func hex(_ v: UInt32?) -> String {
        v.map { String(format: "0x%X", $0) } ?? "none"
    }
}
