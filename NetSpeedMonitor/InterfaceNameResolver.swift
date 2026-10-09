import Foundation
import SystemConfiguration

enum InterfaceNameResolver {
    private static let cacheLock = NSLock()
    private static var cachedDisplayNames: [String: String] = [:]

    static func displayName(forBSDName name: String) -> String {
        let fallbackName = fallback(name)
        if fallbackName != name {
            return fallbackName
        }

        cacheLock.lock()
        if let cached = cachedDisplayNames[name] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let resolved = resolveDisplayName(forBSDName: name)
        cacheLock.lock()
        cachedDisplayNames[name] = resolved
        cacheLock.unlock()
        return resolved
    }

    private static func resolveDisplayName(forBSDName name: String) -> String {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return name }
        for interface in interfaces where SCNetworkInterfaceGetBSDName(interface) as String? == name {
            if let localized = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?, !localized.isEmpty { return "\(localized) (\(name))" }
            if let type = SCNetworkInterfaceGetInterfaceType(interface) as String?, !type.isEmpty { return "\(type) (\(name))" }
        }
        return name
    }

    static func fallback(_ name: String) -> String {
        if name == "lo0" { return "Loopback (lo0)" }
        if name.hasPrefix("utun") { return "VPN Tunnel (\(name))" }
        if name.hasPrefix("awdl") { return "Apple Wireless Direct Link (\(name))" }
        if name.hasPrefix("bridge") { return "Network Bridge (\(name))" }
        return name
    }
}
