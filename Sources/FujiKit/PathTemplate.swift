import Foundation

/// Builds folder and file names from templates such as `{yyyy}/{yyyy-MM-dd}` or `{yyyy-MM-dd}_{original}`.
///
/// Tokens: `{yyyy}`, `{MM}`, `{dd}`, `{yyyy-MM-dd}`, `{HH}`, `{mm}`, `{ss}`, `{camera}`, `{original}`
/// (the camera's filename without extension). Unknown tokens are left as they are.
public struct PathTemplate: Sendable, Equatable {
    public var template: String

    public init(_ template: String) {
        self.template = template
    }

    public static let defaultFolder = PathTemplate("{yyyy}/{yyyy-MM-dd}")

    public func render(date: Date, camera: String, original: String, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ v: Int?, _ width: Int = 2) -> String {
            let s = String(v ?? 0)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        let values: [String: String] = [
            "yyyy-MM-dd": "\(pad(c.year, 4))-\(pad(c.month))-\(pad(c.day))",
            "yyyy": pad(c.year, 4),
            "MM": pad(c.month),
            "dd": pad(c.day),
            "HH": pad(c.hour),
            "mm": pad(c.minute),
            "ss": pad(c.second),
            "camera": camera,
            "original": original,
        ]
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result += rest[..<open]
            let token = String(rest[rest.index(after: open)..<close])
            result += values[token].map(Self.sanitize) ?? "{\(token)}"
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }

    /// Folder components rendered from the template, with empty components dropped.
    public func folderComponents(date: Date, camera: String, original: String) -> [String] {
        render(date: date, camera: camera, original: original)
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Token values must not add path separators or other characters that are awkward in filenames.
    static func sanitize(_ value: String) -> String {
        String(value.map { "/\\:".contains($0) ? "-" : $0 })
    }

    /// `name.ext`, or `name-2.ext`, `name-3.ext`, … for the first name that `exists` says is free.
    public static func uniqueName(_ filename: String, exists: (String) -> Bool) -> String {
        guard exists(filename) else { return filename }
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
            if !exists(candidate) { return candidate }
            n += 1
        }
    }
}
