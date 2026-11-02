import Foundation

/// Minimal blocking TCP socket. Fuji's protocol is strictly request/response,
/// so a blocking socket driven from one serial queue is the simplest correct model.
final class TCPSocket {
    private var fd: Sys.Handle = Sys.invalid

    /// `host` is an IPv4 address (cameras don't have names). `interface` pins the connection to one network
    /// interface (e.g. "en0"), so the camera is reached over Wi-Fi even when a VPN claims the route to its address.
    init(host: String, port: UInt16, interface: String? = nil, connectTimeout: TimeInterval) throws {
        guard let address = Sys.ipv4(host == "localhost" ? "127.0.0.1" : host, port: port) else {
            throw FujiError.connectionFailed("\(host) is not an IPv4 address")
        }
        fd = Sys.tcpSocket()
        guard Sys.isValid(fd) else { throw FujiError.connectionFailed("socket(): \(Sys.describe(Sys.lastError()))") }

        Sys.configureStream(fd)
        if let interface, !Sys.bind(fd, toInterface: interface) {
            close()
            throw FujiError.connectionFailed("cannot use network interface \(interface)")
        }

        // Non-blocking connect so we can enforce a timeout, then switch back to blocking.
        Sys.setNonBlocking(fd, true)
        let started = Sys.startConnect(fd, to: address)
        if started != 0 {
            close()
            throw FujiError.connectionFailed("connect to \(host):\(port): \(Sys.describe(started))")
        }
        let ready = Sys.wait([fd], write: true, timeout: connectTimeout)
        let error = ready.isEmpty ? 0 : Sys.pendingError(fd)
        if ready.isEmpty || error != 0 {
            close()
            throw FujiError.connectionFailed("connect to \(host):\(port): \(ready.isEmpty ? "timed out" : Sys.describe(error))")
        }
        Sys.setNonBlocking(fd, false)
        readTimeout = 10
    }

    /// Wraps an accepted connection.
    init(handle: Sys.Handle) {
        fd = handle
        Sys.configureStream(fd)
    }

    deinit { close() }

    var readTimeout: TimeInterval = 10 {
        didSet { Sys.setReceiveTimeout(fd, seconds: readTimeout) }
    }

    func close() {
        if Sys.isValid(fd) { Sys.close(fd) }
        fd = Sys.invalid
    }

    func write(_ data: Data) throws {
        guard Sys.isValid(fd) else { throw FujiError.disconnected }
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var sent = 0
            while sent < buf.count {
                let n = Sys.send(fd, buf.baseAddress! + sent, buf.count - sent)
                if n < 0 {
                    let error = Sys.lastError()
                    if Sys.isInterrupted(error) { continue }
                    throw FujiError.io("send: \(Sys.describe(error))")
                }
                sent += n
            }
        }
    }

    /// Reads exactly `count` bytes or throws.
    func read(exactly count: Int) throws -> Data {
        guard Sys.isValid(fd) else { throw FujiError.disconnected }
        var data = Data(count: count)
        var got = 0
        try data.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
            while got < count {
                let n = Sys.receive(fd, buf.baseAddress! + got, count - got)
                if n == 0 { throw FujiError.disconnected }
                if n < 0 {
                    let error = Sys.lastError()
                    if Sys.isInterrupted(error) { continue }
                    if Sys.isTimeout(error) { throw FujiError.timeout }
                    throw FujiError.io("recv: \(Sys.describe(error))")
                }
                got += n
            }
        }
        return data
    }

    /// Reads one message of a text protocol (whatever arrives in one go, up to 4 KB).
    func readAvailable() throws -> String {
        guard Sys.isValid(fd) else { throw FujiError.disconnected }
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buf.withUnsafeMutableBytes { Sys.receive(fd, $0.baseAddress!, $0.count) }
            if n > 0 { return String(decoding: buf[0..<n], as: UTF8.self) }
            if n == 0 { throw FujiError.disconnected }
            let error = Sys.lastError()
            if Sys.isInterrupted(error) { continue }
            if Sys.isTimeout(error) { throw FujiError.timeout }
            throw FujiError.io("recv: \(Sys.describe(error))")
        }
    }

    /// Reads and discards whatever is available without blocking (used for the liveview socket).
    func drain() {
        guard Sys.isValid(fd) else { return }
        var buf = [UInt8](repeating: 0, count: 65536)
        while !Sys.wait([fd], timeout: 0).isEmpty {
            let n = buf.withUnsafeMutableBytes { Sys.receive(fd, $0.baseAddress!, $0.count) }
            if n <= 0 { break }
        }
    }
}
