import AppKit
import ImageIO
import FerryKit
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
    /// Bytes of the whole batch, for speed and time left (0 when unknown).
    var bytesDone: Int64 = 0
    var totalBytes: Int64 = 0
    var started = Date()

    /// Bytes per second since the import started.
    var speed: Double? {
        let elapsed = Date().timeIntervalSince(started)
        return elapsed > 2 && bytesDone > 0 ? Double(bytesDone) / elapsed : nil
    }

    var timeRemaining: TimeInterval? {
        guard let speed, speed > 0, totalBytes > bytesDone else { return nil }
        return Double(totalBytes - bytesDone) / speed
    }
}

/// Where the last import went, so it can be shown.
enum ImportLocation: Equatable {
    case photos
    case folder(URL)
}

enum Prefs {
    static let host = "cameraHost"
    static let autoConnect = "autoConnect"
    static let autoImport = "autoImport"
    static let useAlbum = "useAlbum"
    static let albumName = "albumName"
    static let hideResizeNotice = "hideResizeNotice"
    static let lastCameraName = "lastCameraName"
    static let lastCameraGeneration = "lastCameraGeneration"
    static let destination = "destination"
    static let folderBookmark = "folderBookmark"
    static let folderTemplate = "folderTemplate"
    static let renameFiles = "renameFiles"
    static let fileTemplate = "fileTemplate"
    static let backupEnabled = "backupEnabled"
    static let backupBookmark = "backupBookmark"
    static let skipVideos = "skipVideos"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let hideDockIcon = "hideDockIcon"
    static let autoSave = "autoSave"
    static let protectedOnly = "protectedOnly"
    static let sortOldestFirst = "sortOldestFirst"
    static let thumbnailSize = "thumbnailSize"
    static let immichEnabled = "immichEnabled"
    static let immichServer = "immichServer"
    static let immichAlbum = "immichAlbum"
    /// JSON list of `FujiBluetooth.Pairing`.
    static let bluetoothPairings = "bluetoothPairings"
    /// Cameras whose "already copied these?" notice was closed.
    static let backlogNoticeDismissed = "backlogNoticeDismissed"

    static func register() {
        UserDefaults.standard.register(defaults: [
            host: "",
            autoConnect: true,
            autoImport: false,
            useAlbum: true,
            albumName: "Fujifilm",
            destination: DestinationKind.photos.rawValue,
            folderTemplate: PathTemplate.defaultFolder.template,
            renameFiles: false,
            fileTemplate: "{yyyy-MM-dd}_{original}",
            backupEnabled: false,
            skipVideos: false,
            showMenuBarIcon: true,
            hideDockIcon: false,
            autoSave: false,
            protectedOnly: false,
            sortOldestFirst: false,
            thumbnailSize: 170.0,
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
    /// The Bluetooth link to a newer camera whose Wi-Fi was started over Bluetooth. Kept open while connected,
    /// because the camera may turn its Wi-Fi off when it drops; cleared on disconnect.
    private(set) var bluetoothLink: FujiBluetoothCentral?
    var selection: Set<String> = []

    private var camera: SerialCamera?
    private var sessionTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private let history = ImportHistory()
    private var thumbnailCache: [String: NSImage] = [:]
    /// Items of an import that the connection dropped in the middle of; resumed after reconnecting.
    private var pendingImport: Set<String> = []
    private var autoSaveTask: Task<Void, Never>?
    /// What the PC AutoSave listener is doing, for Settings.
    private(set) var autoSaveStatus = ""

    var newItems: [PhotoItem] { items.filter { !$0.imported } }
    /// What "Import New" imports: new items, without videos if the user chose to skip them.
    var itemsToImport: [PhotoItem] {
        let skipVideos = UserDefaults.standard.bool(forKey: Prefs.skipVideos)
        return newItems.filter { !(skipVideos && $0.info.isVideo) && matchesFilters($0) }
    }

    /// Gallery filters; "Import New" imports what the filters show.
    var kindFilter: ObjectInfo.Kind?
    var protectedOnly = UserDefaults.standard.bool(forKey: Prefs.protectedOnly) {
        didSet { UserDefaults.standard.set(protectedOnly, forKey: Prefs.protectedOnly) }
    }

    func matchesFilters(_ item: PhotoItem) -> Bool {
        (kindFilter == nil || item.info.kind == kindFilter) && (!protectedOnly || item.info.isProtected)
    }

    /// Where the last finished import went.
    private(set) var lastImportLocation: ImportLocation?
    var isImporting: Bool { importProgress != nil }

    init() {
        Prefs.register()
        #if DEBUG
        DebugSnapshot.startIfRequested()
        // Lets scripts test folder imports without the open panel.
        let env = ProcessInfo.processInfo.environment
        if let path = env["FERRY_TEST_FOLDER"] { FolderBookmark.save(URL(fileURLWithPath: path), for: Prefs.folderBookmark) }
        if let path = env["FERRY_TEST_BACKUP"] { FolderBookmark.save(URL(fileURLWithPath: path), for: Prefs.backupBookmark) }
        #endif
        startSearching()
        updateAutoSave()
    }

    // MARK: - Connection

    /// Repeatedly tries to reach the camera while auto-connect is on.
    func startSearching() {
        searchTask?.cancel()
        searchTask = Task {
            while !Task.isCancelled {
                // An import the connection dropped in the middle of reconnects even without auto-connect.
                if phase == .searching && (UserDefaults.standard.bool(forKey: Prefs.autoConnect) || !pendingImport.isEmpty) {
                    await connect(quiet: true)
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Connects to the camera on its own Wi-Fi network, or to `autoSaveHost` when the camera reached out over
    /// the home network (PC AutoSave).
    func connect(quiet: Bool = false, autoSaveHost: String? = nil) async {
        guard phase == .searching else { return }
        phase = .connecting
        if !quiet { lastError = nil }

        // By default the camera is the Wi-Fi network's router. Connect through the Wi-Fi interface
        // explicitly so a VPN that routes 192.168.x.x can't intercept it.
        let custom = (UserDefaults.standard.string(forKey: Prefs.host) ?? "").trimmingCharacters(in: .whitespaces)
        let wifi = NetworkInfo.wifiInterface
        let host = autoSaveHost ?? (custom.isEmpty ? (wifi.flatMap(NetworkInfo.router(for:)) ?? "192.168.0.1") : custom)
        let isLoopback = host.hasPrefix("127.") || host == "localhost"
        cameraAddress = host
        let clientName = Host.current().localizedName ?? "Mac"
        let interface = isLoopback || autoSaveHost != nil ? nil : wifi
        let log: (String) -> Void = { [weak self] line in Task { @MainActor in self?.appendLog(line) } }
        let onApproval: () -> Void = { Task { @MainActor [weak self] in self?.phase = .waitingForApproval } }
        let afterBluetoothHandoff = bluetoothLink != nil

        let camera: SerialCamera
        do {
            camera = SerialCamera(try await Task.detached {
                if autoSaveHost != nil {
                    // PC AutoSave is Fuji-only.
                    let fuji = FujiCamera(host: host, interface: interface, clientName: clientName, log: log)
                    try fuji.connect(onWaitingForApproval: onApproval)
                    return fuji as WirelessCamera
                }
                // Fuji's protocol first, then standard PTP/IP (Canon and others).
                return try CameraProtocol.connect(host: host, interface: interface, clientName: clientName,
                                                  afterBluetoothHandoff: afterBluetoothHandoff, log: log,
                                                  onWaitingForApproval: onApproval)
            }.value)
        } catch {
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
        cameraName = camera.camera.cameraName
        if let fuji = camera.fuji { CameraGuide.remember(fuji.profile) }
        lastError = nil
        importSummary = nil
        phase = .connected
        sessionTask = Task { await runSession(camera) }
    }

    /// Called once a camera's Wi-Fi was started over Bluetooth and this Mac joined it.
    func connectAfterBluetoothHandoff(_ link: FujiBluetoothCentral) async {
        bluetoothLink = link
        // The new network needs a moment to give this Mac an address.
        for _ in 0..<10 where phase == .searching {
            await connect()
            if phase != .searching { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func disconnect() {
        bluetoothLink?.disconnect()
        bluetoothLink = nil
        pendingImport = []
        importTask?.cancel()
        sessionTask?.cancel()
        let camera = self.camera
        self.camera = nil
        Task.detached { camera?.camera.disconnect() }
        resetSession()
    }

    private func resetSession() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("Previews"))
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
        lastError = String(localized: "Lost connection to the camera.")
        camera = nil
        importTask?.cancel()
        sessionTask?.cancel()
        resetSession()
    }

    // MARK: - PC AutoSave

    /// Starts or stops listening for cameras on the home network, following the setting.
    func updateAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        guard UserDefaults.standard.bool(forKey: Prefs.autoSave) else {
            autoSaveStatus = ""
            return
        }
        autoSaveStatus = String(localized: "Listening for cameras on this network")
        let clientName = Host.current().localizedName ?? "Mac"
        autoSaveTask = Task.detached { [weak self] in
            let listener = AutoSaveListener(clientName: clientName) { line in
                Task { @MainActor in self?.appendLog(line) }
            }
            defer { listener.stop() }
            while !Task.isCancelled {
                do {
                    guard let event = try listener.waitForCamera(timeout: 1) else { continue }
                    await self?.handleAutoSave(event)
                } catch {
                    let message = error.localizedDescription
                    await MainActor.run {
                        self?.autoSaveStatus = message
                        self?.appendLog("AutoSave: \(message)")
                    }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func handleAutoSave(_ event: AutoSaveListener.Event) async {
        switch event {
        case .registered(let camera, let model):
            let name = model.isEmpty ? camera : model
            autoSaveStatus = String(localized: "Registered with \(name)")
            Notifier.post(String(localized: "Camera registered"), String(localized: "\(name) can now send photos to this Mac."))
        case .importRequest(let host, _):
            guard phase == .searching else {
                appendLog("AutoSave: ignoring the camera's request, already connected")
                return
            }
            await connect(autoSaveHost: host)
        }
    }

    // MARK: - Session: listing, thumbnails, keep-alive

    private func runSession(_ camera: SerialCamera) async {
        if camera.fuji?.isSendingSelection == true {
            await receiveSelection(camera)
            return
        }
        do {
            try await loadList(camera)
            if camera.fuji?.isAutoSave == true {
                // The camera came to us to deliver photos: take everything new, then let it go.
                startImport(itemsToImport)
                await importTask?.value
                if pendingImport.isEmpty { disconnect() }
                return
            }
            let resumable = items.filter { pendingImport.contains($0.id) && !$0.imported }
            pendingImport = []
            if !resumable.isEmpty {
                appendLog("Resuming the interrupted import (\(resumable.count) left)")
                startImport(resumable)
            } else if UserDefaults.standard.bool(forKey: Prefs.autoImport), !itemsToImport.isEmpty {
                importNew()
            } else if !itemsToImport.isEmpty {
                let n = itemsToImport.count
                Notifier.post(cameraName.isEmpty ? String(localized: "Camera connected") : cameraName, String(localized: "\(n) new items to import"))
            }
            try await loadThumbnails(camera)

            // Keep the connection alive and notice newly taken photos.
            var count = camera.camera.objectHandles.count
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(4))
                if isImporting { continue }
                let newCount = try await camera.run { try $0.refreshObjectCount() }
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

    private func loadList(_ camera: SerialCamera) async throws {
        isListing = true
        defer { isListing = false }
        let handles = camera.camera.objectHandles
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

    private func loadThumbnails(_ camera: SerialCamera) async throws {
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
        startImport(itemsToImport)
    }

    func importSelected() {
        startImport(items.filter { selection.contains($0.id) })
    }

    func cancelImport() {
        pendingImport = []
        importTask?.cancel()
        // Receiving a selection from the camera runs as part of the session.
        if importTask == nil { sessionTask?.cancel() }
    }

    func startImport(_ batch: [PhotoItem]) {
        guard let camera, !batch.isEmpty, !isImporting else { return }
        importSummary = nil
        importProgress = ImportProgress(index: 0, total: batch.count, filename: "", fraction: 0)
        importTask = Task { await runImport(batch, camera: camera) }
    }

    /// The configured destinations, ready to use, or nil (with `lastError` set) when one can't be used.
    private func prepareDestinations() async -> [Destination]? {
        let destinations = configuredDestinations()
        do {
            for destination in destinations { try await destination.prepare() }
        } catch {
            lastError = error.localizedDescription
            appendLog("Can't import: \(error.localizedDescription)")
            return nil
        }
        return destinations
    }

    /// Downloads one object, imports it into Photos and records it. Returns the imported item's info.
    private func importObject(_ handle: UInt32, filename: String, camera: SerialCamera, destinations: [Destination],
                              thumbnail: Bool = false, skipIfImported: Bool = false) async throws -> (ObjectInfo, NSImage?) {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("Ferry", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let file = tmpDir.appendingPathComponent(UUID().uuidString + "-" + filename)
        defer { try? FileManager.default.removeItem(at: file) }

        let info = try await camera.run { cam in
            try cam.download(handle, to: file) { done, total in
                let fraction = total > 0 ? Double(done) / Double(total) : 0
                Task { @MainActor [weak self] in
                    guard let self, var p = importProgress else { return }
                    p.fraction = fraction
                    p.bytesDone = batchBytesBefore + done
                    importProgress = p
                }
            }
        }
        // Use what was actually downloaded, in case handles shifted since listing.
        let key = ImportHistory.key(camera: cameraName, info: info)
        let image = thumbnail ? NSImage(contentsOf: file) : nil
        if !info.isVideo { checkForResizedImage(file) }
        if !(skipIfImported && history.contains(key)) {
            // Storing can take a while (Photos, Immich); the camera hangs up on a connection that goes quiet.
            let keepAlive = keepAlive(camera)
            defer { keepAlive?.cancel() }
            for (i, destination) in destinations.enumerated() {
                try await destination.store(file, info: info, camera: cameraName, move: i == destinations.count - 1)
            }
            history.insert(key)
        }
        if let i = items.firstIndex(where: { $0.id == key }) { items[i].imported = true }
        selection.remove(key)
        return (info, image)
    }

    /// Polls a Fuji camera every few seconds until cancelled. Other cameras' polls list the whole card, so they're left alone.
    private func keepAlive(_ camera: SerialCamera) -> Task<Void, Never>? {
        guard camera.fuji != nil else { return nil }
        return Task {
            while (try? await Task.sleep(for: .seconds(3))) != nil {
                // A lost connection shows up in the next download.
                _ = try? await camera.run { try $0.refreshObjectCount() }
            }
        }
    }

    /// Bytes of the current batch that finished before the file being downloaded.
    private var batchBytesBefore: Int64 = 0

    private func runImport(_ batch: [PhotoItem], camera: SerialCamera) async {
        defer { importProgress = nil }
        let activity = keepAwake()
        defer { ProcessInfo.processInfo.endActivity(activity) }
        guard let destinations = await prepareDestinations() else { return }

        let totalBytes = batch.reduce(Int64(0)) { $0 + Int64($1.info.compressedSize) }
        if let shortage = Self.spaceShortage(needed: totalBytes, destinations: destinations) {
            lastError = shortage
            appendLog("Not enough space: \(shortage)")
            return
        }
        let started = Date()
        batchBytesBefore = 0

        var imported = 0
        var failed: [String] = []
        pendingImport = Set(batch.map(\.id))
        for (index, item) in batch.enumerated() {
            if Task.isCancelled { break }
            importProgress = ImportProgress(index: index + 1, total: batch.count, filename: item.info.filename, fraction: 0,
                                            bytesDone: batchBytesBefore, totalBytes: totalBytes, started: started)
            defer { batchBytesBefore += Int64(item.info.compressedSize) }
            // One retry for errors that aren't a lost connection.
            for attempt in 1...2 {
                do {
                    _ = try await importObject(item.handle, filename: item.info.filename, camera: camera, destinations: destinations)
                    imported += 1
                    pendingImport.remove(item.id)
                    break
                } catch let error as FujiError where error.isConnectionLoss {
                    // Keep `pendingImport`: the import continues after reconnecting.
                    connectionLost(error)
                    return
                } catch {
                    appendLog("Failed to import \(item.info.filename): \(error.localizedDescription)")
                    if attempt == 2 {
                        failed.append(item.info.filename)
                        pendingImport.remove(item.id)
                    }
                }
            }
        }
        pendingImport = []

        var summary = String(localized: "Imported \(imported) items to \(destinations.last?.displayName ?? "Photos")")
        if Task.isCancelled { summary += String(localized: " (cancelled)") }
        if !failed.isEmpty { summary += String(localized: ". \(failed.count) failed: \(failed.prefix(3).joined(separator: ", "))") }
        importSummary = summary
        if imported > 0 { lastImportLocation = destinations.last?.location }
        Notifier.post(failed.isEmpty && imported > 0 ? String(localized: "Your new photos have arrived") : String(localized: "Import finished"), summary)
    }

    /// The user picked images on the camera and chose to send them: import each one as the camera offers it.
    private func receiveSelection(_ camera: SerialCamera) async {
        appendLog("Receiving images selected on the camera")
        let activity = keepAwake()
        defer { ProcessInfo.processInfo.endActivity(activity) }
        importProgress = ImportProgress(index: 0, total: 0, filename: "", fraction: 0)
        var received = 0
        var failure: String?
        if let destinations = await prepareDestinations() {
            while !Task.isCancelled {
                do {
                    guard let info = try await camera.run({ try ($0 as! FujiCamera).nextSelectedImage() }) else { break }
                    importProgress = ImportProgress(index: received + 1, total: 0, filename: info.filename, fraction: 0)
                    let (imported, image) = try await importObject(FujiCamera.selectedImageHandle, filename: info.filename,
                                                                   camera: camera, destinations: destinations, thumbnail: true,
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
        Task.detached { camera.camera.disconnect() }
        importSummary = String(localized: "Received \(received) items from the camera") + (failure.map { String(localized: ". Stopped: \($0)") } ?? "")
        Notifier.post(String(localized: "Transfer finished"), importSummary ?? "")
    }

    /// A message when a destination's disk can't hold `needed` bytes (plus a margin), else nil.
    /// Downloads pass through the temporary folder, so its disk counts too.
    static func spaceShortage(needed: Int64, destinations: [Destination]) -> String? {
        let margin = needed / 20 + 50_000_000
        let places = destinations.compactMap(\.location).map { location -> URL in
            switch location {
            case .photos: FileManager.default.homeDirectoryForCurrentUser
            case .folder(let url): url
            }
        } + [FileManager.default.temporaryDirectory]
        for place in places {
            guard let free = try? place.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage, free < needed + margin else { continue }
            let need = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
            let have = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            return String(localized: "Not enough free space: the import needs \(need) but only \(have) is free on the disk of “\(place.lastPathComponent)”.")
        }
        return nil
    }

    func showLastImport() {
        switch lastImportLocation {
        case .photos?:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
        case .folder(let url)?:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case nil:
            break
        }
    }

    /// Keeps the Mac from sleeping while an import runs; the Wi-Fi connection would drop.
    private func keepAwake() -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                              reason: "Importing photos from the camera")
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

    /// A camera full of photos, none of them imported by Ferry: probably copied some other way before.
    var showBacklogNotice: Bool {
        phase == .connected && !isListing && items.count >= 30 && !items.contains(where: \.imported)
            && !backlogNoticeDismissed.contains(cameraName)
    }

    private var backlogNoticeDismissed = Set(UserDefaults.standard.stringArray(forKey: Prefs.backlogNoticeDismissed) ?? [])

    func dismissBacklogNotice() {
        backlogNoticeDismissed.insert(cameraName)
        UserDefaults.standard.set(Array(backlogNoticeDismissed), forKey: Prefs.backlogNoticeDismissed)
    }

    /// Records photos as imported, or not, without copying anything, so "Import New" leaves them out or offers
    /// them again.
    func markImported(_ ids: Set<String>, _ imported: Bool) {
        if imported { history.insert(contentsOf: ids) } else { history.remove(contentsOf: ids) }
        for i in items.indices where ids.contains(items[i].id) { items[i].imported = imported }
        if imported { selection.subtract(ids) }
    }

    func dismissResizeNotice(forever: Bool) {
        showResizeNotice = false
        if forever { UserDefaults.standard.set(true, forKey: Prefs.hideResizeNotice) }
    }

    /// Downloads `item` into a cache for Quick Look, once per session. Doesn't count as an import.
    func previewFile(for item: PhotoItem) async -> URL? {
        guard let camera, !item.info.isVideo else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Previews", isDirectory: true)
        let file = dir.appendingPathComponent(PathTemplate.sanitize(item.id) + "." + (item.info.filename as NSString).pathExtension)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let partial = dir.appendingPathComponent(UUID().uuidString)
        do {
            let handle = item.handle
            try await camera.run { try $0.download(handle, to: partial) }
            try FileManager.default.moveItem(at: partial, to: file)
            return file
        } catch {
            try? FileManager.default.removeItem(at: partial)
            appendLog("Preview of \(item.info.filename) failed: \(error.localizedDescription)")
            return nil
        }
    }

    func forgetHistory() {
        history.removeAll()
        for i in items.indices { items[i].imported = false }
    }

    // MARK: - Log

    func appendLog(_ line: String) {
        let now = Date()
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        log.append("[\(f.string(from: now))] \(line)")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        LogFile.append("[\(f.string(from: now))] \(line)")
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
        #if DEBUG
        print(log.last!)
        #endif
    }

    var logText: String { log.joined(separator: "\n") }
}
