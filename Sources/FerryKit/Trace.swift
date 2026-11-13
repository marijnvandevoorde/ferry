import Foundation

/// Records what happens between Ferry and a camera, so a failed connection can be explained afterwards and replayed
/// by a mock camera (`scripts/mock-cameras/replay.py`). Always on and kept in memory; `export` writes it as JSON.
///
/// A session starts with each connection attempt and holds every protocol tried, the steps reached, each request and
/// answer, the log lines and the error. Photo contents (downloads, thumbnails) are never kept, only their size.
/// Attempts where no camera answered at all are replaced by the next attempt, so retrying in the background doesn't
/// push out the attempt that went wrong.
public final class Trace: @unchecked Sendable {
    public static let shared = Trace()

    /// The steps of a connection, in order. A session remembers the furthest one reached.
    public enum Stage: Int, Comparable, CaseIterable, Sendable {
        case searching, reached, identified, session, approved, listed, thumbnail, downloaded

        public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

        var name: String { String(describing: self) }

        var label: String {
            switch self {
            case .searching: "Looked for a camera"
            case .reached: "Something answered on a camera port"
            case .identified: "The camera answered and said which model it is"
            case .session: "Opened a session with the camera"
            case .approved: "The camera allowed access"
            case .listed: "Read the list of photos"
            case .thumbnail: "Received a thumbnail"
            case .downloaded: "Downloaded a photo"
            }
        }
    }

    /// Which app records, and its version; shown in the exported file.
    public var app = "ferryctl"
    public var appVersion = ""

    /// Payloads larger than this are cut, so a big listing can't fill memory.
    static let maxPayload = 256 * 1024
    /// Events per session; past this only steps, errors and log lines are kept.
    static let maxEvents = 20_000
    static let maxSessions = 4

    private let lock = NSLock()
    private var sessions: [Session] = []
    private var redactions: [String] = []

    final class Session {
        let started = Date()
        var host: String?
        var interface: String?
        var stage = Stage.searching
        /// Thumbnails, listing and downloads are separate steps, so each is remembered on its own.
        var reachedStages: Set<Stage> = []

        func hasReached(_ stage: Stage) -> Bool {
            stage <= min(self.stage, .approved) || reachedStages.contains(stage)
        }
        var attempts: [[String: Any]] = []
        var events: [[String: Any]] = []
        var camera: String?
        var protocolName: String?
        var details: [String: Any] = [:]
        var error: [String: Any]?
        var truncated = false
        /// A camera connected in this session; the next attempt starts a new one.
        var connected = false
        /// Something answered during the current protocol attempt.
        var attemptAnswered = false

        func elapsed() -> Int { Int(Date().timeIntervalSince(started) * 1000) }
    }

    init() {
        redactions = [NSHomeDirectory()].filter { $0.count > 1 }
    }

    /// Text replaced in the exported file, such as the computer's name (sent to the camera as the client name).
    public func redact(_ text: String) {
        guard text.count >= 3 else { return }
        lock.withLock { if !redactions.contains(text) { redactions.append(text) } }
    }

    /// Starts a new session for a connection attempt at `host`.
    public func begin(host: String?, interface: String? = nil) {
        lock.withLock { startSession(host: host, interface: interface) }
    }

    private func startSession(host: String?, interface: String?) {
        // An attempt where nothing answered says nothing new: let this one take its place.
        if let last = sessions.last, last.stage == .searching { sessions.removeLast() }
        let session = Session()
        session.host = host
        session.interface = interface
        sessions.append(session)
        if sessions.count > Self.maxSessions { sessions.removeFirst(sessions.count - Self.maxSessions) }
    }

    /// The session to record into, starting one when there is none.
    private func current() -> Session {
        if let last = sessions.last { return last }
        startSession(host: nil, interface: nil)
        return sessions[sessions.count - 1]
    }

    // MARK: - Recording

    /// A camera protocol is being tried at `host:port`.
    func attempt(_ protocolName: String, host: String, port: Int?) {
        lock.withLock {
            // A new attempt after a camera was connected is a new session.
            if sessions.last?.connected ?? true { startSession(host: host, interface: nil) }
            let session = current()
            if session.host == nil { session.host = host }
            var attempt: [String: Any] = ["protocol": protocolName, "host": host, "t": session.elapsed()]
            if let port { attempt["port"] = port }
            session.attempts.append(attempt)
            session.protocolName = protocolName
            session.attemptAnswered = false
            append(attempt.merging(["kind": "attempt"]) { a, _ in a }, to: session)
        }
    }

    /// How the attempt with the last protocol ended.
    func attemptEnded(_ result: String, error: Error? = nil) {
        lock.withLock {
            guard let session = sessions.last, !session.attempts.isEmpty else { return }
            session.attempts[session.attempts.count - 1]["result"] = result
            if let error { session.attempts[session.attempts.count - 1]["error"] = Self.describe(error) }
        }
    }

    /// The camera reached `stage`; earlier stages count as reached too.
    func stage(_ stage: Stage, _ detail: String? = nil) {
        lock.withLock {
            let session = current()
            if stage >= .reached { session.attemptAnswered = true }
            if stage >= .approved { session.connected = true }
            // Each step is recorded once, the first time it is reached.
            guard !session.reachedStages.contains(stage) else { return }
            session.reachedStages.insert(stage)
            if stage > session.stage { session.stage = stage }
            var event: [String: Any] = ["kind": "stage", "stage": stage.name]
            if let detail { event["detail"] = detail }
            append(event, to: session, always: true)
        }
    }

    /// The camera's name and protocol once it answered.
    func identified(camera: String, protocolName: String) {
        lock.withLock {
            let session = current()
            session.camera = camera
            session.protocolName = protocolName
        }
        stage(.identified, camera)
    }

    /// A fact about the camera worth showing in the summary, such as its PTP device info or Fuji profile.
    func detail(_ key: String, _ value: Any) {
        lock.withLock { current().details[key] = value }
    }

    /// A log line.
    public func note(_ line: String) {
        lock.withLock { append(["kind": "log", "line": line], to: current(), always: true) }
    }

    /// Something failed `during` a step ("connect", "download", "import"…). The last failure is the session's error.
    public func failed(_ error: Error, during step: String) {
        lock.withLock {
            guard let session = sessions.last else { return }
            let entry: [String: Any] = ["during": step, "message": Self.describe(error), "error": String(describing: error)]
            session.error = entry
            append(entry.merging(["kind": "error"]) { a, _ in a }, to: session, always: true)
        }
    }

    /// One PTP transaction: operation, parameters, data sent and received, and the response code.
    /// `dataIn` is omitted for photo contents; its size is kept.
    func ptp(_ protocolName: String, op: UInt16, params: [UInt32], dataOut: Data? = nil, code: UInt16?, dataIn: Data?,
             ms: Int, error: Error? = nil) {
        var dataIn = dataIn
        lock.withLock {
            let session = current()
            if op == PTP.Op.getDeviceInfo, code == PTP.Response.ok, let data = dataIn, let info = try? DeviceInfo.parse(data) {
                dataIn = DeviceInfo.redactingSerial(data, info)
                session.details["deviceInfo"] = info.json
                session.details["model"] = info.model
                session.details["firmware"] = info.version
            }
            var event: [String: Any] = [
                "kind": "ptp", "protocol": protocolName, "op": Self.hex16(op), "opName": PTPNames.operation(op),
                "params": params.map { Int($0) },
                "ms": ms,
            ]
            if (op == PTP.Op.getDevicePropValue || op == PTP.Op.setDevicePropValue), let p = params.first {
                event["prop"] = PTPNames.property(UInt16(truncatingIfNeeded: p))
            }
            if let dataOut { event["out"] = Self.hex(dataOut) }
            if let code { event["code"] = Self.hex16(code); event["codeName"] = PTPNames.response(code) }
            if let dataIn {
                if PTPNames.carriesPhoto(op) {
                    event["inSize"] = dataIn.count
                    event["inOmitted"] = "photo data"
                } else {
                    event["in"] = Self.hex(dataIn.prefix(Self.maxPayload))
                    if dataIn.count > Self.maxPayload { event["inSize"] = dataIn.count }
                }
            }
            if let error { event["error"] = Self.describe(error) }
            append(event, to: session)
        }
    }

    /// Raw bytes the camera sent outside PTP transactions, such as the answer to the connection request.
    func raw(_ protocolName: String, channel: String, received: Data) {
        lock.withLock {
            append(["kind": "raw", "protocol": protocolName, "channel": channel, "received": Self.hex(received)], to: current())
        }
    }

    /// One HTTP request and its answer. Images and downloads keep only their size.
    func http(method: String, url: URL, requestBody: Data?, status: Int?, contentType: String?, body: Data?,
              omitBody: Bool = false, bytes: Int? = nil, ms: Int, error: Error? = nil) {
        lock.withLock {
            var event: [String: Any] = ["kind": "http", "method": method, "url": url.absoluteString, "ms": ms]
            if let requestBody, !requestBody.isEmpty { event["requestBody"] = String(decoding: requestBody.prefix(Self.maxPayload), as: UTF8.self) }
            if let status { event["status"] = status }
            if let contentType { event["contentType"] = contentType }
            if let body {
                let isImage = contentType?.lowercased().hasPrefix("image/") == true || body.starts(with: [0xFF, 0xD8])
                if omitBody || isImage {
                    event["bodySize"] = body.count
                    event["bodyOmitted"] = "photo data"
                } else if let text = String(data: body.prefix(Self.maxPayload), encoding: .utf8) {
                    event["body"] = text
                    if body.count > Self.maxPayload { event["bodySize"] = body.count }
                } else {
                    event["bodyBase64"] = body.prefix(Self.maxPayload).base64EncodedString()
                }
            } else if let bytes {
                event["bodySize"] = bytes
                event["bodyOmitted"] = "photo data"
            }
            if let error { event["error"] = Self.describe(error) }
            append(event, to: current())
        }
    }

    private func append(_ event: [String: Any], to session: Session, always: Bool = false) {
        if session.events.count >= Self.maxEvents && !always {
            session.truncated = true
            return
        }
        var event = event
        event["t"] = session.elapsed()
        session.events.append(event)
    }

    // MARK: - Export

    /// Forgets everything recorded so far.
    public func reset() {
        lock.withLock { sessions = [] }
    }

    /// The human-readable summary of the most telling session: how far it got and what went wrong.
    public func summary() -> String {
        lock.withLock { summaryText(for: mainSession()) }
    }

    /// The whole recording as JSON: a summary first, then each session with its events.
    public func export() -> Data {
        let text: String = lock.withLock {
            let main = mainSession()
            var root: [String: Any] = [
                "format": "ferry-diagnostics",
                "formatVersion": 1,
                "ferry": appVersion,
                "app": app,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "platform": Self.platform,
                "created": ISO8601DateFormatter().string(from: Date()),
                "privacy": "No photos or thumbnails: only file names, sizes and dates. The computer's name and home folder are replaced.",
                "summary": summaryText(for: main).components(separatedBy: "\n"),
            ]
            root["sessions"] = sessions.map(sessionJSON)
            if let main, let index = sessions.firstIndex(where: { $0 === main }) { root["mainSession"] = index }
            guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
                return "{}"
            }
            return String(decoding: data, as: UTF8.self)
        }
        var redacted = text
        for secret in lock.withLock({ redactions }) {
            redacted = redacted.replacingOccurrences(of: secret, with: secret == NSHomeDirectory() ? "~" : "<computer>")
        }
        return Data(redacted.utf8)
    }

    /// Writes `export()` to `url`.
    public func export(to url: URL) throws {
        try export().write(to: url, options: .atomic)
    }

    /// A file name like "ferry-diagnostics-2026-11-13-1042.json".
    public static func suggestedFileName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "ferry-diagnostics-\(f.string(from: date)).json"
    }

    /// The last session that got furthest: the latest one with a camera beats a later attempt where nothing answered.
    private func mainSession() -> Session? {
        let best = sessions.map(\.stage).max() ?? .searching
        return sessions.last { $0.stage == best } ?? sessions.last
    }

    private func sessionJSON(_ s: Session) -> [String: Any] {
        var json: [String: Any] = [
            "started": ISO8601DateFormatter().string(from: s.started),
            "reached": s.stage.name,
            "attempts": s.attempts,
            "events": s.events,
        ]
        if let host = s.host { json["host"] = host }
        if let interface = s.interface { json["interface"] = interface }
        if let camera = s.camera { json["camera"] = camera }
        if let p = s.protocolName { json["protocol"] = p }
        if !s.details.isEmpty { json["camera details"] = s.details }
        if let error = s.error { json["error"] = error }
        if s.truncated { json["truncated"] = true }
        return json
    }

    private func summaryText(for session: Session?) -> String {
        var lines = ["Ferry \(appVersion) (\(app)) on \(Self.platform) \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        guard let s = session else {
            lines.append("Ferry hasn't tried to connect to a camera yet.")
            return lines.joined(separator: "\n")
        }
        let camera = s.camera.map { "\($0), protocol \(s.protocolName ?? "?")" } ?? "none identified"
        lines.append("Camera: \(camera)" + (s.host.map { ", at \($0)" } ?? ""))
        if let model = s.details["model"] as? String, let firmware = s.details["firmware"] as? String {
            lines.append("Model \(model), firmware \(firmware)")
        }
        if let profile = s.details["profile"] as? String { lines.append("Profile: \(profile)") }
        lines.append("")
        lines.append("How far it got:")
        for stage in Stage.allCases where stage != .searching {
            lines.append("  \(s.hasReached(stage) ? "[x]" : "[ ]") \(stage.label)")
        }
        lines.append("")
        if let error = s.error {
            lines.append("What went wrong (during \(error["during"] as? String ?? "?")): \(error["message"] as? String ?? "")")
            if let hint = hint(for: s) { lines.append(hint) }
        } else if s.stage >= .listed {
            lines.append("No errors.")
        } else if s.stage == .searching {
            lines.append("What went wrong: no camera answered.")
            if let hint = hint(for: s) { lines.append(hint) }
        } else {
            lines.append("No error was recorded; the attempt stopped after the last step above.")
        }
        if !s.attempts.isEmpty {
            lines.append("")
            lines.append("Protocols tried:")
            for a in s.attempts {
                let port = (a["port"] as? Int).map { ":\($0)" } ?? ""
                lines.append("  \(a["protocol"] as? String ?? "?") at \(a["host"] as? String ?? "?")\(port): \(a["result"] as? String ?? "no result")"
                             + ((a["error"] as? String).map { " (\($0))" } ?? ""))
            }
        }
        if let last = s.events.last(where: { $0["kind"] as? String == "ptp" || $0["kind"] as? String == "http" }) {
            lines.append("")
            lines.append("Last exchange: " + Self.describeEvent(last))
        }
        return lines.joined(separator: "\n")
    }

    private func hint(for s: Session) -> String? {
        if s.stage == .searching {
            return "Is this computer on the camera's own Wi-Fi network? On the camera, start its \"connect to computer\" or "
                + "\"connect to smartphone\" function first. If the camera is on and joined, it may use a protocol Ferry "
                + "doesn't know yet."
        }
        guard let error = s.error?["error"] as? String else { return nil }
        if error.contains("initRejected") {
            return "The camera refused Ferry's PTP/IP connection: it probably wants to be paired first (Canon's "
                + "\"connect to smartphone\" pairing, Nikon SnapBridge). Ferry can't pair with this camera yet."
        }
        if error.contains("handshakeRejected") { return "Restart Wi-Fi on the camera and try again." }
        let exchanges = s.events.filter { ["ptp", "http"].contains($0["kind"] as? String ?? "") }
        if let failing = exchanges.last(where: { ($0["code"] as? String).map { $0 != "0x2001" } == true || $0["error"] != nil }) {
            if let code = failing["code"] as? String, let codeHint = PTPNames.hint(code) {
                return "The camera answered \(failing["opName"] as? String ?? "?") with \(failing["codeName"] as? String ?? code): \(codeHint)"
            }
            if let message = failing["error"] as? String {
                return "It happened at: \(Self.describeEvent(failing)) (\(message))"
            }
        }
        if error.contains("timeout") { return "The camera stopped answering. It may have gone to sleep or left the Wi-Fi network." }
        if error.contains("disconnected") { return "The camera hung up. It may have been switched off or its Wi-Fi turned off." }
        return nil
    }

    static func describeEvent(_ e: [String: Any]) -> String {
        if e["kind"] as? String == "http" {
            return "\(e["method"] as? String ?? "") \(e["url"] as? String ?? "") → \((e["status"] as? Int).map(String.init) ?? "no answer")"
        }
        var text = "\(e["opName"] as? String ?? "?") (\(e["op"] as? String ?? ""))"
        if let prop = e["prop"] as? String { text += " \(prop)" }
        if let params = e["params"] as? [Int], !params.isEmpty, e["prop"] == nil {
            text += " [" + params.map { String(format: "0x%X", $0) }.joined(separator: ", ") + "]"
        }
        return text + " → " + (e["codeName"] as? String ?? "no answer")
    }

    // MARK: - Helpers

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func hex16(_ v: UInt16) -> String { String(format: "0x%04X", v) }

    static var platform: String {
        #if os(macOS)
        "macOS"
        #elseif os(Windows)
        "Windows"
        #elseif os(Linux)
        "Linux"
        #else
        "unknown"
        #endif
    }
}

extension Trace {
    /// Runs one camera's connect, recording the attempt and how it ended.
    func connecting(_ protocolName: String, host: String, port: Int?, _ body: () throws -> Void) throws {
        attempt(protocolName, host: host, port: port)
        do {
            try body()
            attemptEnded("connected")
        } catch {
            var nothing = false
            if case FujiError.connectionFailed = error { nothing = !lock.withLock { sessions.last?.attemptAnswered ?? false } }
            attemptEnded(nothing ? "not found" : "failed", error: error)
            if !nothing { failed(error, during: "connect") }
            throw error
        }
    }
}

/// Names and hints for PTP codes, for the diagnostics summary.
enum PTPNames {
    static let operations: [UInt16: String] = [
        0x1001: "GetDeviceInfo", 0x1002: "OpenSession", 0x1003: "CloseSession", 0x1004: "GetStorageIDs",
        0x1005: "GetStorageInfo", 0x1006: "GetNumObjects", 0x1007: "GetObjectHandles", 0x1008: "GetObjectInfo",
        0x1009: "GetObject", 0x100A: "GetThumb", 0x1014: "GetDevicePropDesc", 0x1015: "GetDevicePropValue",
        0x1016: "SetDevicePropValue", 0x1018: "TerminateOpenCapture", 0x101B: "GetPartialObject",
        0x101C: "InitiateOpenCapture", 0x9050: "Fuji GetImageImportFolders", 0x9053: "Fuji GetImageImportDates",
        0x9054: "Fuji GetExtensionObjectInfo", 0x9055: "Fuji GetExtensionThumb",
    ]

    static let responses: [UInt16: String] = [
        0x2001: "OK", 0x2002: "GeneralError", 0x2003: "SessionNotOpen", 0x2004: "InvalidTransactionID",
        0x2005: "OperationNotSupported", 0x2006: "ParameterNotSupported", 0x2007: "IncompleteTransfer",
        0x2008: "InvalidStorageID", 0x2009: "InvalidObjectHandle", 0x200A: "DevicePropNotSupported",
        0x200B: "InvalidObjectFormatCode", 0x200F: "AccessDenied", 0x2013: "StoreNotAvailable",
        0x2019: "DeviceBusy", 0x201D: "InvalidParameter", 0x201E: "SessionAlreadyOpen", 0x201F: "TransactionCancelled",
        0xFFFF: "Fuji goodbye",
    ]

    static let properties: [UInt16: String] = [
        0x5001: "BatteryLevel", 0xD212: "Fuji EventsList", 0xD222: "Fuji ObjectCount", 0xD226: "Fuji CompressSmall",
        0xD227: "Fuji EnableCorrectFileSize", 0xD242: "Fuji BatteryLevel", 0xD244: "Fuji StorageID",
        0xD36A: "Fuji BatteryInfo1", 0xD36B: "Fuji BatteryInfo2", 0xDF00: "Fuji CameraState",
        0xDF01: "Fuji ClientState", 0xDF21: "Fuji ImageGetVersion", 0xDF22: "Fuji GetObjectVersion",
        0xDF23: "Fuji AutoSaveVersion", 0xDF24: "Fuji RemoteVersion", 0xDF25: "Fuji RemoteGetObjectVersion",
        0xDF28: "Fuji RemotePhotoViewExVersion", 0xD620: "Fuji ImageImportObjectCount",
        0xD621: "Fuji ImageImportObjectHandles",
    ]

    static func operation(_ op: UInt16) -> String { operations[op] ?? String(format: "0x%04X", op) }
    static func response(_ code: UInt16) -> String { responses[code] ?? String(format: "0x%04X", code) }
    static func property(_ code: UInt16) -> String { properties[code] ?? String(format: "0x%04X", code) }

    /// Operations whose data is a photo or thumbnail, which diagnostics never keep.
    static func carriesPhoto(_ op: UInt16) -> Bool {
        [0x1009, 0x100A, 0x101B, 0x9055].contains(op)
    }

    static func hint(_ code: String) -> String? {
        switch code {
        case "0x2005": "the camera doesn't support this operation in this mode."
        case "0x2019": "the camera is busy; it may need to be in playback or shooting mode, or be waiting for a button press."
        case "0x2003": "the camera closed the session."
        case "0x2009": "the camera says this photo doesn't exist; the card may have changed."
        case "0x200F": "the camera refused access; it may want to be paired or approved on its screen."
        case "0x2013": "the camera can't read its card. Is a card inserted?"
        case "0x200A": "the camera doesn't have this setting in this mode."
        case "0x2002": "the camera reported a general error."
        default: nil
        }
    }
}

/// The standard PTP DeviceInfo dataset: who made the camera and what it can do.
struct DeviceInfo {
    var standardVersion: UInt16
    var vendorExtensionID: UInt32
    var vendorExtension: String
    var operations: [UInt16]
    var events: [UInt16]
    var properties: [UInt16]
    var captureFormats: [UInt16]
    var imageFormats: [UInt16]
    var manufacturer: String
    var model: String
    var version: String
    /// Where the serial number's characters start in the payload and how many there are, to blank them.
    var serialRange: Range<Int>?

    static func parse(_ data: Data) throws -> DeviceInfo {
        var r = DataReader(data)
        let standard = try r.u16()
        let vendorID = try r.u32()
        _ = try r.u16() // vendor extension version
        let vendor = try r.ptpString()
        _ = try r.u16() // functional mode
        func array() throws -> [UInt16] {
            let n = Int(try r.u32())
            guard n < 10_000 else { throw FujiError.protocolError("bad array length") }
            return try (0..<n).map { _ in try r.u16() }
        }
        let ops = try array(), events = try array(), props = try array(), capture = try array(), image = try array()
        let manufacturer = try r.ptpString()
        let model = try r.ptpString()
        let version = try r.ptpString()
        let serialStart = r.offset
        var serialRange: Range<Int>?
        if r.remaining >= 1 {
            let count = Int(try r.u8())
            if r.remaining >= count * 2 { serialRange = (serialStart + 1)..<(serialStart + 1 + count * 2) }
        }
        return DeviceInfo(standardVersion: standard, vendorExtensionID: vendorID, vendorExtension: vendor, operations: ops,
                          events: events, properties: props, captureFormats: capture, imageFormats: image,
                          manufacturer: manufacturer, model: model, version: version, serialRange: serialRange)
    }

    /// The payload with the serial number replaced by zeros (same length, so it still parses).
    static func redactingSerial(_ data: Data, _ info: DeviceInfo) -> Data {
        guard let range = info.serialRange else { return data }
        var copy = Data(data)
        for i in stride(from: range.lowerBound, to: range.upperBound - 2, by: 2) {
            copy[copy.startIndex + i] = 0x30
            copy[copy.startIndex + i + 1] = 0
        }
        return copy
    }

    var json: [String: Any] {
        func hexes(_ codes: [UInt16]) -> [String] { codes.map { String(format: "0x%04X", $0) } }
        return [
            "manufacturer": manufacturer, "model": model, "firmware": version,
            "vendorExtensionID": String(format: "0x%08X", vendorExtensionID), "vendorExtension": vendorExtension,
            "operations": hexes(operations), "events": hexes(events), "properties": hexes(properties),
            "captureFormats": hexes(captureFormats), "imageFormats": hexes(imageFormats),
        ]
    }
}
