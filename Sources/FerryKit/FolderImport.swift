import Foundation

/// Files a downloaded photo into a folder: subfolders from a template, optional renaming, never overwriting.
public struct FolderImport: Sendable {
    public var root: URL
    public var folderTemplate: PathTemplate
    /// Renames files when set; the extension is kept.
    public var fileTemplate: PathTemplate?

    public init(root: URL, folderTemplate: PathTemplate = .defaultFolder, fileTemplate: PathTemplate? = nil) {
        self.root = root
        self.folderTemplate = folderTemplate
        self.fileTemplate = fileTemplate
    }

    /// Where `info` would go, before making the name unique.
    public func destination(for info: ObjectInfo, camera: String) -> (folder: URL, name: String) {
        let date = info.date ?? Date()
        let original = (info.filename as NSString).deletingPathExtension
        var folder = root
        for component in folderTemplate.folderComponents(date: date, camera: camera, original: original) {
            folder.appendPathComponent(component, isDirectory: true)
        }
        var name = info.filename
        if let fileTemplate {
            let base = fileTemplate.render(date: date, camera: camera, original: original)
            let ext = (info.filename as NSString).pathExtension
            if !base.isEmpty { name = ext.isEmpty ? base : "\(base).\(ext)" }
        }
        return (folder, name)
    }

    /// Moves or copies `file` into place and returns where it went.
    @discardableResult
    public func store(_ file: URL, info: ObjectInfo, camera: String, move: Bool) throws -> URL {
        let fm = FileManager.default
        let (folder, name) = destination(for: info, camera: camera)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let unique = PathTemplate.uniqueName(name) { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        let target = folder.appendingPathComponent(unique)
        if move {
            try fm.moveItem(at: file, to: target)
        } else {
            try fm.copyItem(at: file, to: target)
        }
        if let date = info.date {
            try? fm.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: target.path)
        }
        return target
    }
}
