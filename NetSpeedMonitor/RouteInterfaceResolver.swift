import Darwin
import Foundation

enum RouteInterfaceResolver {
    static func currentDefaultInterface() -> String? {
        interfaceName(forHost: "1.1.1.1", port: 53)
            ?? interfaceName(forHost: "2606:4700:4700::1111", port: 53)
    }

    static func interfaceName(forHost host: String, port: UInt16) -> String? {
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = port.bigEndian
            destination.sin_addr = ipv4
            return resolve(destination: &destination, family: AF_INET)
        }
        var ipv6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            var destination = sockaddr_in6()
            destination.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            destination.sin6_family = sa_family_t(AF_INET6)
            destination.sin6_port = port.bigEndian
            destination.sin6_addr = ipv6
            return resolve(destination: &destination, family: AF_INET6)
        }
        return nil
    }

    private static func resolve<T>(destination: inout T, family: Int32) -> String? {
        let descriptor = socket(family, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let connected = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<T>.size))
            }
        }
        guard connected == 0 else { return nil }
        var localAddress = sockaddr_storage()
        var localLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let readAddress = withUnsafeMutablePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &localLength)
            }
        }
        guard readAddress == 0 else { return nil }

        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr, Int32(address.pointee.sa_family) == family else { continue }
            if addressesEqual(local: localAddress, candidate: address, family: family) {
                return String(cString: interface.pointee.ifa_name)
            }
        }
        return nil
    }

    private static func addressesEqual(local: sockaddr_storage, candidate: UnsafePointer<sockaddr>, family: Int32) -> Bool {
        if family == AF_INET {
            let lhs = withUnsafePointer(to: local) { UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr }
            let rhs = UnsafeRawPointer(candidate).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            return lhs == rhs
        }
        let lhs = withUnsafePointer(to: local) { UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr }
        let rhs = UnsafeRawPointer(candidate).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
        return withUnsafeBytes(of: lhs) { left in withUnsafeBytes(of: rhs) { right in left.elementsEqual(right) } }
    }
}
