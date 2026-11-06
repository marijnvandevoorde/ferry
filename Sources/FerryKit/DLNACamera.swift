import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Cameras that share their photos as a UPnP/DLNA media server on their own Wi-Fi network: older Sony cameras
/// ("Send to Smartphone"/"View on Smartphone") and Panasonic Lumix. Finds the ContentDirectory service in the
/// device description, browses it, and downloads the original-size resource of each photo.
///
/// `host` may be the camera's address (the description is looked up via SSDP or the known locations) or a full
/// description URL. Not yet tested on real cameras.
public final class DLNACamera: HTTPCamera {
    /// Where cameras publish their device description when SSDP gives no answer.
    static let knownDescriptions = [
        "http://192.168.122.1:64321/DmsDesc.xml",   // Sony
        "http://192.168.54.1:60606/Server0/ddd",    // Panasonic
    ]

    static let cameraMakers = ["Sony", "Panasonic"]

    private(set) var controlURL: URL?
    private var manufacturer = ""

    public init(host: String, log: @escaping (String) -> Void = { _ in }) {
        super.init(host: host, port: nil, log: log)
    }

    public func connect(onWaitingForApproval: () -> Void = {}) throws {
        log("Looking for a DLNA media server at \(host)")
        let candidates = host.hasPrefix("http") ? [host]
            : SSDP.search(target: "urn:schemas-upnp-org:service:ContentDirectory:1", timeout: 1).filter { $0.contains("//\(host)") }
              + Self.knownDescriptions.filter { $0.contains("//\(host):") }
        for location in candidates {
            guard let url = URL(string: location), let (data, status) = try? fetch(url, timeout: 5), status == 200,
                  let description = DeviceDescription(xml: data, base: url), let control = description.contentDirectoryControl else {
                continue
            }
            // Routers, TVs and NAS boxes run media servers too; only take cameras.
            guard Self.cameraMakers.contains(where: description.manufacturer.localizedCaseInsensitiveContains) else {
                log("Ignoring the media server of \(description.manufacturer) \(description.modelName): not a camera")
                continue
            }
            controlURL = control
            manufacturer = description.manufacturer
            cameraName = description.friendlyName.isEmpty ? description.modelName : description.friendlyName
            break
        }
        guard let controlURL else { throw FujiError.connectionFailed("no DLNA media server at \(host)") }
        log("Found \(cameraName) (\(manufacturer)), browsing \(controlURL.absoluteString)")
        if manufacturer.localizedCaseInsensitiveContains("panasonic") { preparePanasonic(controlURL) }
        try loadList()
        isConnected = true
        log("Connected to \(cameraName): \(files.count) files")
    }

    /// Lumix cameras only share their card after the app asks for access and switches to playback.
    private func preparePanasonic(_ control: URL) {
        guard let base = URL(string: "http://\(control.host ?? host)") else { return }
        let id = "4D454930-0100-1000-8001-\(String(UUID().uuidString.suffix(12)))"
        for query in ["mode=accctrl&type=req_acc&value=\(id)&value2=Ferry", "mode=camcmd&value=playmode"] {
            _ = try? fetch(base.appendingPathComponent("cam.cgi").appendingQuery(query), timeout: 5)
        }
    }

    func loadList() throws {
        var found: [(String, ObjectInfo)] = []
        var containers = ["0"]
        var visited = Set<String>()
        while let id = containers.popLast(), visited.insert(id).inserted, visited.count < 500 {
            let result = try browse(id)
            containers += result.containers
            for item in result.items {
                found.append((item.url.absoluteString,
                              Self.info(index: found.count, filename: item.filename, size: item.size, date: item.date)))
            }
        }
        files = found
    }

    struct Item {
        var url: URL
        var filename: String
        var size: UInt32
        var date: Date?
        var thumbnail: URL?
    }

    private var thumbnails: [String: URL] = [:]

    func browse(_ objectID: String) throws -> (containers: [String], items: [Item]) {
        guard let controlURL else { throw FujiError.disconnected }
        var start = 0
        var containers: [String] = []
        var items: [Item] = []
        while true {
            let body = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
            <ObjectID>\(objectID)</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter>
            <StartingIndex>\(start)</StartingIndex><RequestedCount>200</RequestedCount><SortCriteria></SortCriteria>
            </u:Browse></s:Body></s:Envelope>
            """
            var request = URLRequest(url: controlURL, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.httpBody = Data(body.utf8)
            request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
            request.setValue("\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"", forHTTPHeaderField: "SOAPACTION")
            let (data, status) = try perform(request)
            guard status == 200 else { throw FujiError.protocolError("Browse \(objectID): HTTP \(status)") }
            let page = BrowseResult(soap: data, base: controlURL)
            containers += page.containers
            items += page.items
            start += page.returned
            if page.returned == 0 || start >= page.total { break }
        }
        for item in items { if let t = item.thumbnail { thumbnails[item.url.absoluteString] = t } }
        return (containers, items)
    }

    public func thumbnail(_ handle: UInt32) throws -> Data? {
        guard let url = thumbnails[try entry(handle).path], let (data, status) = try? fetch(url) else { return nil }
        return status == 200 && data.count >= 100 ? data : nil
    }

    @discardableResult
    public func download(_ handle: UInt32, to destination: URL, progress: (Int64, Int64) -> Void) throws -> ObjectInfo {
        var (path, info) = try entry(handle)
        log("Downloading \(info.filename)")
        try download(path, to: destination, expected: Int64(info.compressedSize), progress: progress)
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.uint32Value ?? 0
        info.compressedSize = size
        progress(Int64(size), Int64(size))
        return info
    }

    public func refreshObjectCount() throws -> Int {
        try loadList()
        return files.count
    }

    private func fetch(_ url: URL, timeout: TimeInterval = 10) throws -> (Data, Int) {
        try perform(URLRequest(url: url, timeoutInterval: timeout))
    }
}

extension DLNACamera: WirelessCamera {}

private extension URL {
    func appendingQuery(_ query: String) -> URL {
        URL(string: absoluteString + "?" + query) ?? self
    }
}

// MARK: - UPnP parsing

/// The parts of a UPnP device description we need.
struct DeviceDescription {
    var friendlyName = ""
    var manufacturer = ""
    var modelName = ""
    var contentDirectoryControl: URL?

    init?(xml: Data, base: URL) {
        let doc = XMLTree.parse(xml)
        guard let device = doc?.first("device") else { return nil }
        friendlyName = device.child("friendlyName")?.text ?? ""
        manufacturer = device.child("manufacturer")?.text ?? ""
        modelName = device.child("modelName")?.text ?? ""
        let urlBase = doc?.first("URLBase")?.text.flatMap(URL.init(string:)) ?? base
        for service in doc?.all("service") ?? [] where service.child("serviceType")?.text?.contains("ContentDirectory") == true {
            if let path = service.child("controlURL")?.text {
                contentDirectoryControl = URL(string: path, relativeTo: urlBase)?.absoluteURL
            }
        }
    }
}

/// A Browse response: DIDL-Lite inside the SOAP `Result` element.
struct BrowseResult {
    var containers: [String] = []
    var items: [DLNACamera.Item] = []
    var returned = 0
    var total = 0

    init(soap: Data, base: URL) {
        guard let envelope = XMLTree.parse(soap) else { return }
        returned = Int(envelope.first("NumberReturned")?.text ?? "") ?? 0
        total = Int(envelope.first("TotalMatches")?.text ?? "") ?? 0
        guard let didl = envelope.first("Result")?.text, let tree = XMLTree.parse(Data(didl.utf8)) else { return }
        containers = tree.all("container").compactMap { $0.attributes["id"] }
        for item in tree.all("item") {
            let resources = item.children.filter { $0.name == "res" }
            // Photos come with several resolutions; the original is the largest. Skip non-image/video items.
            let media = resources.filter {
                let info = $0.attributes["protocolInfo"] ?? ""
                return info.contains("image/") || info.contains("video/")
            }
            guard let original = media.max(by: { size($0) < size($1) }), let text = original.text,
                  let url = URL(string: text, relativeTo: base)?.absoluteURL else { continue }
            let thumb = media.min(by: { size($0) < size($1) }).flatMap { $0 === original ? nil : $0.text }.flatMap { URL(string: $0, relativeTo: base) }
            let title = item.child("title")?.text ?? url.lastPathComponent
            let filename = (title as NSString).pathExtension.isEmpty ? url.lastPathComponent : title
            let date = item.child("date")?.text.flatMap(Self.parseDate)
            items.append(.init(url: url, filename: filename, size: UInt32(clamping: size(original)), date: date, thumbnail: thumb))
        }
    }

    private func size(_ res: XMLTree) -> Int {
        if let s = res.attributes["size"], let n = Int(s) { return n }
        // Some cameras only give a resolution.
        let parts = (res.attributes["resolution"] ?? "").split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * parts[1] : 0
    }

    static func parseDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: text) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: text) { return d }
        }
        return nil
    }
}

/// A minimal XML tree; namespaces prefixes are dropped from element names.
final class XMLTree: NSObject, XMLParserDelegate {
    var name = ""
    var attributes: [String: String] = [:]
    var children: [XMLTree] = []
    private var buffer = ""
    var text: String? { buffer.isEmpty ? nil : buffer.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var stack: [XMLTree] = []

    static func parse(_ data: Data) -> XMLTree? {
        let root = XMLTree()
        let parser = XMLParser(data: data)
        root.stack = [root]
        parser.delegate = root
        return parser.parse() ? root.children.first : nil
    }

    func child(_ name: String) -> XMLTree? { children.first { $0.name == name } }
    func first(_ name: String) -> XMLTree? { name == self.name ? self : children.lazy.compactMap { $0.first(name) }.first }
    func all(_ name: String) -> [XMLTree] { (self.name == name ? [self] : []) + children.flatMap { $0.all(name) } }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let node = XMLTree()
        node.name = String(elementName.split(separator: ":").last ?? Substring(elementName))
        node.attributes = attributes
        stack.last?.children.append(node)
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        stack.removeLast()
    }
}
