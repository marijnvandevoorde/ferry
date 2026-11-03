import Foundation

public enum FujiError: Error, LocalizedError, Equatable {
    case connectionFailed(String)
    case handshakeRejected
    case disconnected
    case timeout
    case io(String)
    case protocolError(String)
    case response(op: UInt16, code: UInt16)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let m): return localized("Could not connect: %@", m)
        case .handshakeRejected: return localized("The camera rejected the connection. Restart Wi-Fi on the camera and try again.")
        case .disconnected: return localized("The camera closed the connection.")
        case .timeout: return localized("The camera stopped responding.")
        case .io(let m): return localized("Network error: %@", m)
        case .protocolError(let m): return localized("Protocol error: %@", m)
        case .response(let op, let code):
            return localized("Camera returned %@ for operation %@", String(format: "0x%04X", code), String(format: "0x%04X", op))
        case .cancelled: return localized("Cancelled")
        }
    }

    /// The connection to the camera is gone; reconnecting may help.
    public var isConnectionLoss: Bool {
        // Written with `if case`: the Swift 6.0 compiler for Windows crashes on the equivalent switch.
        if case .disconnected = self { return true }
        if case .timeout = self { return true }
        if case .io = self { return true }
        return false
    }
}

/// Looks up `key` in FujiKit's translations and fills in `%@` arguments; English when they aren't shipped.
func localized(_ key: String, _ args: String...) -> String {
    let format = translations.map { NSLocalizedString(key, bundle: $0, comment: "") } ?? key
    return String(format: format, arguments: args)
}

/// FujiKit's resource bundle. Not `Bundle.module`: that crashes when the bundle wasn't shipped next to the binary,
/// as with the desktop app's single-file ferryctl sidecar.
private let translations: Bundle? = {
    let names = ["FujiKit_FujiKit.bundle", "FujiKit_FujiKit.resources"]
    let places = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
    for place in places.compactMap({ $0 }) {
        for name in names {
            if let bundle = Bundle(url: place.appendingPathComponent(name)) { return bundle }
        }
    }
    return nil
}()

/// PTP codes used by this client. Fuji-specific values come from libfuji (MIT, github.com/petabyt/libfuji).
enum PTP {
    enum ContainerType: UInt16 {
        case command = 1, data = 2, response = 3, event = 4
    }

    enum Op {
        static let openSession: UInt16 = 0x1002
        static let closeSession: UInt16 = 0x1003
        static let getObjectHandles: UInt16 = 0x1007
        static let getObjectInfo: UInt16 = 0x1008
        static let getObject: UInt16 = 0x1009
        static let getThumb: UInt16 = 0x100A
        static let getDevicePropValue: UInt16 = 0x1015
        static let setDevicePropValue: UInt16 = 0x1016
        static let terminateOpenCapture: UInt16 = 0x1018
        static let getPartialObject: UInt16 = 0x101B
        static let initiateOpenCapture: UInt16 = 0x101C
        // Fujifilm's XApp gallery
        static let fujiGetImageImportFolders: UInt16 = 0x9050
        static let fujiGetImageImportDates: UInt16 = 0x9053
        static let fujiGetExtensionObjectInfo: UInt16 = 0x9054
        static let fujiGetExtensionThumb: UInt16 = 0x9055
    }

    enum Response {
        static let ok: UInt16 = 0x2001
        static let operationNotSupported: UInt16 = 0x2005
        static let sessionAlreadyOpen: UInt16 = 0x201E
    }

    enum FujiProp {
        static let eventsList: UInt16 = 0xD212
        static let objectCount: UInt16 = 0xD222
        static let compressSmall: UInt16 = 0xD226
        static let enableCorrectFileSize: UInt16 = 0xD227
        static let storageID: UInt16 = 0xD244
        static let cameraState: UInt16 = 0xDF00
        static let clientState: UInt16 = 0xDF01
        static let imageGetVersion: UInt16 = 0xDF21
        static let getObjectVersion: UInt16 = 0xDF22
        static let autoSaveVersion: UInt16 = 0xDF23
        static let remoteVersion: UInt16 = 0xDF24
        static let remoteGetObjectVersion: UInt16 = 0xDF25
        static let remotePhotoViewExVersion: UInt16 = 0xDF28
        static let imageImportObjectCount: UInt16 = 0xD620
        static let imageImportObjectHandles: UInt16 = 0xD621
    }

    /// Values of 0xDF00
    enum CameraState {
        static let waitForAccess: UInt32 = 0
        static let multipleTransfer: UInt32 = 1
        static let fullAccess: UInt32 = 2
        static let pcAutoSave: UInt32 = 3
        static let remoteAccess: UInt32 = 6
    }

    /// Values of 0xDF01
    enum ClientState {
        static let viewMultiple: UInt16 = 1
        static let viewAllImages: UInt16 = 2
        static let oldRemote: UInt16 = 3
        static let remoteMode: UInt16 = 5
        static let remoteImageView: UInt16 = 11
        static let remoteImageViewXApp: UInt16 = 20
    }

    static let fujiProtocolVersion: UInt32 = 0x8F53_E4F2
    static let camConnectRemoteVersion: UInt32 = 0x2000C
    /// The XApp gallery's handle for "the photo shown on the camera".
    static let xappCurrentObject: UInt32 = 0x1000_0001
    static let commandPort: UInt16 = 55740
    static let eventPort: UInt16 = 55741
    static let liveviewPort: UInt16 = 55742
    static let maxPartialObject: UInt32 = 0x100000
}

/// A USB-style PTP bulk container. Fuji sends these over TCP instead of standard PTP/IP packets.
struct Container {
    var type: PTP.ContainerType
    var code: UInt16
    var transaction: UInt32
    var payload: Data

    func encoded() -> Data {
        var w = DataWriter()
        w.u32(UInt32(12 + payload.count))
        w.u16(type.rawValue)
        w.u16(code)
        w.u32(transaction)
        w.data.append(payload)
        return w.data
    }

    static func command(_ code: UInt16, transaction: UInt32, params: [UInt32]) -> Container {
        var w = DataWriter()
        params.forEach { w.u32($0) }
        return Container(type: .command, code: code, transaction: transaction, payload: w.data)
    }
}

struct DataWriter {
    var data = Data()
    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
}

struct DataReader {
    let data: Data
    var offset: Int

    init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var remaining: Int { data.count - offset }

    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw FujiError.protocolError("short read") }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw FujiError.protocolError("short read") }
        let s = data.startIndex + offset
        offset += 2
        return UInt16(data[s]) | UInt16(data[s + 1]) << 8
    }

    mutating func u32() throws -> UInt32 {
        guard remaining >= 4 else { throw FujiError.protocolError("short read") }
        let s = data.startIndex + offset
        offset += 4
        return UInt32(data[s]) | UInt32(data[s + 1]) << 8 | UInt32(data[s + 2]) << 16 | UInt32(data[s + 3]) << 24
    }

    /// PTP string: u8 character count (including the terminating NUL), then UTF-16LE.
    mutating func ptpString() throws -> String {
        let count = Int(try u8())
        var units: [UInt16] = []
        for _ in 0..<count { units.append(try u16()) }
        while units.last == 0 { units.removeLast() }
        return String(decoding: units, as: UTF16.self)
    }
}

/// Standard PTP ObjectInfo dataset.
public struct ObjectInfo: Sendable, Hashable {
    public var handle: UInt32
    public var format: UInt16
    public var compressedSize: UInt32
    public var imageWidth: UInt32
    public var imageHeight: UInt32
    public var filename: String
    public var captureDate: String
    /// Protected (locked) on the camera; photographers use this to mark their selects.
    public var isProtected = false

    /// Parsed capture date (PTP format "YYYYMMDDThhmmss[.s]")
    public var date: Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f.date(from: String(captureDate.prefix(15)))
    }

    /// Association (folder) objects. Real cameras don't list these over Wi-Fi, but be safe.
    public var isFolder: Bool { format == 0x3001 }

    public var isVideo: Bool { kind == .video }

    public enum Kind: String, Sendable, CaseIterable {
        case jpeg, raw, heif, video, other
    }

    public var kind: Kind {
        switch (filename as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "raf", "cr2", "cr3", "nef", "nrw", "arw", "orf", "rw2", "dng", "pef": .raw
        case "heif", "heic", "hif": .heif
        case "mov", "mp4", "avi", "mts": .video
        default: .other
        }
    }

    static func parse(handle: UInt32, payload: Data) throws -> ObjectInfo {
        var r = DataReader(payload)
        _ = try r.u32() // storage id
        let format = try r.u16()
        let protection = try r.u16()
        let size = try r.u32()
        _ = try r.u16() // thumb format
        _ = try r.u32() // thumb size
        _ = try r.u32() // thumb w
        _ = try r.u32() // thumb h
        let w = try r.u32()
        let h = try r.u32()
        _ = try r.u32() // bit depth
        _ = try r.u32() // parent
        _ = try r.u16() // association type
        _ = try r.u32() // association desc
        _ = try r.u32() // sequence number
        let filename = try r.ptpString()
        let captured = (try? r.ptpString()) ?? ""
        return ObjectInfo(handle: handle, format: format, compressedSize: size, imageWidth: w, imageHeight: h,
                          filename: filename, captureDate: captured, isProtected: protection != 0)
    }
}
