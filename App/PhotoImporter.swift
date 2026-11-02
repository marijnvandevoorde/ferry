import Foundation
import Photos

/// Adds downloaded files to the Photos library, optionally into an album.
enum PhotoImporter {
    enum Access {
        case full, addOnly, denied
    }

    static func requestAccess(needsAlbum: Bool) async -> Access {
        if needsAlbum {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if status == .authorized || status == .limited { return .full }
        }
        let addOnly = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return addOnly == .authorized ? .addOnly : .denied
    }

    static func album(named title: String) async throws -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        if let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject {
            return existing
        }
        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            identifier = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                .placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let identifier else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    /// Imports `file` (moved into the library) and adds it to `album` if given.
    static func importFile(_ file: URL, originalFilename: String, isVideo: Bool, album: PHAssetCollection?) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            options.originalFilename = originalFilename
            request.addResource(with: isVideo ? .video : .photo, fileURL: file, options: options)
            if let album, let placeholder = request.placeholderForCreatedAsset {
                PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
            }
        }
    }
}
