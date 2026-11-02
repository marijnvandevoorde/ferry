#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// Minimal blocking TCP socket. Fuji's protocol is strictly request/response,
/// so a blocking socket driven from one serial queue is the simplest correct model.
final class TCPSocket {
    private var fd: Int32 = -1

    /// `interface` pins the connection to one network interface (e.g. "en0"), so the camera is reached
    /// over Wi-Fi even when a VPN claims the route to its address.
    init(host: String, port: UInt16, interface: String? = nil, connectTimeout: TimeInterval) throws {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = Sys.stream
        hints.ai_protocol = Int32(IPPROTO_TCP)
        var result: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, String(port), &hints, &result)
        guard rc == 0, let info = result else {
            throw FujiError.connectionFailed("Cannot resolve \(host): \(String(cString: gai_strerror(rc)))")
        }
        defer { freeaddrinfo(result) }

        fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { throw FujiError.connectionFailed("socket(): \(String(cString: strerror(errno)))") }

        var one: Int32 = 1
        Sys.configure(fd)
        setsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        if let interface {
            if !Sys.bind(fd, toInterface: interface) {
                close()
                throw FujiError.connectionFailed("cannot use network interface \(interface)")
            }
        }

        // Non-blocking connect so we can enforce a timeout, then switch back to blocking.
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let c = Sys.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if c != 0 && errno != EINPROGRESS {
            let msg = String(cString: strerror(errno))
            close()
            throw FujiError.connectionFailed("connect to \(host):\(port): \(msg)")
        }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let p = poll(&pfd, 1, Int32(connectTimeout * 1000))
        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
        if p <= 0 || soError != 0 {
            let msg = p == 0 ? "timed out" : String(cString: strerror(soError != 0 ? soError : errno))
            close()
            throw FujiError.connectionFailed("connect to \(host):\(port): \(msg)")
        }
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        readTimeout = 10
    }

    /// Wraps an accepted connection.
    init(fd: Int32) {
        self.fd = fd
        Sys.configure(fd)
    }

    deinit { close() }

    var readTimeout: TimeInterval = 10 {
        didSet {
            var tv = Sys.timeout(seconds: readTimeout)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }
    }

    func close() {
        if fd >= 0 { Sys.close(fd) }
        fd = -1
    }

    func write(_ data: Data) throws {
        guard fd >= 0 else { throw FujiError.disconnected }
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var sent = 0
            while sent < buf.count {
                let n = send(fd, buf.baseAddress! + sent, buf.count - sent, Sys.sendFlags)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw FujiError.io("send: \(String(cString: strerror(errno)))")
                }
                sent += n
            }
        }
    }

    /// Reads exactly `count` bytes or throws.
    func read(exactly count: Int) throws -> Data {
        guard fd >= 0 else { throw FujiError.disconnected }
        var data = Data(count: count)
        var got = 0
        try data.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
            while got < count {
                let n = recv(fd, buf.baseAddress! + got, count - got, 0)
                if n == 0 { throw FujiError.disconnected }
                if n < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK { throw FujiError.timeout }
                    throw FujiError.io("recv: \(String(cString: strerror(errno)))")
                }
                got += n
            }
        }
        return data
    }

    /// Reads one message of a text protocol (whatever arrives in one go, up to 4 KB).
    func readAvailable() throws -> String {
        guard fd >= 0 else { throw FujiError.disconnected }
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 { return String(decoding: buf[0..<n], as: UTF8.self) }
            if n == 0 { throw FujiError.disconnected }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { throw FujiError.timeout }
            throw FujiError.io("recv: \(String(cString: strerror(errno)))")
        }
    }

    /// Reads and discards whatever is available without blocking (used for the liveview socket).
    func drain() {
        guard fd >= 0 else { return }
        var buf = [UInt8](repeating: 0, count: 65536)
        while recv(fd, &buf, buf.count, Int32(MSG_DONTWAIT)) > 0 {}
    }
}
