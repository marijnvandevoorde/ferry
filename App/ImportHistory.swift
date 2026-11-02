import FujiKit
import Foundation

/// Remembers which photos were already imported, so "Import New" skips them on the next connection.
final class ImportHistory {
    private var keys: Set<String>
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FujiImport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("imported.json")
        let data = (try? Data(contentsOf: url)) ?? Data()
        keys = (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    /// File numbers wrap around on the camera, so the capture date is part of the key.
    static func key(camera: String, info: ObjectInfo) -> String {
        "\(camera)/\(info.filename)/\(info.captureDate)"
    }

    func contains(_ key: String) -> Bool { keys.contains(key) }

    func insert(_ key: String) {
        keys.insert(key)
        save()
    }

    func removeAll() {
        keys.removeAll()
        save()
    }

    private func save() {
        try? JSONEncoder().encode(keys).write(to: url, options: .atomic)
    }
}
