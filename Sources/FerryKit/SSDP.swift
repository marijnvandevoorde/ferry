import Foundation

/// UPnP discovery: multicasts an M-SEARCH and collects the LOCATION (device description URL) of each answer.
enum SSDP {
    static func search(target: String, timeout: TimeInterval) -> [String] {
        let fd = Sys.udpSocket()
        guard Sys.isValid(fd) else { return [] }
        defer { Sys.close(fd) }
        let message = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: \(target)\r\n\r\n"
        guard let group = Sys.ipv4("239.255.255.250", port: 1900), Sys.send(fd, Data(message.utf8), to: group) else { return [] }

        var locations: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 2048)
        while case let remaining = deadline.timeIntervalSinceNow, remaining > 0, !Sys.wait([fd], timeout: remaining).isEmpty {
            let n = buffer.withUnsafeMutableBytes { Sys.receive(fd, $0.baseAddress!, $0.count) }
            guard n > 0 else { break }
            for line in String(decoding: buffer[0..<n], as: UTF8.self).components(separatedBy: "\r\n")
            where line.lowercased().hasPrefix("location:") {
                let location = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                if !locations.contains(location) { locations.append(location) }
            }
        }
        return locations
    }
}
