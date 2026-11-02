import Foundation
import SystemConfiguration

/// Finds the Wi-Fi interface and its router. When joined to a camera's network, the router is the camera.
public enum NetworkInfo {
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
}
