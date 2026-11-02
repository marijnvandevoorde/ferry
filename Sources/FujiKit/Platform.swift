#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The few socket details that differ between macOS and Linux.
enum Sys {
    #if canImport(Darwin)
    static let stream = SOCK_STREAM
    static let datagram = SOCK_DGRAM
    /// macOS sets SO_NOSIGPIPE on the socket instead.
    static let sendFlags: Int32 = 0
    #else
    static let stream = Int32(SOCK_STREAM.rawValue)
    static let datagram = Int32(SOCK_DGRAM.rawValue)
    static let sendFlags = Int32(MSG_NOSIGNAL)
    #endif

    static func close(_ fd: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(fd)
        #else
        _ = Glibc.close(fd)
        #endif
    }

    static func connect(_ fd: Int32, _ addr: UnsafePointer<sockaddr>, _ len: socklen_t) -> Int32 {
        #if canImport(Darwin)
        Darwin.connect(fd, addr, len)
        #else
        Glibc.connect(fd, addr, len)
        #endif
    }

    static func bind(_ fd: Int32, _ addr: UnsafePointer<sockaddr>, _ len: socklen_t) -> Int32 {
        #if canImport(Darwin)
        Darwin.bind(fd, addr, len)
        #else
        Glibc.bind(fd, addr, len)
        #endif
    }

    static func listen(_ fd: Int32, _ backlog: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.listen(fd, backlog)
        #else
        Glibc.listen(fd, backlog)
        #endif
    }

    /// Socket options every connection gets.
    static func configure(_ fd: Int32) {
        #if canImport(Darwin)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    /// Pins the socket to one network interface, so a VPN can't take the route to the camera.
    static func bind(_ fd: Int32, toInterface name: String) -> Bool {
        #if canImport(Darwin)
        var index = if_nametoindex(name)
        return index != 0 && setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0
        #else
        return name.withCString { setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, $0, socklen_t(name.utf8.count + 1)) == 0 }
        #endif
    }

    static func timeout(seconds: Double) -> timeval {
        let whole = Int(seconds)
        return timeval(tv_sec: whole, tv_usec: .init((seconds - Double(whole)) * 1_000_000))
    }

    static func sockaddrIPv4(port: UInt16, address: in_addr_t) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = address
        return addr
    }
}
