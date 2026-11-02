import FujiKit
import Foundation

let usage = """
usage: fujictl [--host IP] [--quiet] <command>

The camera address defaults to the Wi-Fi router (the camera, when joined to its network).

commands:
  info                 connect and print the camera name and photo count
  list [n]             list the first n photos (default: all)
  download <dir> [n]   download the first n photos (default: all) into <dir>
  thumbs <dir> [n]     save thumbnails of the first n photos into <dir>
  autosave register    wait for the camera's "PC AutoSave Setting" and register this computer
  autosave <dir>       wait for the camera to send photos over the home network (PC AutoSave)
                       and download them into <dir>; with --host, answer the camera at that address
"""

var args = Array(CommandLine.arguments.dropFirst())
var host: String?
var verbose = true
if let i = args.firstIndex(of: "--host"), i + 1 < args.count {
    host = args[i + 1]
    args.removeSubrange(i...i + 1)
}
if let i = args.firstIndex(of: "--quiet") {
    verbose = false
    args.remove(at: i)
}
guard let command = args.first else {
    print(usage)
    exit(2)
}

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

func logLine(_ msg: String) {
    if verbose { FileHandle.standardError.write("[\(stamp())] \(msg)\n".data(using: .utf8)!) }
}

#if os(macOS)
let clientName = Host.current().localizedName ?? "fujictl"
#else
let clientName = ProcessInfo.processInfo.hostName
#endif

if command == "autosave" {
    guard args.count > 1 else { print(usage); exit(2) }
    let register = args[1] == "register"
    let listener = AutoSaveListener(clientName: clientName, log: logLine)
    do {
        var event: AutoSaveListener.Event?
        if let host {
            event = try listener.respond(toCameraAt: host, register: register)
        } else {
            try listener.start()
            print(register ? "Choose PC AutoSave Setting on the camera…" : "Waiting for the camera to start PC AutoSave…")
            while event == nil { event = try listener.waitForCamera(timeout: 5) }
        }
        switch event {
        case .registered(let camera, let model)?:
            print("Registered with \(camera) (\(model)) as \(listener.clientName)")
        case .importRequest(let cameraHost, _)?:
            let dir = URL(fileURLWithPath: args[1])
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let camera = FujiCamera(host: cameraHost, clientName: clientName, log: logLine)
            try camera.connect()
            defer { camera.disconnect() }
            print("Connected to \(camera.cameraName): \(camera.objectCount) objects")
            for handle in camera.objectHandles {
                if try camera.objectInfo(handle).isFolder { continue }
                let tmp = dir.appendingPathComponent(".download-\(handle)")
                let info = try camera.download(handle, to: tmp)
                let url = dir.appendingPathComponent(info.filename)
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: tmp, to: url)
                print("\(info.filename) (\(info.compressedSize) bytes)")
            }
        case nil:
            print("No camera answered")
            exit(1)
        }
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

let wifi = NetworkInfo.wifiInterface
let cameraHost = host ?? wifi.flatMap(NetworkInfo.router(for:)) ?? "192.168.0.1"
// Bind to Wi-Fi so a VPN can't swallow the connection; not for an explicit host like a local emulator.
let camera = FujiCamera(host: cameraHost, interface: host == nil ? wifi : nil, clientName: clientName, log: logLine)

func limit(_ index: Int) -> Int? {
    args.count > index ? Int(args[index]) : nil
}

do {
    try camera.connect { print("Press OK on the camera to allow the connection…") }
    defer { camera.disconnect() }
    print("Connected to \(camera.cameraName): \(camera.objectCount) objects")

    switch command {
    case "info":
        break
    case "list":
        for handle in camera.objectHandles.prefix(limit(1) ?? .max) {
            let info = try camera.objectInfo(handle)
            print(String(format: "%5d  %-14@ %@  %dx%d", handle, info.filename, info.captureDate, info.imageWidth, info.imageHeight))
        }
    case "download" where camera.isSendingSelection:
        guard args.count > 1 else { print(usage); exit(2) }
        let dir = URL(fileURLWithPath: args[1])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print("Receiving the images selected on the camera")
        while let info = try camera.nextSelectedImage() {
            let url = dir.appendingPathComponent(info.filename)
            try? FileManager.default.removeItem(at: url)
            try camera.download(FujiCamera.selectedImageHandle, to: url)
            print("\(info.filename) (\(info.compressedSize) bytes)")
        }
    case "download", "thumbs":
        guard args.count > 1 else { print(usage); exit(2) }
        let dir = URL(fileURLWithPath: args[1])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for handle in camera.objectHandles.prefix(limit(2) ?? .max) {
            if command == "thumbs" {
                guard let jpeg = try camera.thumbnail(handle) else { print("\(handle): no thumbnail"); continue }
                let url = dir.appendingPathComponent("thumb_\(handle).jpg")
                try jpeg.write(to: url)
                print("\(handle): \(url.lastPathComponent) (\(jpeg.count) bytes)")
            } else {
                if try camera.objectInfo(handle).isFolder { continue }
                let tmp = dir.appendingPathComponent(".download-\(handle)")
                let start = Date()
                let info = try camera.download(handle, to: tmp)
                let url = dir.appendingPathComponent(info.filename)
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: tmp, to: url)
                let secs = Date().timeIntervalSince(start)
                print(String(format: "%d: %@ (%d bytes, %.1fs, %.1f MB/s)", handle, info.filename, info.compressedSize, secs, Double(info.compressedSize) / secs / 1e6))
            }
        }
    default:
        print(usage)
        exit(2)
    }
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
