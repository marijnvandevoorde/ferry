#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif
import Foundation

#if os(Windows)
typealias sa_family_t = ADDRESS_FAMILY
#endif

/// The socket calls FujiKit needs, with the differences between macOS, Linux and Windows kept in one place.
enum Sys {
    #if os(Windows)
    typealias Handle = SOCKET
    static let invalid: Handle = INVALID_SOCKET
    #else
    typealias Handle = Int32
    static let invalid: Handle = -1
    #endif

    static func isValid(_ h: Handle) -> Bool {
        h != invalid
    }

    // MARK: Creating and closing

    static func tcpSocket() -> Handle {
        startup()
        #if os(Windows)
        return WinSDK.socket(AF_INET, SOCK_STREAM, Int32(IPPROTO_TCP.rawValue))
        #elseif canImport(Darwin)
        return Darwin.socket(AF_INET, SOCK_STREAM, Int32(IPPROTO_TCP))
        #else
        return Glibc.socket(AF_INET, Int32(SOCK_STREAM.rawValue), Int32(IPPROTO_TCP))
        #endif
    }

    static func udpSocket() -> Handle {
        startup()
        #if os(Windows)
        return WinSDK.socket(AF_INET, SOCK_DGRAM, Int32(IPPROTO_UDP.rawValue))
        #elseif canImport(Darwin)
        return Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        #else
        return Glibc.socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        #endif
    }

    static func close(_ h: Handle) {
        #if os(Windows)
        closesocket(h)
        #elseif canImport(Darwin)
        _ = Darwin.close(h)
        #else
        _ = Glibc.close(h)
        #endif
    }

    #if os(Windows)
    private static let wsaStarted: Bool = {
        var data = WSADATA()
        return WSAStartup(0x0202, &data) == 0
    }()
    #endif

    static func startup() {
        #if os(Windows)
        _ = wsaStarted
        #endif
    }

    // MARK: Options

    private static func setOption(_ h: Handle, _ level: Int32, _ name: Int32, _ value: Int32) {
        var v = value
        #if os(Windows)
        _ = withUnsafePointer(to: &v) {
            $0.withMemoryRebound(to: CChar.self, capacity: 4) { setsockopt(h, level, name, $0, 4) }
        }
        #else
        setsockopt(h, level, name, &v, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    /// Options every TCP connection gets.
    static func configureStream(_ h: Handle) {
        #if canImport(Darwin)
        setOption(h, SOL_SOCKET, SO_NOSIGPIPE, 1)
        #endif
        #if os(Windows)
        setOption(h, Int32(IPPROTO_TCP.rawValue), TCP_NODELAY, 1)
        #else
        setOption(h, Int32(IPPROTO_TCP), TCP_NODELAY, 1)
        #endif
    }

    static func setReuseAddress(_ h: Handle, port: Bool = false) {
        setOption(h, SOL_SOCKET, SO_REUSEADDR, 1)
        #if !os(Windows)
        if port { setOption(h, SOL_SOCKET, SO_REUSEPORT, 1) }
        #endif
    }

    /// Pins the socket to one network interface, so a VPN can't take the route to the camera.
    static func bind(_ h: Handle, toInterface name: String) -> Bool {
        #if canImport(Darwin)
        var index = if_nametoindex(name)
        return index != 0 && setsockopt(h, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0
        #elseif os(Windows)
        // Not yet: IP_UNICAST_IF needs the adapter's index. Without it a VPN may claim the camera's route.
        _ = (h, name)
        return true
        #else
        return name.withCString { setsockopt(h, SOL_SOCKET, SO_BINDTODEVICE, $0, socklen_t(name.utf8.count + 1)) == 0 }
        #endif
    }

    static func setNonBlocking(_ h: Handle, _ on: Bool) {
        #if os(Windows)
        var mode: UInt32 = on ? 1 : 0
        // FIONBIO is a C macro Swift can't import.
        ioctlsocket(h, Int32(bitPattern: 0x8004_667E), &mode)
        #else
        let flags = fcntl(h, F_GETFL, 0)
        _ = fcntl(h, F_SETFL, on ? flags | O_NONBLOCK : flags & ~O_NONBLOCK)
        #endif
    }

    static func setReceiveTimeout(_ h: Handle, seconds: Double) {
        #if os(Windows)
        setOption(h, SOL_SOCKET, SO_RCVTIMEO, Int32(seconds * 1000))
        #else
        let whole = Int(seconds)
        var tv = timeval(tv_sec: whole, tv_usec: .init((seconds - Double(whole)) * 1_000_000))
        setsockopt(h, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        #endif
    }

    static func pendingError(_ h: Handle) -> Int32 {
        var error: Int32 = 0
        #if os(Windows)
        var len: Int32 = 4
        _ = withUnsafeMutablePointer(to: &error) {
            $0.withMemoryRebound(to: CChar.self, capacity: 4) { getsockopt(h, SOL_SOCKET, SO_ERROR, $0, &len) }
        }
        #else
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(h, SOL_SOCKET, SO_ERROR, &error, &len)
        #endif
        return error
    }

    // MARK: Addresses and connections

    static func ipv4(_ host: String, port: UInt16) -> sockaddr_in? {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return nil }
        return addr
    }

    static func anyIPv4(port: UInt16) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        return addr
    }

    private static func withSockaddr<T>(_ addr: sockaddr_in, _ body: (UnsafePointer<sockaddr>, Int32) -> T) -> T {
        var a = addr
        return withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, Int32(MemoryLayout<sockaddr_in>.size)) }
        }
    }

    /// Starts a non-blocking connect. Returns 0, or the error code if it failed right away.
    static func startConnect(_ h: Handle, to addr: sockaddr_in) -> Int32 {
        let rc = withSockaddr(addr) { ptr, len in
            #if os(Windows)
            WinSDK.connect(h, ptr, len)
            #elseif canImport(Darwin)
            Darwin.connect(h, ptr, socklen_t(len))
            #else
            Glibc.connect(h, ptr, socklen_t(len))
            #endif
        }
        guard rc != 0 else { return 0 }
        let error = lastError()
        #if os(Windows)
        return error == WSAEWOULDBLOCK ? 0 : error
        #else
        return error == EINPROGRESS ? 0 : error
        #endif
    }

    static func bind(_ h: Handle, to addr: sockaddr_in) -> Bool {
        withSockaddr(addr) { ptr, len in
            #if os(Windows)
            WinSDK.bind(h, ptr, len) == 0
            #elseif canImport(Darwin)
            Darwin.bind(h, ptr, socklen_t(len)) == 0
            #else
            Glibc.bind(h, ptr, socklen_t(len)) == 0
            #endif
        }
    }

    static func listen(_ h: Handle, backlog: Int32) -> Bool {
        #if os(Windows)
        WinSDK.listen(h, backlog) == 0
        #elseif canImport(Darwin)
        Darwin.listen(h, backlog) == 0
        #else
        Glibc.listen(h, backlog) == 0
        #endif
    }

    static func accept(_ h: Handle) -> Handle {
        #if os(Windows)
        WinSDK.accept(h, nil, nil)
        #elseif canImport(Darwin)
        Darwin.accept(h, nil, nil)
        #else
        Glibc.accept(h, nil, nil)
        #endif
    }

    // MARK: Waiting

    /// Waits until one of `handles` is readable (or, with `write`, writable). Returns which ones are ready,
    /// or an empty array on timeout.
    static func wait(_ handles: [Handle], write: Bool = false, timeout: Double) -> [Bool] {
        let events = Int16(write ? POLLOUT : POLLIN)
        #if os(Windows)
        var fds = handles.map { WSAPOLLFD(fd: $0, events: events, revents: 0) }
        let n = WSAPoll(&fds, UInt32(fds.count), Int32(timeout * 1000))
        #else
        var fds = handles.map { pollfd(fd: $0, events: events, revents: 0) }
        let n = poll(&fds, nfds_t(fds.count), Int32(timeout * 1000))
        #endif
        guard n > 0 else { return [] }
        return fds.map { $0.revents != 0 }
    }

    // MARK: Data

    static func send(_ h: Handle, _ ptr: UnsafeRawPointer, _ count: Int) -> Int {
        #if os(Windows)
        Int(WinSDK.send(h, ptr.assumingMemoryBound(to: CChar.self), Int32(count), 0))
        #elseif canImport(Darwin)
        Darwin.send(h, ptr, count, 0)
        #else
        Glibc.send(h, ptr, count, Int32(MSG_NOSIGNAL))
        #endif
    }

    static func receive(_ h: Handle, _ ptr: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if os(Windows)
        Int(WinSDK.recv(h, ptr.assumingMemoryBound(to: CChar.self), Int32(count), 0))
        #elseif canImport(Darwin)
        Darwin.recv(h, ptr, count, 0)
        #else
        Glibc.recv(h, ptr, count, 0)
        #endif
    }

    // MARK: Errors

    static func lastError() -> Int32 {
        #if os(Windows)
        WSAGetLastError()
        #else
        errno
        #endif
    }

    static func isInterrupted(_ code: Int32) -> Bool {
        #if os(Windows)
        code == WSAEINTR
        #else
        code == EINTR
        #endif
    }

    static func isTimeout(_ code: Int32) -> Bool {
        #if os(Windows)
        code == WSAETIMEDOUT || code == WSAEWOULDBLOCK
        #else
        code == EAGAIN || code == EWOULDBLOCK
        #endif
    }

    static func describe(_ code: Int32) -> String {
        #if os(Windows)
        "socket error \(code)"
        #else
        String(cString: strerror(code))
        #endif
    }
}
