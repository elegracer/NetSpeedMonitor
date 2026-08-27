import Foundation

@main
struct InterfaceNameResolverTests {
    static func main() {
        precondition(InterfaceNameResolver.fallback("utun9") == "VPN Tunnel (utun9)")
        precondition(InterfaceNameResolver.fallback("bridge0") == "Network Bridge (bridge0)")
        precondition(!InterfaceNameResolver.displayName(forBSDName: "en0").isEmpty)
        print("Interface name resolver tests passed")
    }
}
