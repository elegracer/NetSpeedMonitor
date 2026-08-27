import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

func releaseJSON() -> Data {
    let digest = "sha256:" + String(repeating: "a", count: 64)
    return Data("[{\"tag_name\":\"v1.2-beta.1\",\"prerelease\":true,\"draft\":false,\"assets\":[{\"name\":\"NetSpeedMonitor.zip\",\"browser_download_url\":\"https://github.com/a/b/releases/download/v1.2-beta.1/NetSpeedMonitor.zip\",\"digest\":\"\(digest)\"},{\"name\":\"NetSpeedMonitor.sig\",\"browser_download_url\":\"https://github.com/a/b/releases/download/v1.2-beta.1/NetSpeedMonitor.sig\",\"digest\":null}]},{\"tag_name\":\"v1.2-beta.2\",\"prerelease\":true,\"draft\":false,\"assets\":[{\"name\":\"NetSpeedMonitor.zip\",\"browser_download_url\":\"https://github.com/a/b/releases/download/v1.2-beta.2/NetSpeedMonitor.zip\",\"digest\":\"\(digest)\"},{\"name\":\"NetSpeedMonitor.sig\",\"browser_download_url\":\"https://github.com/a/b/releases/download/v1.2-beta.2/NetSpeedMonitor.sig\",\"digest\":null}]},{\"tag_name\":\"v1.1\",\"prerelease\":false,\"draft\":false,\"assets\":[{\"name\":\"NetSpeedMonitor.zip\",\"browser_download_url\":\"https://github.com/a/b/releases/download/v1.1/NetSpeedMonitor.zip\",\"digest\":\"\(digest)\"},{\"name\":\"NetSpeedMonitor.sig\",\"browser_download_url\":\"https://github.com/a/b/releases/download/v1.1/NetSpeedMonitor.sig\",\"digest\":null}]}]".utf8)
}

func fetch(_ provider: ReleaseProvider, includePrereleases: Bool) -> Result<ReleaseDescriptor, Error> {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<ReleaseDescriptor, Error>!
    _ = provider.fetch(repo: "a/b", includePrereleases: includePrereleases, userAgent: "test") { result = $0; semaphore.signal() }
    precondition(semaphore.wait(timeout: .now() + 2) == .success)
    return result
}

@main
struct ReleaseProviderTests {
    static func main() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let suite = "ReleaseProviderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = ReleaseProvider(session: session, defaults: defaults)

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "test-etag"])!
            return (response, releaseJSON())
        }
        guard case .success(let stable) = fetch(provider, includePrereleases: false), stable.tag == "v1.1" else { fatalError("stable filtering failed") }
        guard case .success(let preview) = fetch(provider, includePrereleases: true), preview.tag == "v1.2-beta.2" else { fatalError("newest prerelease selection failed") }

        MockURLProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "If-None-Match") == "test-etag")
            return (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, Data())
        }
        guard case .success(let cached) = fetch(provider, includePrereleases: false), cached.tag == "v1.1" else { fatalError("304 cache failed") }

        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "60"])!, Data())
        }
        guard case .failure = fetch(provider, includePrereleases: false), provider.retryAfter(repo: "a/b") != nil else { fatalError("rate limit handling failed") }
        print("Release provider tests passed")
    }
}
