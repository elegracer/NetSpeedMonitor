import Foundation

func sample(_ source: NetworkStatisticsTrafficSource) -> [String: NetworkTrafficRate]? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: [String: NetworkTrafficRate]?
    source.requestUpdate {
        result = $0
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 3) == .success else {
        return nil
    }
    return result
}

func runDownload() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = [
        "--fail",
        "--location",
        "--silent",
        "--show-error",
        "--max-time", "10",
        "--limit-rate", "512k",
        "--range", "0-2097151",
        "--output", "/dev/null",
        "https://registry.npmjs.org/typescript/-/typescript-5.9.3.tgz?probe=nstat-runtime-\(UUID().uuidString)",
    ]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "NetworkStatisticsRuntimeTests", code: Int(process.terminationStatus))
    }
}

@main
struct NetworkStatisticsRuntimeTests {
    static func main() throws {
        let source = NetworkStatisticsTrafficSource()
        defer { source.stop() }
        precondition(source.isAvailable, "NetworkStatistics route source is unavailable")
        guard let interfaceName = RouteInterfaceResolver.currentDefaultInterface() else {
            fatalError("Default route interface is unavailable")
        }

        Thread.sleep(forTimeInterval: 0.2)
        guard sample(source) != nil else {
            fatalError("Initial NetworkStatistics query failed")
        }
        try runDownload()
        guard let rates = sample(source), let rate = rates[interfaceName] else {
            fatalError("NetworkStatistics did not return the default interface \(interfaceName)")
        }
        precondition(
            rate.downloadBytesPerSecond >= 64 * 1024,
            "Expected download traffic on \(interfaceName), got \(rate.downloadBytesPerSecond) B/s"
        )
        print(
            "NetworkStatistics runtime tests passed:"
                + " interface=\(interfaceName)"
                + " download=\(Int(rate.downloadBytesPerSecond)) B/s"
                + " upload=\(Int(rate.uploadBytesPerSecond)) B/s"
        )
    }
}
