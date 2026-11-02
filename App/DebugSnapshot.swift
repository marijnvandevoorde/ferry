#if DEBUG
import AppKit

/// Development aid: `FUJIIMPORT_SNAPSHOT=/path/prefix` saves PNGs of the main window every few seconds,
/// for checking the UI against the vcam emulator without screen-recording permissions.
enum DebugSnapshot {
    static func startIfRequested() {
        guard let prefix = ProcessInfo.processInfo.environment["FUJIIMPORT_SNAPSHOT"] else { return }
        var n = 0
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated {
                // The largest window, so the menu bar extra's tiny window isn't picked.
                guard let window = NSApp.windows.filter({ $0.isVisible && $0.title != "Connection Log" })
                        .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
                      let view = window.contentView?.superview, let layer = view.layer else { return }
                // Render the layer tree; cacheDisplay misses layer-backed scroll content.
                let scale = window.backingScaleFactor
                let size = view.bounds.size
                guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                ctx.scaleBy(x: scale, y: scale)
                layer.render(in: ctx)
                guard let image = ctx.makeImage() else { return }
                n += 1
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(n).png"))
            }
        }
    }
}
#endif
