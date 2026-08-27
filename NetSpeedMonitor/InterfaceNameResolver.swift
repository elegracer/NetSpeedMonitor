import Foundation
import SystemConfiguration

enum InterfaceNameResolver {
    static func displayName(forBSDName name: String) -> String {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return fallback(name) }
        for interface in interfaces where SCNetworkInterfaceGetBSDName(interface) as String? == name {
            if let localized = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?, !localized.isEmpty { return "\(localized) (\(name))" }
            if let type = SCNetworkInterfaceGetInterfaceType(interface) as String?, !type.isEmpty { return "\(type) (\(name))" }
        }
        return fallback(name)
    }

    static func fallback(_ name: String) -> String {
        if name == "lo0" { return "Loopback (lo0)" }
        if name.hasPrefix("utun") { return "VPN Tunnel (\(name))" }
        if name.hasPrefix("awdl") { return "Apple Wireless Direct Link (\(name))" }
        if name.hasPrefix("bridge") { return "Network Bridge (\(name))" }
        return name
    }
}
