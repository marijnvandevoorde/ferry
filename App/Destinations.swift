import AppKit
import FujiKit
import Photos

/// Somewhere imported photos end up.
@MainActor
protocol Destination: AnyObject {
    var displayName: String { get }
    /// Where imported files can be seen afterwards; nil for remote destinations.
    var location: ImportLocation? { get }
    /// Checks access before an import; throws a user-facing error when the destination can't be used.
    func prepare() async throws
    /// Stores `file`. With `move`, the destination may take the file instead of copying it.
    func store(_ file: URL, info: ObjectInfo, camera: String, move: Bool) async throws
}

struct DestinationError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum DestinationKind: String, CaseIterable, Identifiable {
    case photos, folder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .photos: String(localized: "Apple Photos")
        case .folder: String(localized: "A folder")
        }
    }
}

/// The destinations configured in Settings: the backup folder (if any) first, the main destination last,
/// so the main destination can take the downloaded file.
@MainActor
func configuredDestinations() -> [Destination] {
    let defaults = UserDefaults.standard
    var result: [Destination] = []
    if defaults.bool(forKey: Prefs.immichEnabled), let server = URL(string: defaults.string(forKey: Prefs.immichServer) ?? "") {
        result.append(ImmichDestination(upload: ImmichUpload(server: server, apiKey: ImmichKey.load() ?? "",
                                                             albumName: defaults.string(forKey: Prefs.immichAlbum),
                                                             deviceID: Host.current().localizedName ?? "Mac")))
    }
    if defaults.bool(forKey: Prefs.backupEnabled) {
        result.append(FolderDestination(bookmarkKey: Prefs.backupBookmark, folderTemplate: PathTemplate.defaultFolder,
                                        fileTemplate: nil, role: String(localized: "backup folder")))
    }
    switch DestinationKind(rawValue: defaults.string(forKey: Prefs.destination) ?? "") ?? .photos {
    case .photos:
        let useAlbum = defaults.bool(forKey: Prefs.useAlbum)
        let name = defaults.string(forKey: Prefs.albumName) ?? ""
        result.append(PhotosDestination(albumName: useAlbum ? (name.isEmpty ? "Fujifilm" : name) : nil))
    case .folder:
        let folder = defaults.string(forKey: Prefs.folderTemplate) ?? ""
        let rename = defaults.bool(forKey: Prefs.renameFiles)
        let file = defaults.string(forKey: Prefs.fileTemplate) ?? ""
        result.append(FolderDestination(bookmarkKey: Prefs.folderBookmark, folderTemplate: PathTemplate(folder),
                                        fileTemplate: rename && !file.isEmpty ? PathTemplate(file) : nil,
                                        role: String(localized: "import folder")))
    }
    return result
}

// MARK: - Apple Photos

final class PhotosDestination: Destination {
    /// May contain date tokens, e.g. "Fujifilm {yyyy}-{MM}", for an album per month.
    let albumName: String?
    private var canUseAlbums = false
    private var albums: [String: PHAssetCollection] = [:]

    init(albumName: String?) {
        self.albumName = albumName
    }

    var displayName: String { "Photos" }
    var location: ImportLocation? { .photos }

    func prepare() async throws {
        let access = await PhotoImporter.requestAccess(needsAlbum: albumName != nil)
        guard access != .denied else {
            throw DestinationError(String(localized: "Fuji Import needs access to Photos. Allow it in System Settings → Privacy & Security → Photos."))
        }
        canUseAlbums = albumName != nil && access == .full
    }

    func store(_ file: URL, info: ObjectInfo, camera: String, move: Bool) async throws {
        var source = file
        if !move {
            // Photos always takes the file it is given.
            source = file.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + "-" + info.filename)
            try FileManager.default.copyItem(at: file, to: source)
        }
        var album: PHAssetCollection?
        if canUseAlbums, let albumName {
            let name = PathTemplate(albumName).render(date: info.date ?? Date(), camera: camera,
                                                      original: (info.filename as NSString).deletingPathExtension)
            if albums[name] == nil { albums[name] = try? await PhotoImporter.album(named: name) }
            album = albums[name]
        }
        try await PhotoImporter.importFile(source, originalFilename: info.filename, isVideo: info.isVideo, album: album)
    }
}

// MARK: - Immich

/// Uploads a copy to a self-hosted Immich server, next to the main destination.
final class ImmichDestination: Destination {
    let upload: ImmichUpload

    init(upload: ImmichUpload) {
        self.upload = upload
    }

    var displayName: String { "Immich" }
    var location: ImportLocation? { nil }

    func prepare() async throws {
        guard !upload.apiKey.isEmpty else { throw DestinationError(String(localized: "Enter your Immich API key in Settings.")) }
        try await upload.check()
    }

    func store(_ file: URL, info: ObjectInfo, camera: String, move: Bool) async throws {
        try await upload.upload(file, info: info, key: "\(camera)/\(info.filename)/\(info.captureDate)")
    }
}

/// The Immich API key, kept in the Keychain rather than in preferences.
enum ImmichKey {
    private static let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "Fuji Import Immich API key",
        kSecAttrAccount: "immich",
    ]

    static func load() -> String? {
        var q = query
        q[kSecReturnData] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        var q = query
        q[kSecValueData] = Data(key.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}

// MARK: - Folder

/// A folder chosen by the user (remembered as a security-scoped bookmark), with date-based subfolders.
/// Also the hand-off for Lightroom Classic Auto Import, Capture One hot folders and similar.
final class FolderDestination: Destination {
    let bookmarkKey: String
    let folderTemplate: PathTemplate
    let fileTemplate: PathTemplate?
    let role: String
    private var root: URL?

    init(bookmarkKey: String, folderTemplate: PathTemplate, fileTemplate: PathTemplate?, role: String) {
        self.bookmarkKey = bookmarkKey
        self.folderTemplate = folderTemplate
        self.fileTemplate = fileTemplate
        self.role = role
    }

    deinit {
        root?.stopAccessingSecurityScopedResource()
    }

    var displayName: String { root?.lastPathComponent ?? FolderBookmark.url(for: bookmarkKey)?.lastPathComponent ?? "folder" }
    /// The last file stored, to select it in Finder; the folder before that.
    private var lastStored: URL?
    var location: ImportLocation? { (lastStored ?? root).map { .folder($0) } }

    func prepare() async throws {
        guard root == nil else { return }
        guard let url = FolderBookmark.url(for: bookmarkKey) else {
            throw DestinationError(String(localized: "Choose the \(role) in Settings."))
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw DestinationError(String(localized: "Fuji Import can't access the \(role) “\(url.lastPathComponent)”. Choose it again in Settings."))
        }
        root = url
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw DestinationError(String(localized: "The \(role) “\(url.lastPathComponent)” isn't available. Is the drive connected?"))
        }
    }

    func store(_ file: URL, info: ObjectInfo, camera: String, move: Bool) async throws {
        guard let root else { throw DestinationError(String(localized: "The \(role) isn't ready.")) }
        let folder = FolderImport(root: root, folderTemplate: folderTemplate, fileTemplate: fileTemplate)
        lastStored = try await Task.detached { try folder.store(file, info: info, camera: camera, move: move) }.value
    }
}

/// Folders the user picked, stored as app-scoped security bookmarks so they stay accessible in the sandbox.
enum FolderBookmark {
    static func url(for key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale { save(url, for: key) }
        return url
    }

    static func save(_ url: URL, for key: String) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Shows an open panel for choosing a folder and remembers the choice.
    @MainActor
    static func choose(for key: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        save(url, for: key)
        return url
    }
}
