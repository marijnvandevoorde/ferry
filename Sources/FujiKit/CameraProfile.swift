import Foundation

/// What a connected camera supports, derived from the version properties it reports at connect time.
/// Fuji never published a model list, so behaviour is keyed on these versions, like libfuji does.
public struct CameraProfile: Sendable, Equatable {
    public enum Generation: String, Sendable {
        /// No remote mode (X-A2, X30, X-E2 era): plain "view all images" access.
        case imageViewOnly = "image view only"
        /// Camera Remote with liveview and remote gallery (X-T20, X-T2, X-H1, …).
        case remote
        /// Remote version 0x20007 or later (X-S10, X-T4 and newer).
        case remoteNew = "remote (new)"
    }

    public var model: String
    public var getObjectVersion: UInt32?
    public var remoteImageViewVersion: UInt32?
    public var imageGetVersion: UInt32?
    public var remoteVersion: UInt32?

    public init(model: String, getObjectVersion: UInt32? = nil, remoteImageViewVersion: UInt32? = nil,
                imageGetVersion: UInt32? = nil, remoteVersion: UInt32? = nil) {
        self.model = model
        self.getObjectVersion = getObjectVersion
        self.remoteImageViewVersion = remoteImageViewVersion
        self.imageGetVersion = imageGetVersion
        // Cameras without remote mode answer with an empty value or zero.
        self.remoteVersion = remoteVersion == 0 ? nil : remoteVersion
    }

    public var hasRemoteMode: Bool { remoteVersion != nil }

    public var generation: Generation {
        guard let remoteVersion else { return .imageViewOnly }
        return remoteVersion >= 0x20007 ? .remoteNew : .remote
    }

    /// Newer cameras (remote image view version 5+, e.g. X-T5) number their photos oldest first.
    public var listsOldestFirst: Bool { (remoteImageViewVersion ?? 0) >= 5 }

    /// libfuji: GetThumb blocks forever on newer cameras unless GetObjectInfo was called first.
    public var thumbnailNeedsObjectInfo: Bool { (remoteVersion ?? 0) > 0x20006 }

    public var summary: String {
        func hex(_ v: UInt32?) -> String { v.map { String(format: "0x%X", $0) } ?? "none" }
        return "\(model): \(generation.rawValue) (getObject=\(hex(getObjectVersion)) remoteGetObject=\(hex(remoteImageViewVersion)) imageGet=\(hex(imageGetVersion)) remote=\(hex(remoteVersion)))"
    }
}
