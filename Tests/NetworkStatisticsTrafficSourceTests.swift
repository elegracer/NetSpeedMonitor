import Darwin
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func routeDataIPv4(address: String) -> Data {
    var route = sockaddr_in()
    route.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    route.sin_family = sa_family_t(AF_INET)
    precondition(inet_pton(AF_INET, address, &route.sin_addr) == 1)
    return Data(bytes: &route, count: MemoryLayout<sockaddr_in>.size)
}

func routeDataIPv6(address: String) -> Data {
    var route = sockaddr_in6()
    route.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    route.sin6_family = sa_family_t(AF_INET6)
    precondition(inet_pton(AF_INET6, address, &route.sin6_addr) == 1)
    return Data(bytes: &route, count: MemoryLayout<sockaddr_in6>.size)
}

@main
struct NetworkStatisticsTrafficSourceTests {
    static func main() {
        require(NetworkStatisticsRouteParser.isIPRoute(routeDataIPv4(address: "0.0.0.0")), "IPv4 default route")
        require(NetworkStatisticsRouteParser.isIPRoute(routeDataIPv4(address: "64.0.0.0")), "IPv4 split route")
        require(NetworkStatisticsRouteParser.isIPRoute(routeDataIPv4(address: "1.1.1.1")), "IPv4 host route")
        require(NetworkStatisticsRouteParser.isIPRoute(routeDataIPv6(address: "::")), "IPv6 default route")
        require(NetworkStatisticsRouteParser.isIPRoute(routeDataIPv6(address: "2606:4700:4700::1111")), "IPv6 host route")
        require(!NetworkStatisticsRouteParser.isIPRoute(Data()), "empty route data")
        require(!NetworkStatisticsRouteParser.isIPRoute(Data([2, UInt8(AF_UNIX)])), "non-IP route")
        require(NetworkStatisticsRouteParser.shouldInclude(flags: UInt32(RTF_HOST)), "configured host route")
        require(
            !NetworkStatisticsRouteParser.shouldInclude(flags: UInt32(RTF_HOST | RTF_WASCLONED)),
            "dynamic cloned route"
        )
        require(
            !NetworkStatisticsRouteParser.shouldRemoveSource(
                destination: routeDataIPv4(address: "0.0.0.0"),
                flags: UInt32(RTF_GATEWAY)
            ),
            "configured IP route remains subscribed"
        )
        require(
            NetworkStatisticsRouteParser.shouldRemoveSource(
                destination: Data([2, UInt8(AF_UNIX)]),
                flags: nil
            ),
            "non-IP route is removed"
        )
        require(
            NetworkStatisticsRouteParser.shouldRemoveSource(
                destination: routeDataIPv4(address: "1.1.1.1"),
                flags: UInt32(RTF_HOST | RTF_WASCLONED)
            ),
            "dynamic cloned route is removed"
        )
        require(
            !NetworkStatisticsRouteParser.shouldRemoveSource(destination: nil, flags: nil),
            "incomplete description is retained"
        )

        var calculator = NetworkStatisticsRateCalculator()
        let first = calculator.update(samples: [
            .init(sourceID: 1, interfaceName: "en0", receivedBytes: 10_000, sentBytes: 5_000),
            .init(sourceID: 2, interfaceName: "en0", receivedBytes: 2_000, sentBytes: 1_000),
            .init(sourceID: 3, interfaceName: "utun4", receivedBytes: 500, sentBytes: 300),
        ], timestamp: 10)
        require(first["en0"]?.downloadBytesPerSecond == 0, "first sample establishes baseline")

        let second = calculator.update(samples: [
            .init(sourceID: 1, interfaceName: "en0", receivedBytes: 11_000, sentBytes: 5_200),
            .init(sourceID: 2, interfaceName: "en0", receivedBytes: 2_500, sentBytes: 1_100),
            .init(sourceID: 3, interfaceName: "utun4", receivedBytes: 800, sentBytes: 500),
        ], timestamp: 12)
        require(second["en0"]?.downloadBytesPerSecond == 750, "multiple default routes aggregate by interface")
        require(second["en0"]?.uploadBytesPerSecond == 150, "upload routes aggregate by interface")
        require(second["utun4"]?.downloadBytesPerSecond == 150, "VPN route rate")

        let switched = calculator.update(samples: [
            .init(sourceID: 4, interfaceName: "utun5", receivedBytes: 900_000_000, sentBytes: 700_000_000),
        ], timestamp: 13)
        require(switched["utun5"]?.downloadBytesPerSecond == 0, "new route source does not create a spike")

        let reset = calculator.update(samples: [
            .init(sourceID: 4, interfaceName: "utun5", receivedBytes: 10, sentBytes: 5),
        ], timestamp: 14)
        require(reset["utun5"]?.downloadBytesPerSecond == 0, "counter reset does not wrap")

        calculator.reset()
        let afterReset = calculator.update(samples: [
            .init(sourceID: 4, interfaceName: "utun5", receivedBytes: 50, sentBytes: 25),
        ], timestamp: 20)
        require(afterReset["utun5"]?.downloadBytesPerSecond == 0, "explicit reset establishes a new baseline")

        print("NetworkStatistics traffic source tests passed")
    }
}
