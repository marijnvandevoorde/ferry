import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cameras that serve their card over plain HTTP on their own Wi-Fi network. They have no session; "connecting"
/// means checking that the camera API answers and reading the file list. Handles are positions in that list.
///
/// Based on the publicly documented APIs: Olympus/OM System OI.Share (`get_imglist.cgi`) and the Ricoh GR II/III
/// Wi-Fi API (`/v1/photos`). Not yet tested on real cameras.
public class HTTPCamera: @unchecked Sendable {
    public let host: String
    public var log: (String) -> Void
    public internal(set) var cameraName = ""
    public internal(set) var isConnected = false
    /// Card-relative paths, e.g. "/DCIM/100OLYMP/P1010001.JPG".
    var files: [(path: String, info: ObjectInfo)] = []
    let base: URL

    init(host: String, port: Int?, log: @escaping (String) -> Void) {
        self.host = host
        self.log = log
        base = URL(string: "http://\(host)\(port.map { ":\($0)" } ?? "")")!
    }

    public var objectHandles: [UInt32] { files.indices.map { UInt32($0 + 1) } }

    public func disconnect() {
        isConnected = false
        log("Disconnected")
    }

    public func objectInfo(_ handle: UInt32) throws -> ObjectInfo {
        try entry(handle).info
    }

    func entry(_ handle: UInt32) throws -> (path: String, info: ObjectInfo) {
        let i = Int(handle) - 1
        guard files.indices.contains(i) else { throw FujiError.protocolError("no object \(handle)") }
        return files[i]
    }

    var headers: [String: String] { [:] }

    /// GET `path` (with query) and return the body; throws `connectionFailed` when nothing answers.
    func get(_ pathAndQuery: String, timeout: TimeInterval = 10) throws -> (Data, Int) {
        guard let url = URL(string: pathAndQuery, relativeTo: base) else { throw FujiError.protocolError("bad URL \(pathAndQuery)") }
        return try perform(URLRequest(url: url, timeoutInterval: timeout))
    }

    /// Sends `request` (with the camera's headers) and returns the body and status code.
    func perform(_ request: URLRequest) throws -> (Data, Int) {
        var request = request
        let url = request.url!
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<(Data, Int), Error>!
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(FujiError.connectionFailed("\(url.absoluteString): \(error.localizedDescription)"))
            } else {
                result = .success((data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result.get()
    }

    /// Downloads to a file without holding it in memory.
    func download(_ pathAndQuery: String, to destination: URL, timeout: TimeInterval = 120) throws {
        guard let url = URL(string: pathAndQuery, relativeTo: base)?.absoluteURL else { throw FujiError.protocolError("bad URL \(pathAndQuery)") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: Error?
        URLSession.shared.downloadTask(with: request) { tmp, response, error in
            if let error {
                failure = FujiError.io(error.localizedDescription)
            } else if let code = (response as? HTTPURLResponse)?.statusCode, code != 200 {
                failure = FujiError.protocolError("HTTP \(code) for \(url.path)")
            } else if let tmp {
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: tmp, to: destination)
                } catch {
                    failure = error
                }
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let failure { throw failure }
    }

    static func info(index: Int, filename: String, size: UInt32, date: Date?) -> ObjectInfo {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return ObjectInfo(handle: UInt32(index + 1), format: 0x3801, compressedSize: size, imageWidth: 0, imageHeight: 0,
                          filename: filename, captureDate: date.map(f.string(from:)) ?? "")
    }
}

// MARK: - Olympus / OM System

/// Olympus and OM System cameras (OI.Share): camera at 192.168.0.10, CGI commands on port 80.
public final class OlympusCamera: HTTPCamera {
    public static let defaultHost = "192.168.0.10"

    public override init(host: String = OlympusCamera.defaultHost, port: Int? = nil, log: @escaping (String) -> Void = { _ in }) {
        super.init(host: host, port: port, log: log)
    }

    override var headers: [String: String] { ["User-Agent": "OlympusCameraKit", "Host": "192.168.0.10"] }

    public func connect(onWaitingForApproval: () -> Void = {}) throws {
        log("Connecting to \(host) (Olympus)")
        let (data, status) = try get("/get_caminfo.cgi", timeout: 5)
        let xml = String(decoding: data, as: UTF8.self)
        guard status == 200, let model = Self.tag("model", in: xml) else {
            throw FujiError.connectionFailed("\(host) is not an Olympus camera")
        }
        cameraName = model
        _ = try? get("/switch_cammode.cgi?mode=play")
        try loadList()
        isConnected = true
        log("Connected to \(cameraName): \(files.count) files")
    }

    func loadList() throws {
        var found: [(String, ObjectInfo)] = []
        for folder in try listing("/DCIM") where folder.isDirectory {
            for file in try listing("/DCIM/\(folder.name)") where !file.isDirectory {
                found.append(("/DCIM/\(folder.name)/\(file.name)",
                              Self.info(index: found.count, filename: file.name, size: file.size, date: file.date)))
            }
        }
        files = found
    }

    struct Entry {
        var name: String
        var size: UInt32
        var isDirectory: Bool
        var date: Date?
    }

    /// `get_imglist.cgi` lines: `dir,name,size,attributes,fatDate,fatTime` after a `VER_100` header.
    func listing(_ dir: String) throws -> [Entry] {
        let (data, status) = try get("/get_imglist.cgi?DIR=\(dir)")
        guard status == 200 else { throw FujiError.protocolError("listing \(dir): HTTP \(status)") }
        return Self.parseListing(String(decoding: data, as: UTF8.self))
    }

    static func parseListing(_ text: String) -> [Entry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 6, let size = UInt32(f[2]), let attributes = Int(f[3]),
                  let fatDate = Int(f[4]), let fatTime = Int(f[5]) else { return nil }
            return Entry(name: String(f[1]), size: size, isDirectory: attributes & 0x10 != 0,
                         date: fatDateTime(date: fatDate, time: fatTime))
        }
    }

    static func fatDateTime(date: Int, time: Int) -> Date? {
        var c = DateComponents()
        c.year = 1980 + (date >> 9)
        c.month = (date >> 5) & 0x0F
        c.day = date & 0x1F
        c.hour = time >> 11
        c.minute = (time >> 5) & 0x3F
        c.second = (time & 0x1F) * 2
        return Calendar(identifier: .gregorian).date(from: c)
    }

    static func tag(_ name: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(name)>"), let end = xml.range(of: "</\(name)>", range: start.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    public func thumbnail(_ handle: UInt32) throws -> Data? {
        let (data, status) = try get("/get_thumbnail.cgi?DIR=\(try entry(handle).path)")
        return status == 200 && data.count >= 100 ? data : nil
    }

    @discardableResult
    public func download(_ handle: UInt32, to destination: URL, progress: (Int64, Int64) -> Void) throws -> ObjectInfo {
        let (path, info) = try entry(handle)
        log("Downloading \(info.filename) (\(info.compressedSize) bytes)")
        try download(path, to: destination)
        try verifySize(destination, expected: info.compressedSize)
        progress(Int64(info.compressedSize), Int64(info.compressedSize))
        return info
    }

    public func refreshObjectCount() throws -> Int {
        try loadList()
        return files.count
    }
}

// MARK: - Ricoh GR

/// Ricoh GR II / GR III / GR IIIx: camera at 192.168.0.1, JSON API under /v1.
public final class RicohCamera: HTTPCamera {
    public static let defaultHost = "192.168.0.1"
    public private(set) var batteryPercent: Int?

    public override init(host: String = RicohCamera.defaultHost, port: Int? = nil, log: @escaping (String) -> Void = { _ in }) {
        super.init(host: host, port: port, log: log)
    }

    public func connect(onWaitingForApproval: () -> Void = {}) throws {
        log("Connecting to \(host) (Ricoh)")
        let (data, status) = try get("/v1/props", timeout: 5)
        guard status == 200, let props = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = props["model"] as? String else {
            throw FujiError.connectionFailed("\(host) is not a Ricoh camera")
        }
        cameraName = model
        batteryPercent = (props["battery"] as? NSNumber)?.intValue
        try loadList()
        isConnected = true
        log("Connected to \(cameraName): \(files.count) files")
    }

    func loadList() throws {
        let (data, status) = try get("/v1/photos")
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dirs = json["dirs"] as? [[String: Any]] else {
            throw FujiError.protocolError("bad photo list from \(cameraName)")
        }
        var found: [(String, ObjectInfo)] = []
        for dir in dirs {
            guard let name = dir["name"] as? String, let names = dir["files"] as? [String] else { continue }
            for file in names {
                let path = "/v1/photos/\(name)/\(file)"
                // Size and date come from the per-file info call.
                var size: UInt32 = 0
                var date: Date?
                if let (infoData, code) = try? get("\(path)/info"), code == 200,
                   let info = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any] {
                    size = (info["size"] as? NSNumber)?.uint32Value ?? 0
                    date = (info["datetime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                }
                found.append((path, Self.info(index: found.count, filename: file, size: size, date: date)))
            }
        }
        files = found
    }

    public func thumbnail(_ handle: UInt32) throws -> Data? {
        let (data, status) = try get("\(try entry(handle).path)?size=thumb")
        return status == 200 && data.count >= 100 ? data : nil
    }

    @discardableResult
    public func download(_ handle: UInt32, to destination: URL, progress: (Int64, Int64) -> Void) throws -> ObjectInfo {
        var (path, info) = try entry(handle)
        log("Downloading \(info.filename)")
        try download(path, to: destination)
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.uint32Value ?? 0
        info.compressedSize = size
        progress(Int64(size), Int64(size))
        return info
    }

    public func refreshObjectCount() throws -> Int {
        if let (data, status) = try? get("/v1/props", timeout: 5), status == 200,
           let props = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            batteryPercent = (props["battery"] as? NSNumber)?.intValue
        }
        try loadList()
        return files.count
    }
}

// MARK: - GoPro

/// GoPro HERO9 and later over the camera's Wi-Fi: the Open GoPro HTTP API on port 8080 (camera at 10.5.5.9).
/// See https://gopro.github.io/OpenGoPro/http. Not yet tested on a real camera.
public final class GoProCamera: HTTPCamera {
    public static let defaultHost = "10.5.5.9"
    public private(set) var batteryPercent: Int?

    public init(host: String = GoProCamera.defaultHost, log: @escaping (String) -> Void = { _ in }) {
        // A host with its own port (the mock camera in tests) keeps it; otherwise the API's port 8080.
        super.init(host: host, port: host.contains(":") ? nil : 8080, log: log)
    }

    public func connect(onWaitingForApproval: () -> Void = {}) throws {
        log("Connecting to \(host) (GoPro)")
        if let (data, status) = try? get("/gopro/camera/info", timeout: 5), status == 200,
           let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            cameraName = info["model_name"] as? String ?? "GoPro"
        } else {
            // Older firmware has no camera info; the version call tells it's a GoPro.
            let (_, status) = try get("/gopro/version", timeout: 5)
            guard status == 200 else { throw FujiError.connectionFailed("\(host) is not a GoPro") }
            cameraName = "GoPro"
        }
        readBattery()
        try loadList()
        isConnected = true
        log("Connected to \(cameraName): \(files.count) files")
    }

    func loadList() throws {
        let (data, status) = try get("/gopro/media/list", timeout: 30)
        guard status == 200 else { throw FujiError.protocolError("media list: HTTP \(status)") }
        files = Self.parseMediaList(data).enumerated().map { index, file in
            ("/videos/DCIM/\(file.path)", Self.info(index: index, filename: file.name, size: file.size, date: file.date))
        }
    }

    /// The files in a `/gopro/media/list` response. Grouped items (bursts, time lapses) are listed once and
    /// expanded here; a photo with `raw` set has a .GPR file next to it. Sizes of those are unknown until downloaded.
    static func parseMediaList(_ data: Data) -> [(path: String, name: String, size: UInt32, date: Date?)] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let media = json["media"] as? [[String: Any]] else { return [] }
        var result: [(path: String, name: String, size: UInt32, date: Date?)] = []
        for folder in media {
            guard let dir = folder["d"] as? String, let entries = folder["fs"] as? [[String: Any]] else { continue }
            for entry in entries {
                guard let name = entry["n"] as? String else { continue }
                let date = (entry["cre"] as? String).flatMap(TimeInterval.init).flatMap(localDate)
                var names = [name]
                if entry["g"] != nil {
                    // Group members share the first four characters and are numbered b...l: G0010001.JPG ... G0010030.JPG.
                    let first = Int(entry["b"] as? String ?? ""), last = Int(entry["l"] as? String ?? "")
                    let missing = Set((entry["m"] as? [String] ?? []).compactMap(Int.init))
                    let ext = (name as NSString).pathExtension
                    if let first, let last, first <= last, name.count >= 8 {
                        names = (first...last).filter { !missing.contains($0) }
                            .map { "\(name.prefix(4))\(String(format: "%04d", $0)).\(ext)" }
                    }
                }
                for n in names {
                    // Group entries carry the member count in "s", not a size.
                    let size = entry["g"] == nil ? UInt32(entry["s"] as? String ?? "") ?? 0 : 0
                    result.append(("\(dir)/\(n)", n, size, date))
                    if entry["raw"] as? String == "1" {
                        let raw = (n as NSString).deletingPathExtension + ".GPR"
                        result.append(("\(dir)/\(raw)", raw, 0, date))
                    }
                }
            }
        }
        return result
    }

    /// Status 70 of the camera state is the internal battery's charge in percent.
    private func readBattery() {
        guard let (data, status) = try? get("/gopro/camera/state", timeout: 5), status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["status"] as? [String: Any] else { return }
        batteryPercent = (values["70"] as? NSNumber)?.intValue
    }

    /// GoPro timestamps are the camera's local clock counted as if it were UTC.
    static func localDate(_ seconds: TimeInterval) -> Date? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let components = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: seconds))
        return Calendar(identifier: .gregorian).date(from: components)
    }

    public func thumbnail(_ handle: UInt32) throws -> Data? {
        let path = try entry(handle).path.replacingOccurrences(of: "/videos/DCIM/", with: "")
        let (data, status) = try get("/gopro/media/thumbnail?path=\(path)")
        return status == 200 && data.count >= 100 ? data : nil
    }

    @discardableResult
    public func download(_ handle: UInt32, to destination: URL, progress: (Int64, Int64) -> Void) throws -> ObjectInfo {
        var (path, info) = try entry(handle)
        log("Downloading \(info.filename)")
        try download(path, to: destination, timeout: 600)
        if info.compressedSize > 0 {
            try verifySize(destination, expected: info.compressedSize)
        } else {
            info.compressedSize = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.uint32Value ?? 0
        }
        progress(Int64(info.compressedSize), Int64(info.compressedSize))
        return info
    }

    public func refreshObjectCount() throws -> Int {
        // Without it the camera may turn its Wi-Fi off.
        _ = try? get("/gopro/camera/keep_alive", timeout: 5)
        readBattery()
        try loadList()
        return files.count
    }
}

extension OlympusCamera: WirelessCamera {}
extension RicohCamera: WirelessCamera {}
extension GoProCamera: WirelessCamera {}
