import FerryKit
import Foundation

/// Matches the apps' version; bumped with them on a release (docs/releasing.md).
let version = "0.2.2"

let usage = """
usage: ferryctl [options] <command>

commands:
  import <dir>         import photos not imported before into <dir>
  watch <dir>          wait for the camera, import new photos, repeat (with --autosave: over the home network)
  autosave register    wait for the camera's "PC AutoSave Setting" and register this computer
  autosave <dir>       wait for the camera to send photos over the home network and import them
  serve                drive the camera for a desktop UI over JSON lines on stdin/stdout (see Serve.swift)
  info                 connect and print the camera name and photo count
  list [n]             list the first n photos (default: all)
  download <dir> [n]   download the first n photos into <dir> as they are, ignoring import history
  thumbs <dir> [n]     save thumbnails of the first n photos into <dir>

options:
  --host IP            camera address (default: the Wi-Fi router, which is the camera when joined to its
                       network); for autosave, answer the camera at this address without waiting for it
  --folders TEMPLATE   subfolders for import (default "{yyyy}/{yyyy-MM-dd}", "" for none)
  --rename TEMPLATE    rename imported files, e.g. "{yyyy-MM-dd}_{original}"
                       tokens: {yyyy} {MM} {dd} {HH} {mm} {ss} {camera} {original}
  --all                import everything, not only photos that weren't imported before
  --skip-videos        leave out videos
  --bluetooth          the camera's Wi-Fi was started over Bluetooth (newer Fujifilm cameras: XApp gallery)
  --protocol NAME      fuji, ptpip (Canon, Nikon, …), olympus, ricoh, gopro or dlna (Sony, Panasonic); default: try each
  --immich URL         also upload imports to this Immich server (API key in $IMMICH_API_KEY)
  --immich-album NAME  add Immich uploads to this album
  --history FILE       import history file (default: \(ImportHistory.defaultURL.path))
  --quiet              no protocol log on stderr
  --trace FILE         save a diagnostics file: every step and exchange with the camera (no photo contents),
                       what went wrong and how far it got. A mock camera can replay it (scripts/mock-cameras/replay.py)
  --help, --version
"""

// Line-buffered, so `watch` output shows up promptly in logs (systemd, launchd).
setvbuf(stdout, nil, _IOLBF, 0)

var args = Array(CommandLine.arguments.dropFirst())

// Before anything else: an unknown command would otherwise go looking for a camera first.
if args.contains(where: { ["--help", "-h", "help"].contains($0) }) {
    print(usage)
    exit(0)
}
if args.contains(where: { ["--version", "version"].contains($0) }) {
    print("ferryctl \(version)")
    exit(0)
}
let commands: Set = ["import", "watch", "autosave", "serve", "info", "list", "download", "thumbs"]

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...i + 1) }
    return args[i + 1]
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

let host = option("--host")
let folders = option("--folders")
let rename = option("--rename")
let historyPath = option("--history")
let protocolName = option("--protocol")
let immichURL = option("--immich")
let immichAlbum = option("--immich-album")
let all = flag("--all")
let skipVideos = flag("--skip-videos")
let watchAutoSave = flag("--autosave")
let afterBluetoothHandoff = flag("--bluetooth")
let verbose = !flag("--quiet")
let traceFile = option("--trace")
guard let command = args.first, commands.contains(command) else {
    if let unknown = args.first { FileHandle.standardError.write(Data("ferryctl: unknown command \(unknown)\n".utf8)) }
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

func fail(_ message: String) -> Never {
    print("Error: \(message)")
    saveTrace()
    exit(1)
}

/// Writes the diagnostics file asked for with --trace, and prints its summary.
func saveTrace() {
    guard let traceFile else { return }
    do {
        try Trace.shared.export(to: URL(fileURLWithPath: traceFile))
        FileHandle.standardError.write(Data("\n\(Trace.shared.summary())\n\nDiagnostics saved to \(traceFile)\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("Could not save diagnostics to \(traceFile): \(error.localizedDescription)\n".utf8))
    }
}

#if os(macOS)
let clientName = Host.current().localizedName ?? "ferryctl"
#else
let clientName = ProcessInfo.processInfo.hostName
#endif

Trace.shared.app = "ferryctl"
Trace.shared.appVersion = version
Trace.shared.redact(clientName)
#if !os(Windows)
// `watch` and `autosave` run until interrupted: save the diagnostics file then.
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
if traceFile != nil {
    signal(SIGINT, SIG_IGN)
    interrupt.setEventHandler {
        saveTrace()
        exit(130)
    }
    interrupt.resume()
}
#endif

func argument(_ index: Int) -> String {
    guard args.count > index else { print(usage); exit(2) }
    return args[index]
}

func limit(_ index: Int) -> Int? {
    args.count > index ? Int(args[index]) : nil
}

func folderImport(_ path: String) -> FolderImport {
    FolderImport(root: URL(fileURLWithPath: path),
                 folderTemplate: folders.map(PathTemplate.init) ?? .defaultFolder,
                 fileTemplate: rename.map(PathTemplate.init))
}

let immich: ImmichUpload? = immichURL.map { url in
    guard let server = URL(string: url), let key = ProcessInfo.processInfo.environment["IMMICH_API_KEY"], !key.isEmpty else {
        fail("--immich needs a server URL and the API key in IMMICH_API_KEY")
    }
    return ImmichUpload(server: server, apiKey: key, albumName: immichAlbum, deviceID: clientName)
}

/// Runs async work from this synchronous tool.
@discardableResult
func blocking<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>!
    Task {
        do { result = .success(try await body()) } catch { result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}

let history = ImportHistory(url: historyPath.map { URL(fileURLWithPath: $0) } ?? ImportHistory.defaultURL)

/// Downloads `handle` next to its destination, then files it. Returns false if it was skipped.
func importObject(_ camera: WirelessCamera, handle: UInt32, into target: FolderImport, info known: ObjectInfo? = nil) throws -> Bool {
    let info = try known ?? camera.objectInfo(handle)
    if info.isFolder || (skipVideos && info.isVideo) { return false }
    if !all && history.contains(ImportHistory.key(camera: camera.cameraName, info: info)) { return false }
    try FileManager.default.createDirectory(at: target.root, withIntermediateDirectories: true)
    let tmp = target.root.appendingPathComponent(".ferryctl-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let downloaded = try camera.download(handle, to: tmp)
    let url = try target.store(tmp, info: downloaded, camera: camera.cameraName, move: true)
    let key = ImportHistory.key(camera: camera.cameraName, info: downloaded)
    if let immich {
        try blocking { try await immich.upload(url, info: downloaded, key: key) }
    }
    history.insert(key)
    print("\(downloaded.filename) → \(url.path)")
    return true
}

/// Imports everything new the connected camera offers. Returns the number of files imported.
@discardableResult
func importNew(_ camera: WirelessCamera, into target: FolderImport) throws -> Int {
    var count = 0
    if let fuji = camera as? FujiCamera, fuji.isSendingSelection {
        print("Receiving the images selected on the camera")
        while let info = try fuji.nextSelectedImage() {
            if try importObject(camera, handle: FujiCamera.selectedImageHandle, into: target, info: info) { count += 1 }
        }
    } else {
        for handle in camera.objectHandles where try importObject(camera, handle: handle, into: target) {
            count += 1
        }
    }
    print("Imported \(count) \(count == 1 ? "file" : "files") from \(camera.cameraName)")
    return count
}

let wifi = NetworkInfo.wifiInterface

/// Connects to the camera on its own Wi-Fi network: an explicit --host, or the Wi-Fi router.
/// Returns nil when there's no network to look on.
func connectDirect() throws -> WirelessCamera? {
    guard let cameraHost = host ?? wifi.flatMap(NetworkInfo.router(for:)) else { return nil }
    // Bind to Wi-Fi so a VPN can't swallow the connection; not for an explicit host like a local emulator.
    let interface = host == nil ? wifi : nil
    let approval = { print("Press OK on the camera to allow the connection…") }
    if let protocolName {
        guard let proto = CameraProtocol(rawValue: protocolName) else { fail("unknown protocol \(protocolName)") }
        let camera = proto.camera(host: cameraHost, interface: interface, clientName: clientName,
                                  afterBluetoothHandoff: afterBluetoothHandoff, log: logLine)
        try camera.connect(onWaitingForApproval: approval)
        return camera
    }
    return try CameraProtocol.connect(host: cameraHost, interface: interface, clientName: clientName,
                                      afterBluetoothHandoff: afterBluetoothHandoff, log: logLine,
                                      onWaitingForApproval: approval)
}

func waitForAutoSave(_ listener: AutoSaveListener, register: Bool) throws -> AutoSaveListener.Event {
    if let host {
        guard let event = try listener.respond(toCameraAt: host, register: register) else { fail("the camera didn't answer") }
        return event
    }
    try listener.start()
    while true {
        if let event = try listener.waitForCamera(timeout: 5) { return event }
    }
}

func autoSaveImport(_ cameraHost: String, into target: FolderImport) throws {
    let camera = FujiCamera(host: cameraHost, clientName: clientName, log: logLine)
    try camera.connect()
    defer { camera.disconnect() }
    try importNew(camera, into: target)
}

do {
    switch command {
    case "autosave":
        let register = argument(1) == "register"
        let listener = AutoSaveListener(clientName: clientName, log: logLine)
        if host == nil { print(register ? "Choose PC AutoSave Setting on the camera…" : "Waiting for the camera to start PC AutoSave…") }
        switch try waitForAutoSave(listener, register: register) {
        case .registered(let camera, let model):
            print("Registered with \(camera) (\(model)) as \(listener.clientName)")
        case .importRequest(let cameraHost, _):
            if register { fail("the camera asked to send photos instead of registering") }
            try autoSaveImport(cameraHost, into: folderImport(argument(1)))
        }

    case "serve":
        Server(host: host, clientName: clientName, history: history).run()

    case "watch" where watchAutoSave:
        let target = folderImport(argument(1))
        let listener = AutoSaveListener(clientName: clientName, log: logLine)
        try listener.start()
        print("Waiting for cameras on the home network (PC AutoSave)…")
        while true {
            do {
                switch try listener.waitForCamera(timeout: 5) {
                case .registered(let camera, let model)?: print("Registered with \(camera) (\(model))")
                case .importRequest(let cameraHost, _)?: try autoSaveImport(cameraHost, into: target)
                case nil: break
                }
            } catch {
                print("Error: \(error.localizedDescription)")
            }
        }

    case "watch":
        let target = folderImport(argument(1))
        print("Waiting for a camera on Wi-Fi…")
        // After importing, wait for the camera to go away before importing from it again.
        var importedFrom: String?
        while true {
            let router = host ?? wifi.flatMap(NetworkInfo.router(for:))
            if router != importedFrom {
                do {
                    guard let camera = try connectDirect() else { Thread.sleep(forTimeInterval: 5); continue }
                    defer { camera.disconnect() }
                    try importNew(camera, into: target)
                    importedFrom = router
                } catch FujiError.connectionFailed {
                    importedFrom = nil
                } catch {
                    print("Error: \(error.localizedDescription)")
                }
            } else if router == nil {
                importedFrom = nil
            }
            Thread.sleep(forTimeInterval: host != nil && importedFrom != nil ? 60 : 5)
            if host != nil && importedFrom != nil { importedFrom = nil }
        }

    default:
        guard let camera = try connectDirect() else { fail("not connected to a Wi-Fi network; join the camera's network or use --host") }
        defer { camera.disconnect() }
        print("Connected to \(camera.cameraName): \(camera.objectHandles.count) objects")

        switch command {
        case "info":
            print((camera as? FujiCamera)?.profile.summary ?? "\(camera.cameraName): standard PTP/IP")
        case "import":
            try importNew(camera, into: folderImport(argument(1)))
        case "list":
            for handle in camera.objectHandles.prefix(limit(1) ?? .max) {
                let info = try camera.objectInfo(handle)
                print("\(String(handle).padding(toLength: 6, withPad: " ", startingAt: 0)) \(info.filename.padding(toLength: 14, withPad: " ", startingAt: 0)) \(info.captureDate)  \(info.imageWidth)x\(info.imageHeight)")
            }
        case "download" where (camera as? FujiCamera)?.isSendingSelection == true:
            let fuji = camera as! FujiCamera
            let dir = URL(fileURLWithPath: argument(1))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            print("Receiving the images selected on the camera")
            while let info = try fuji.nextSelectedImage() {
                let url = dir.appendingPathComponent(info.filename)
                try? FileManager.default.removeItem(at: url)
                try fuji.download(FujiCamera.selectedImageHandle, to: url) { _, _ in }
                print("\(info.filename) (\(info.compressedSize) bytes)")
            }
        case "download", "thumbs":
            let dir = URL(fileURLWithPath: argument(1))
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
                    let info = try camera.download(handle, to: tmp) { _, _ in }
                    let url = dir.appendingPathComponent(info.filename)
                    try? FileManager.default.removeItem(at: url)
                    try FileManager.default.moveItem(at: tmp, to: url)
                    let secs = Date().timeIntervalSince(start)
                    let speed = (Double(info.compressedSize) / max(secs, 0.001) / 1e6 * 10).rounded() / 10
                    print("\(handle): \(info.filename) (\(info.compressedSize) bytes, \(speed) MB/s)")
                }
            }
        default:
            print(usage)
            exit(2)
        }
    }
    saveTrace()
} catch {
    if !(error is FujiError) { Trace.shared.failed(error, during: command) }
    fail(error.localizedDescription)
}
