import Foundation

@main
struct RouteInterfaceResolverTests {
    static func main() {
        precondition(RouteInterfaceResolver.interfaceName(forHost: "not-an-address", port: 53) == nil)
        precondition(RouteInterfaceResolver.interfaceName(forHost: "127.0.0.1", port: 53) == "lo0")
        let ipv6Loopback = RouteInterfaceResolver.interfaceName(forHost: "::1", port: 53)
        precondition(ipv6Loopback == nil || ipv6Loopback == "lo0")
        _ = RouteInterfaceResolver.currentDefaultInterface()
        print("Route resolver tests passed")
    }
}
