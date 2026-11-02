import Foundation
#if canImport(SystemConfiguration)
import SystemConfiguration
#endif

/// Finds the Wi-Fi interface and its router. When joined to a camera's network, the router is the camera.
public enum NetworkInfo {
    #if canImport(SystemConfiguration)
    /// BSD name of the Wi-Fi interface, e.g. "en0".
    public static var wifiInterface: String? {
        let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let wifi = all.first { SCNetworkInterfaceGetInterfaceType($0) == kSCNetworkInterfaceTypeIEEE80211 }
        return wifi.flatMap { SCNetworkInterfaceGetBSDName($0) as String? }
    }

    /// IPv4 router of `interface`, regardless of which interface (e.g. a VPN) is the primary route.
    public static func router(for interface: String) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "FujiKit" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString) as? [String]
        else { return nil }
        for key in keys {
            guard let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  dict["InterfaceName"] as? String == interface else { continue }
            return dict["Router"] as? String
        }
        return nil
    }
    #else
    /// Name of the first wireless interface, e.g. "wlan0".
    public static var wifiInterface: String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/sys/class/net")) ?? []
        return names.sorted().first { FileManager.default.fileExists(atPath: "/sys/class/net/\($0)/wireless") }
    }

    /// Default gateway of `interface`, from the kernel routing table.
    public static func router(for interface: String) -> String? {
        guard let table = try? String(contentsOfFile: "/proc/net/route", encoding: .utf8) else { return nil }
        return gateway(in: table, interface: interface)
    }
    #endif

    /// Parses `/proc/net/route`: the default route's gateway is little-endian hex.
    static func gateway(in table: String, interface: String) -> String? {
        for line in table.split(separator: "\n").dropFirst() {
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count > 2, f[0] == interface, f[1] == "00000000", let g = UInt32(f[2], radix: 16), g != 0 else { continue }
            return [g & 0xFF, (g >> 8) & 0xFF, (g >> 16) & 0xFF, g >> 24].map(String.init).joined(separator: ".")
        }
        return nil
    }
}
