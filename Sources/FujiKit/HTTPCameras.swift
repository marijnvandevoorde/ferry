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
        var request = URLRequest(url: url, timeoutInterval: timeout)
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
        guard let url = URL(string: pathAndQuery, relativeTo: base) else { throw FujiError.protocolError("bad URL \(pathAndQuery)") }
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
        try loadList()
        return files.count
    }
}

extension OlympusCamera: WirelessCamera {}
extension RicohCamera: WirelessCamera {}
