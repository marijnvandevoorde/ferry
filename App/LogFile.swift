import Foundation

/// The connection log on disk, so a dropped connection can be looked into afterwards. Lives in Library/Logs inside
/// the app's container; starts over past 5 MB, keeping the previous file as Ferry.old.log.
@MainActor
enum LogFile {
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Ferry.log")
    private static var handle: FileHandle?

    static func append(_ line: String) {
        if handle == nil { handle = open() }
        guard let handle else { return }
        try? handle.write(contentsOf: Data((line + "\n").utf8))
        if let size = try? handle.offset(), size > 5_000_000 {
            try? handle.close()
            self.handle = nil
            let old = url.deletingLastPathComponent().appendingPathComponent("Ferry.old.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
    }

    private static func open() -> FileHandle? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return handle
    }
}
