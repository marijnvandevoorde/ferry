import Foundation

/// Remembers which photos were already imported, so "Import New" skips them on the next connection.
public final class ImportHistory: @unchecked Sendable {
    private var keys: Set<String>
    private let url: URL
    private let lock = NSLock()

    /// `url` defaults to `imported.json` in the app's data folder: Application Support on macOS
    /// (inside the sandbox container for the app), `$XDG_DATA_HOME/fuji-import` elsewhere.
    public init(url: URL = ImportHistory.defaultURL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = (try? Data(contentsOf: url)) ?? Data()
        keys = (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    public static var defaultURL: URL {
        #if os(macOS)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FujiImport", isDirectory: true)
        #else
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
        let dir = base.appendingPathComponent("fuji-import", isDirectory: true)
        #endif
        return dir.appendingPathComponent("imported.json")
    }

    /// File numbers wrap around on the camera, so the capture date is part of the key.
    public static func key(camera: String, info: ObjectInfo) -> String {
        "\(camera)/\(info.filename)/\(info.captureDate)"
    }

    public func contains(_ key: String) -> Bool {
        lock.withLock { keys.contains(key) }
    }

    public func insert(_ key: String) {
        lock.withLock { keys.insert(key) }
        save()
    }

    public func removeAll() {
        lock.withLock { keys.removeAll() }
        save()
    }

    private func save() {
        let snapshot = lock.withLock { keys }
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
