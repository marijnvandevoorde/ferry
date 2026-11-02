import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Uploads photos to a self-hosted Immich server (immich.app) with an API key, optionally into an album.
public struct ImmichUpload: Sendable {
    public var server: URL
    public var apiKey: String
    public var albumName: String?
    /// Identifies this computer to Immich, which uses it with the file key to recognize duplicates.
    public var deviceID: String

    public init(server: URL, apiKey: String, albumName: String? = nil, deviceID: String = "fuji-import") {
        self.server = server
        self.apiKey = apiKey
        self.albumName = albumName
        self.deviceID = deviceID
    }

    public struct Failure: LocalizedError {
        public var errorDescription: String?
    }

    /// Uploads `file`; returns the Immich asset ID. Duplicates Immich already has count as success.
    @discardableResult
    public func upload(_ file: URL, info: ObjectInfo, key: String) async throws -> String {
        let boundary = "fuji-import-\(UUID().uuidString)"
        let date = ISO8601DateFormatter().string(from: info.date ?? Date())
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("immich-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: body) }
        try writeMultipart(to: body, boundary: boundary, file: file, filename: info.filename, fields: [
            "deviceAssetId": key,
            "deviceId": deviceID,
            "fileCreatedAt": date,
            "fileModifiedAt": date,
        ])

        var request = URLRequest(url: server.appendingPathComponent("api/assets"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, status) = try await send(request, bodyFile: body)
        guard status == 200 || status == 201,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw Failure(errorDescription: "Immich refused \(info.filename) (HTTP \(status)): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        if let albumName, !albumName.isEmpty {
            try await addToAlbum(named: albumName, assetID: id)
        }
        return id
    }

    /// Checks the server address and API key.
    public func check() async throws {
        let (data, status) = try await send(URLRequest(url: server.appendingPathComponent("api/users/me")))
        guard status == 200 else {
            throw Failure(errorDescription: "Immich at \(server.absoluteString) answered HTTP \(status): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
    }

    private func addToAlbum(named name: String, assetID: String) async throws {
        let (listData, _) = try await send(URLRequest(url: server.appendingPathComponent("api/albums")))
        let albums = (try? JSONSerialization.jsonObject(with: listData) as? [[String: Any]]) ?? []
        var albumID = albums.first { $0["albumName"] as? String == name }?["id"] as? String
        if albumID == nil {
            var create = URLRequest(url: server.appendingPathComponent("api/albums"))
            create.httpMethod = "POST"
            create.setValue("application/json", forHTTPHeaderField: "Content-Type")
            create.httpBody = try JSONSerialization.data(withJSONObject: ["albumName": name])
            let (data, _) = try await send(create)
            albumID = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
        }
        guard let albumID else { throw Failure(errorDescription: "Couldn't create the Immich album \(name)") }
        var add = URLRequest(url: server.appendingPathComponent("api/albums/\(albumID)/assets"))
        add.httpMethod = "PUT"
        add.setValue("application/json", forHTTPHeaderField: "Content-Type")
        add.httpBody = try JSONSerialization.data(withJSONObject: ["ids": [assetID]])
        _ = try await send(add)
    }

    private func send(_ request: URLRequest, bodyFile: URL? = nil) async throws -> (Data, Int) {
        var request = request
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300
        let (data, response): (Data, URLResponse)
        if let bodyFile {
            (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyFile)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func writeMultipart(to url: URL, boundary: String, file: URL, filename: String, fields: [String: String]) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            try out.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        try out.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"assetData\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
        }
        try out.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }
}
