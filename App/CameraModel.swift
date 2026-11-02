import AppKit
import ImageIO
import FujiKit
import Foundation
import Observation
import Photos

struct PhotoItem: Identifiable, Hashable {
    let id: String
    var handle: UInt32
    let info: ObjectInfo
    var thumbnail: NSImage?
    var imported: Bool

    var date: Date { info.date ?? .distantPast }
}

struct ImportProgress {
    var index: Int
    var total: Int
    var filename: String
    var fraction: Double
}

enum Prefs {
    static let host = "cameraHost"
    static let autoConnect = "autoConnect"
    static let autoImport = "autoImport"
    static let useAlbum = "useAlbum"
    static let albumName = "albumName"
    static let hideResizeNotice = "hideResizeNotice"

    static func register() {
        UserDefaults.standard.register(defaults: [
            host: "",
            autoConnect: true,
            autoImport: false,
            useAlbum: true,
            albumName: "Fujifilm",
        ])
    }
}

@MainActor
@Observable
final class CameraModel {
    enum Phase: Equatable {
        case searching
        case connecting
        case waitingForApproval
        case connected
    }

    private(set) var phase: Phase = .searching
    private(set) var cameraName = ""
    private(set) var items: [PhotoItem] = []
    private(set) var listProgress: (loaded: Int, total: Int) = (0, 0)
    private(set) var isListing = false
    private(set) var importProgress: ImportProgress?
    private(set) var lastError: String?
    private(set) var importSummary: String?
    private(set) var log: [String] = []
    /// Address the app is trying, for display.
    private(set) var cameraAddress = ""
    /// The camera sent reduced-size JPEGs ("Resize image for smartphone" is on).
    private(set) var showResizeNotice = false
    private var lastSearchFailure: String?
    var selection: Set<String> = []

    private var camera: FujiCamera?
    private var sessionTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private let history = ImportHistory()
    private var thumbnailCache: [String: NSImage] = [:]

    var newItems: [PhotoItem] { items.filter { !$0.imported } }
    var isImporting: Bool { importProgress != nil }

    init() {
        Prefs.register()
        #if DEBUG
        DebugSnapshot.startIfRequested()
        #endif
        startSearching()
    }

    // MARK: - Connection

    /// Repeatedly tries to reach the camera while auto-connect is on.
    func startSearching() {
        searchTask?.cancel()
        searchTask = Task {
            while !Task.isCancelled {
                if phase == .searching && UserDefaults.standard.bool(forKey: Prefs.autoConnect) {
                    await connect(quiet: true)
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func connect(quiet: Bool = false) async {
        guard phase == .searching else { return }
        phase = .connecting
        if !quiet { lastError = nil }

        // By default the camera is the Wi-Fi network's router. Connect through the Wi-Fi interface
        // explicitly so a VPN that routes 192.168.x.x can't intercept it.
        let custom = (UserDefaults.standard.string(forKey: Prefs.host) ?? "").trimmingCharacters(in: .whitespaces)
        let wifi = NetworkInfo.wifiInterface
        let host = custom.isEmpty ? (wifi.flatMap(NetworkInfo.router(for:)) ?? "192.168.0.1") : custom
        let isLoopback = host.hasPrefix("127.") || host == "localhost"
        cameraAddress = host
        let clientName = Host.current().localizedName ?? "Mac"
        let camera = FujiCamera(host: host, interface: isLoopback ? nil : wifi, clientName: clientName) { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        }

        do {
            try await camera.run { cam in
                try cam.connect {
                    Task { @MainActor [weak self] in self?.phase = .waitingForApproval }
                }
            }
        } catch {
            camera.disconnect()
            phase = .searching
            // While searching, failing to reach the camera is expected; only surface real problems.
            if case FujiError.connectionFailed(let reason) = error, quiet {
                if reason != lastSearchFailure { appendLog("Not found: \(reason)") }
                lastSearchFailure = reason
                return
            }
            appendLog("Connection failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return
        }

        self.camera = camera
        lastSearchFailure = nil
        cameraName = camera.cameraName
        lastError = nil
        importSummary = nil
        phase = .connected
        sessionTask = Task { await runSession(camera) }
    }

    func disconnect() {
        importTask?.cancel()
        sessionTask?.cancel()
        let camera = self.camera
        self.camera = nil
        Task.detached { camera?.disconnect() }
        resetSession()
    }

    private func resetSession() {
        items = []
        selection = []
        listProgress = (0, 0)
        isListing = false
        importProgress = nil
        phase = .searching
    }

    private func connectionLost(_ error: Error) {
        guard phase == .connected else { return }
        appendLog("Connection lost: \(error.localizedDescription)")
        lastError = "Lost connection to the camera."
        camera = nil
        importTask?.cancel()
        sessionTask?.cancel()
        resetSession()
    }

    // MARK: - Session: listing, thumbnails, keep-alive

    private func runSession(_ camera: FujiCamera) async {
        if camera.isSendingSelection {
            await receiveSelection(camera)
            return
        }
        do {
            try await loadList(camera)
            if UserDefaults.standard.bool(forKey: Prefs.autoImport), !newItems.isEmpty {
                importNew()
            }
            try await loadThumbnails(camera)

            // Keep the connection alive and notice newly taken photos.
            var count = camera.objectCount
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(4))
                if isImporting { continue }
                let newCount = try await camera.run { cam -> Int in
                    try cam.pollEvents()
                    return cam.objectCount
                }
                if newCount != count {
                    count = newCount
                    try await loadList(camera)
                    try await loadThumbnails(camera)
                }
            }
        } catch is CancellationError {
        } catch {
            connectionLost(error)
        }
    }

    private func loadList(_ camera: FujiCamera) async throws {
        isListing = true
        defer { isListing = false }
        let handles = camera.objectHandles
        listProgress = (0, handles.count)
        var loaded: [PhotoItem] = []
        for handle in handles {
            try Task.checkCancellation()
            try await waitWhileImporting()
            let info = try await camera.run { try $0.objectInfo(handle) }
            listProgress.loaded += 1
            guard !info.isFolder else { continue }
            let key = ImportHistory.key(camera: cameraName, info: info)
            loaded.append(PhotoItem(id: key, handle: handle, info: info, thumbnail: thumbnailCache[key],
                                    imported: history.contains(key)))
            // Publish in batches so the grid fills in progressively.
            if loaded.count % 24 == 0 { items = sorted(loaded) }
        }
        items = sorted(loaded)
        selection = selection.intersection(items.map(\.id))
    }

    private func loadThumbnails(_ camera: FujiCamera) async throws {
        for item in items where item.thumbnail == nil {
            try Task.checkCancellation()
            try await waitWhileImporting()
            let handle = item.handle
            guard let data = try await camera.run({ try $0.thumbnail(handle) }),
                  let image = NSImage(data: data) else { continue }
            thumbnailCache[item.id] = image
            if let i = items.firstIndex(where: { $0.id == item.id }) {
                items[i].thumbnail = image
            }
        }
    }

    private func waitWhileImporting() async throws {
        while isImporting {
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    private func sorted(_ items: [PhotoItem]) -> [PhotoItem] {
        items.sorted { $0.date == $1.date ? $0.info.filename > $1.info.filename : $0.date > $1.date }
    }

    // MARK: - Importing

    func importNew() {
        startImport(newItems)
    }

    func importSelected() {
        startImport(items.filter { selection.contains($0.id) })
    }

    func cancelImport() {
        importTask?.cancel()
        // Receiving a selection from the camera runs as part of the session.
        if importTask == nil { sessionTask?.cancel() }
    }

    private func startImport(_ batch: [PhotoItem]) {
        guard let camera, !batch.isEmpty, !isImporting else { return }
        importSummary = nil
        importProgress = ImportProgress(index: 0, total: batch.count, filename: "", fraction: 0)
        importTask = Task { await runImport(batch, camera: camera) }
    }

    /// Where imported files go, or nil (with `lastError` set) when Photos access was denied.
    private func photosTarget() async -> PhotosTarget? {
        let useAlbum = UserDefaults.standard.bool(forKey: Prefs.useAlbum)
        let access = await PhotoImporter.requestAccess(needsAlbum: useAlbum)
        guard access != .denied else {
            lastError = "Fuji Import needs access to Photos. Allow it in System Settings → Privacy & Security → Photos."
            return nil
        }
        var album: PHAssetCollection?
        if useAlbum, access == .full {
            let name = UserDefaults.standard.string(forKey: Prefs.albumName) ?? "Fujifilm"
            album = try? await PhotoImporter.album(named: name.isEmpty ? "Fujifilm" : name)
        }
        return PhotosTarget(album: album)
    }

    private struct PhotosTarget {
        var album: PHAssetCollection?
    }

    /// Downloads one object, imports it into Photos and records it. Returns the imported item's info.
    private func importObject(_ handle: UInt32, filename: String, camera: FujiCamera, target: PhotosTarget,
                              thumbnail: Bool = false, skipIfImported: Bool = false) async throws -> (ObjectInfo, NSImage?) {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("FujiImport", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let file = tmpDir.appendingPathComponent(UUID().uuidString + "-" + filename)
        defer { try? FileManager.default.removeItem(at: file) }

        let info = try await camera.run { cam in
            try cam.download(handle, to: file) { done, total in
                let fraction = total > 0 ? Double(done) / Double(total) : 0
                Task { @MainActor [weak self] in self?.importProgress?.fraction = fraction }
            }
        }
        // Use what was actually downloaded, in case handles shifted since listing.
        let key = ImportHistory.key(camera: cameraName, info: info)
        let image = thumbnail ? NSImage(contentsOf: file) : nil
        if !info.isVideo { checkForResizedImage(file) }
        if !(skipIfImported && history.contains(key)) {
            try await PhotoImporter.importFile(file, originalFilename: info.filename, isVideo: info.isVideo, album: target.album)
            history.insert(key)
        }
        if let i = items.firstIndex(where: { $0.id == key }) { items[i].imported = true }
        selection.remove(key)
        return (info, image)
    }

    private func runImport(_ batch: [PhotoItem], camera: FujiCamera) async {
        defer { importProgress = nil }
        guard let target = await photosTarget() else { return }

        var imported = 0
        var failed: [String] = []
        for (index, item) in batch.enumerated() {
            if Task.isCancelled { break }
            importProgress = ImportProgress(index: index + 1, total: batch.count, filename: item.info.filename, fraction: 0)
            do {
                _ = try await importObject(item.handle, filename: item.info.filename, camera: camera, target: target)
                imported += 1
            } catch let error as FujiError {
                switch error {
                case .disconnected, .timeout, .io:
                    connectionLost(error)
                    return
                default:
                    failed.append(item.info.filename)
                    appendLog("Failed to import \(item.info.filename): \(error.localizedDescription)")
                }
            } catch {
                failed.append(item.info.filename)
                appendLog("Failed to import \(item.info.filename): \(error.localizedDescription)")
            }
        }

        var summary = "Imported \(imported) \(imported == 1 ? "item" : "items") to Photos"
        if Task.isCancelled { summary += " (cancelled)" }
        if !failed.isEmpty { summary += ". \(failed.count) failed: \(failed.prefix(3).joined(separator: ", "))" }
        importSummary = summary
    }

    /// The user picked images on the camera and chose to send them: import each one as the camera offers it.
    private func receiveSelection(_ camera: FujiCamera) async {
        appendLog("Receiving images selected on the camera")
        importProgress = ImportProgress(index: 0, total: 0, filename: "", fraction: 0)
        var received = 0
        var failure: String?
        if let target = await photosTarget() {
            while !Task.isCancelled {
                do {
                    guard let info = try await camera.run({ try $0.nextSelectedImage() }) else { break }
                    importProgress = ImportProgress(index: received + 1, total: 0, filename: info.filename, fraction: 0)
                    let (imported, image) = try await importObject(FujiCamera.selectedImageHandle, filename: info.filename,
                                                                   camera: camera, target: target, thumbnail: true,
                                                                   skipIfImported: true)
                    let key = ImportHistory.key(camera: cameraName, info: imported)
                    if !items.contains(where: { $0.id == key }) {
                        items.insert(PhotoItem(id: key, handle: FujiCamera.selectedImageHandle, info: imported,
                                               thumbnail: image, imported: true), at: 0)
                        received += 1
                    }
                } catch {
                    appendLog("Receiving failed: \(error.localizedDescription)")
                    failure = error.localizedDescription
                    break
                }
            }
        }
        importProgress = nil
        // The camera ends this mode itself; keep showing what arrived until the user disconnects.
        self.camera = nil
        Task.detached { camera.disconnect() }
        importSummary = "Received \(received) \(received == 1 ? "item" : "items") from the camera" + (failure.map { ". Stopped: \($0)" } ?? "")
    }

    /// With "Resize image for smartphone" on, Fuji cameras send ~3 MP JPEGs (2048 px on the long side) over Wi-Fi.
    private func checkForResizedImage(_ file: URL) {
        guard !showResizeNotice, !UserDefaults.standard.bool(forKey: Prefs.hideResizeNotice),
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return }
        if max(width, height) <= 2048 {
            appendLog("Received a \(width)×\(height) image; the camera is probably resizing images for smartphones")
            showResizeNotice = true
        }
    }

    func dismissResizeNotice(forever: Bool) {
        showResizeNotice = false
        if forever { UserDefaults.standard.set(true, forKey: Prefs.hideResizeNotice) }
    }

    func forgetHistory() {
        history.removeAll()
        for i in items.indices { items[i].imported = false }
    }

    // MARK: - Log

    private func appendLog(_ line: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        log.append("[\(f.string(from: Date()))] \(line)")
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
        #if DEBUG
        print(log.last!)
        #endif
    }

    var logText: String { log.joined(separator: "\n") }
}
