import FerryKit
import Foundation

/// `ferryctl serve`: drives the camera for a desktop UI (the Tauri app) over JSON lines.
///
/// Commands, one JSON object per line on stdin:
///   {"cmd": "connect", "bluetooth": true?}      try to connect now (it also retries every few seconds); "bluetooth"
///                                               after a Bluetooth hand-off, kept until "disconnect"
///   {"cmd": "import", "ids": [...]?, "folder": "...", "folders": "{yyyy}/{yyyy-MM-dd}", "rename": "...",
///    "skipVideos": false, "immich": {"server", "apiKey", "album"}?}
///                                               import the given items, or all new ones without "ids";
///                                               with "immich", also upload each file to that Immich server
///   {"cmd": "cancel"}                           stop the running import after the current file
///   {"cmd": "autosave", "enabled": bool}        listen for Fujifilm cameras sending photos over the home network
///                                               (PC AutoSave); registering happens when the camera asks
///   {"cmd": "disconnect"} / {"cmd": "quit"}
///
/// Events, one JSON object per line on stdout:
///   {"event": "status", "phase": "searching|connecting|waitingForApproval|connected", "camera": "...", "address": "..."}
///   {"event": "items", "items": [{"id", "filename", "date", "isVideo", "kind", "protected", "size", "imported"}],
///    "complete": bool, "total": n}                 the list so far, newest first; sent in batches while reading the card
///   {"event": "thumbnail", "id", "path"}
///   {"event": "progress", "index", "total", "filename", "fraction", "bytes", "totalBytes"}
///   {"event": "imported", "id", "path"}
///   {"event": "done", "imported", "failed", "cancelled"}
///   {"event": "autosave", "status": "off|listening|registered|error", "camera"?, "message"?}
///   {"event": "status", ..., "autoSave": true}  connected because the camera came over the home network
///   {"event": "error", "message"}
///   {"event": "log", "line"}
final class Server: @unchecked Sendable {
    private let host: String?
    private let clientName: String
    private let history: ImportHistory
    private let thumbnails: URL
    private let queue = DispatchQueue(label: "ferryctl.serve")
    private let lock = NSLock()
    private let output = FileHandle.standardOutput

    private var camera: WirelessCamera?
    private var items: [String: (handle: UInt32, info: ObjectInfo)] = [:]
    private var objectCount = 0
    private var thumbnailQueue: [String] = []
    /// Card objects still to read, newest first, and the ids read so far.
    private var pendingHandles: [UInt32] = []
    private var listed: [String] = []
    /// Bumped on every new listing or disconnect, so a batch queued for an older one stops.
    private var listGeneration = 0
    private let autoSaveLock = NSLock()
    private var autoSaveListener: AutoSaveListener?
    private var cancelRequested = false
    private var stopped = false
    /// Set by a connect command after a Bluetooth hand-off; newer Fujifilm cameras then use the XApp gallery.
    private var afterBluetoothHandoff = false

    init(host: String?, clientName: String, history: ImportHistory) {
        self.host = host
        self.clientName = clientName
        self.history = history
        thumbnails = FileManager.default.temporaryDirectory.appendingPathComponent("ferryctl-thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
    }

    func run() -> Never {
        emit(["event": "status", "phase": "searching"])
        scheduleTick()
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let name = command["cmd"] as? String else {
                emit(["event": "error", "message": "bad command: \(line)"])
                continue
            }
            switch name {
            case "cancel":
                lock.withLock { cancelRequested = true }
            case "quit":
                queue.sync { disconnect() }
                exit(0)
            case "connect":
                let bluetooth = command["bluetooth"] as? Bool ?? false
                queue.async {
                    if bluetooth { self.afterBluetoothHandoff = true }
                    self.connectIfNeeded(reportFailure: true)
                }
            case "disconnect":
                queue.async { self.disconnect() }
            case "autosave":
                let enabled = command["enabled"] as? Bool ?? false
                queue.async { self.setAutoSave(enabled) }
            case "import":
                lock.withLock { cancelRequested = false }
                queue.async { self.runImport(command) }
            default:
                emit(["event": "error", "message": "unknown command \(name)"])
            }
        }
        // stdin closed: the UI went away.
        queue.sync { disconnect() }
        exit(0)
    }

    // MARK: - Connection

    /// Every few seconds: connect when there's no camera, otherwise keep the connection alive.
    private func scheduleTick() {
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            if camera == nil {
                connectIfNeeded(reportFailure: false)
            } else {
                keepAlive()
            }
            scheduleTick()
        }
    }

    private func connectIfNeeded(reportFailure: Bool) {
        guard camera == nil else { return }
        let wifi = NetworkInfo.wifiInterface
        guard let address = host ?? wifi.flatMap(NetworkInfo.router(for:)) else {
            if reportFailure { emit(["event": "error", "message": "Not connected to a Wi-Fi network."]) }
            return
        }
        emit(["event": "status", "phase": "connecting", "address": address])
        do {
            let camera = try CameraProtocol.connect(
                host: address, interface: host == nil ? wifi : nil, clientName: clientName,
                afterBluetoothHandoff: afterBluetoothHandoff,
                log: { [weak self] in self?.emit(["event": "log", "line": $0]) },
                onWaitingForApproval: { [weak self] in self?.emit(["event": "status", "phase": "waitingForApproval"]) })
            self.camera = camera
            emit(["event": "status", "phase": "connected", "camera": camera.cameraName, "address": address])
            try loadItems()
        } catch {
            camera?.disconnect()
            camera = nil
            emit(["event": "status", "phase": "searching"])
            if reportFailure { emit(["event": "error", "message": error.localizedDescription]) }
        }
    }

    private func keepAlive() {
        // In selection mode the camera drives the transfer; listing doesn't apply.
        guard let camera, (camera as? FujiCamera)?.isSendingSelection != true else { return }
        do {
            let count = try camera.refreshObjectCount()
            if count != objectCount { try loadItems() }
        } catch {
            lost(error)
        }
    }

    private func disconnect() {
        afterBluetoothHandoff = false
        camera?.disconnect()
        camera = nil
        items = [:]
        thumbnailQueue = []
        pendingHandles = []
        listed = []
        listGeneration += 1
        emit(["event": "status", "phase": "searching"])
    }

    private func lost(_ error: Error) {
        emit(["event": "error", "message": "Lost connection to the camera: \(error.localizedDescription)"])
        disconnect()
    }

    // MARK: - Listing

    private func loadItems() throws {
        guard let camera else { return }
        objectCount = camera.objectHandles.count
        // Newest first: new photos are at the end of the card, so they can be imported before the rest is read.
        pendingHandles = camera.objectHandles.reversed()
        listGeneration += 1
        // On a re-read the previous list stays until the new one is complete.
        listed = []
        thumbnailQueue = []
        try listSome(generation: listGeneration)
    }

    /// Reads a batch of the card and reports the list so far, then queues the rest behind any command that came in,
    /// so an import can start before the whole card is read.
    private func listSome(generation: Int) throws {
        guard let camera, generation == listGeneration else { return }
        for handle in pendingHandles.prefix(32) {
            pendingHandles.removeFirst()
            let info = try camera.objectInfo(handle)
            if info.isFolder { continue }
            let id = ImportHistory.key(camera: camera.cameraName, info: info)
            if !listed.contains(id) { listed.append(id) }
            items[id] = (handle, info)
        }
        let complete = pendingHandles.isEmpty
        if complete {
            let current = Set(listed)
            items = items.filter { current.contains($0.key) }
        }
        let shown = complete ? listed : listed + items.keys.filter { !listed.contains($0) }
        emit(["event": "items", "items": shown.compactMap { id in items[id].map { item(id: id, info: $0.info) } },
              "complete": complete, "total": objectCount])
        if complete {
            // Thumbnails of the photos not imported yet first.
            thumbnailQueue = listed.filter { !history.contains($0) } + listed.filter { history.contains($0) }
            loadThumbnails(generation: generation)
        } else {
            queue.async {
                do { try self.listSome(generation: generation) } catch { self.lost(error) }
            }
        }
    }

    /// Loads a few thumbnails, then queues the rest behind any command that came in, so an import doesn't wait
    /// for every thumbnail.
    private func loadThumbnails(generation: Int) {
        guard let camera, generation == listGeneration, !thumbnailQueue.isEmpty else { return }
        for id in thumbnailQueue.prefix(8) {
            thumbnailQueue.removeFirst()
            guard let handle = items[id]?.handle else { continue }
            let file = thumbnails.appendingPathComponent(PathTemplate.sanitize(id) + ".jpg")
            if !FileManager.default.fileExists(atPath: file.path) {
                do {
                    guard let data = try camera.thumbnail(handle) else { continue }
                    try? data.write(to: file)
                } catch {
                    lost(error)
                    return
                }
            }
            emit(["event": "thumbnail", "id": id, "path": file.path])
        }
        queue.async { self.loadThumbnails(generation: generation) }
    }

    private func item(id: String, info: ObjectInfo) -> [String: Any] {
        [
            "id": id,
            "filename": info.filename,
            "date": info.date.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "isVideo": info.isVideo,
            "kind": info.kind.rawValue,
            "protected": info.isProtected,
            "size": Int(info.compressedSize),
            "imported": history.contains(id),
        ]
    }

    // MARK: - PC AutoSave

    private func setAutoSave(_ enabled: Bool) {
        let old = autoSaveLock.withLock { () -> AutoSaveListener? in
            defer { autoSaveListener = nil }
            return autoSaveListener
        }
        old?.stop()
        guard enabled else {
            emit(["event": "autosave", "status": "off"])
            return
        }
        let listener = AutoSaveListener(clientName: clientName) { [weak self] in self?.emit(["event": "log", "line": $0]) }
        autoSaveLock.withLock { autoSaveListener = listener }
        emit(["event": "autosave", "status": "listening"])
        Thread.detachNewThread { [weak self] in
            while let self, self.autoSaveLock.withLock({ self.autoSaveListener === listener }) {
                do {
                    guard let event = try listener.waitForCamera(timeout: 1) else { continue }
                    self.queue.async { self.handleAutoSave(event) }
                } catch {
                    self.emit(["event": "autosave", "status": "error", "message": error.localizedDescription])
                    Thread.sleep(forTimeInterval: 5)
                }
            }
            listener.stop()
        }
    }

    private func handleAutoSave(_ event: AutoSaveListener.Event) {
        switch event {
        case .registered(let camera, let model):
            emit(["event": "autosave", "status": "registered", "camera": model.isEmpty ? camera : model])
        case .importRequest(let cameraHost, _):
            guard camera == nil else {
                emit(["event": "log", "line": "AutoSave: ignoring the camera's request, already connected"])
                return
            }
            emit(["event": "status", "phase": "connecting", "address": cameraHost])
            // PC AutoSave is Fuji-only.
            let fuji = FujiCamera(host: cameraHost, clientName: clientName) { [weak self] in self?.emit(["event": "log", "line": $0]) }
            do {
                try fuji.connect { [weak self] in self?.emit(["event": "status", "phase": "waitingForApproval"]) }
                camera = fuji
                emit(["event": "status", "phase": "connected", "camera": fuji.cameraName, "address": cameraHost, "autoSave": true])
                try loadItems()
            } catch {
                camera?.disconnect()
                camera = nil
                emit(["event": "status", "phase": "searching"])
                emit(["event": "error", "message": error.localizedDescription])
            }
        }
    }

    // MARK: - Importing

    private func runImport(_ command: [String: Any]) {
        guard let camera else {
            emit(["event": "error", "message": "No camera connected."])
            return
        }
        guard let folder = command["folder"] as? String, !folder.isEmpty else {
            emit(["event": "error", "message": "Choose a folder to import into."])
            return
        }
        let target = FolderImport(root: URL(fileURLWithPath: (folder as NSString).expandingTildeInPath),
                                  folderTemplate: PathTemplate(command["folders"] as? String ?? PathTemplate.defaultFolder.template),
                                  fileTemplate: (command["rename"] as? String).flatMap { $0.isEmpty ? nil : PathTemplate($0) })
        let skipVideos = command["skipVideos"] as? Bool ?? false
        var immich: ImmichUpload?
        if let config = command["immich"] as? [String: Any], let server = (config["server"] as? String).flatMap(URL.init(string:)),
           let key = config["apiKey"] as? String, !key.isEmpty {
            immich = ImmichUpload(server: server, apiKey: key, albumName: config["album"] as? String, deviceID: clientName)
        }
        let ids: [String]
        if let requested = command["ids"] as? [String] {
            ids = requested.filter { items[$0] != nil }
        } else {
            ids = items.filter { !history.contains($0.key) && !(skipVideos && $0.value.info.isVideo) }
                .sorted { ($0.value.info.date ?? .distantPast) < ($1.value.info.date ?? .distantPast) }
                .map(\.key)
        }

        let totalBytes = ids.reduce(0) { $0 + Int(items[$1]?.info.compressedSize ?? 0) }
        try? FileManager.default.createDirectory(at: target.root, withIntermediateDirectories: true)
        if let free = (try? FileManager.default.attributesOfFileSystem(forPath: target.root.path))?[.systemFreeSize] as? NSNumber,
           free.int64Value < Int64(totalBytes) + Int64(totalBytes) / 20 + 50_000_000 {
            let need = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: free.int64Value, countStyle: .file)
            emit(["event": "error", "message": "Not enough free space: the import needs \(need) but only \(have) is free."])
            emit(["event": "done", "imported": 0, "failed": [String](), "cancelled": false])
            return
        }

        var imported = 0
        var failed: [String] = []
        var bytesBefore = 0
        for (index, id) in ids.enumerated() {
            if lock.withLock({ cancelRequested }) { break }
            guard let (handle, info) = items[id] else { continue }
            emit(["event": "progress", "index": index + 1, "total": ids.count, "filename": info.filename, "fraction": 0.0,
                  "bytes": bytesBefore, "totalBytes": totalBytes])
            defer { bytesBefore += Int(info.compressedSize) }
            let tmp = target.root.appendingPathComponent(".ferryctl-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tmp) }
            do {
                try FileManager.default.createDirectory(at: target.root, withIntermediateDirectories: true)
                var lastReport = Date.distantPast
                let downloaded = try camera.download(handle, to: tmp) { done, total in
                    guard Date().timeIntervalSince(lastReport) > 0.2, total > 0 else { return }
                    lastReport = Date()
                    self.emit(["event": "progress", "index": index + 1, "total": ids.count, "filename": info.filename,
                               "fraction": Double(done) / Double(total), "bytes": bytesBefore + Int(done), "totalBytes": totalBytes])
                }
                let url = try target.store(tmp, info: downloaded, camera: camera.cameraName, move: true)
                if let immich {
                    let semaphore = DispatchSemaphore(value: 0)
                    nonisolated(unsafe) var uploadError: Error?
                    Task {
                        do { try await immich.upload(url, info: downloaded, key: id) } catch { uploadError = error }
                        semaphore.signal()
                    }
                    // Uploads can take a while; Fuji cameras hang up on a connection that goes quiet.
                    while semaphore.wait(timeout: .now() + 3) == .timedOut {
                        if camera is FujiCamera { _ = try? camera.refreshObjectCount() }
                    }
                    if let uploadError { throw uploadError }
                }
                history.insert(id)
                imported += 1
                emit(["event": "imported", "id": id, "path": url.path])
            } catch let error as FujiError where error.isConnectionLoss {
                lost(error)
                break
            } catch {
                failed.append(info.filename)
                emit(["event": "log", "line": "Failed to import \(info.filename): \(error.localizedDescription)"])
            }
        }
        emit(["event": "done", "imported": imported, "failed": failed, "cancelled": lock.withLock { cancelRequested }])
    }

    // MARK: - Output

    func emit(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        lock.withLock {
            output.write(data)
            output.write(Data([0x0A]))
        }
    }
}
