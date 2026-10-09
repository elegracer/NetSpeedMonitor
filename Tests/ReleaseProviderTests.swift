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

func releaseFeed() -> Data {
    Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Repository releases</title>
      <entry><title>v1.2-beta.1</title></entry>
      <entry><title>v1.2-beta.2</title></entry>
      <entry><title>v1.1</title></entry>
    </feed>
    """.utf8)
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

        let rateLimitSuite = "ReleaseProviderRateLimitTests-\(UUID().uuidString)"
        let rateLimitDefaults = UserDefaults(suiteName: rateLimitSuite)!
        defer { rateLimitDefaults.removePersistentDomain(forName: rateLimitSuite) }
        let rateLimitProvider = ReleaseProvider(session: session, defaults: rateLimitDefaults)
        MockURLProtocol.handler = { request in
            if request.url?.host == "api.github.com" {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 429,
                        httpVersion: nil,
                        headerFields: ["Retry-After": "60"]
                    )!,
                    Data()
                )
            }
            precondition(request.url?.absoluteString == "https://github.com/a/b/releases/latest")
            return (
                HTTPURLResponse(
                    url: URL(string: "https://github.com/a/b/releases/tag/v1.1")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        guard case .success(let rateLimitIndependent) = fetch(rateLimitProvider, includePrereleases: false),
              rateLimitIndependent.tag == "v1.1" else {
            fatalError("release discovery still depends on the rate-limited GitHub API")
        }

        let suite = "ReleaseProviderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = ReleaseProvider(session: session, defaults: defaults)

        MockURLProtocol.handler = { request in
            precondition(request.url?.host == "github.com")
            precondition(request.url?.path == "/a/b/releases/latest")
            precondition(request.httpMethod == "HEAD")
            return (
                HTTPURLResponse(
                    url: URL(string: "https://github.com/a/b/releases/tag/v1.1")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        guard case .success(let stable) = fetch(provider, includePrereleases: false),
              stable == ReleaseDescriptor(
                version: "1.1",
                tag: "v1.1",
                isPrerelease: false,
                downloadURL: URL(string: "https://github.com/a/b/releases/download/v1.1/NetSpeedMonitor.zip")!,
                checksumURL: URL(string: "https://github.com/a/b/releases/download/v1.1/NetSpeedMonitor.sha256")!,
                signatureURL: URL(string: "https://github.com/a/b/releases/download/v1.1/NetSpeedMonitor.sig")!
              ) else {
            fatalError("stable filtering or asset URL construction failed")
        }

        MockURLProtocol.handler = { request in
            precondition(request.url?.host == "github.com")
            precondition(request.url?.path == "/a/b/releases.atom")
            precondition(request.value(forHTTPHeaderField: "Accept") == "application/atom+xml")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "test-etag"])!
            return (response, releaseFeed())
        }
        guard case .success(let preview) = fetch(provider, includePrereleases: true),
              preview.tag == "v1.2-beta.2",
              preview.isPrerelease else {
            fatalError("newest prerelease selection failed")
        }

        MockURLProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "If-None-Match") == "test-etag")
            return (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, Data())
        }
        guard case .success(let cached) = fetch(provider, includePrereleases: true),
              cached.tag == "v1.2-beta.2" else {
            fatalError("304 cache failed")
        }

        MockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("<feed><entry>".utf8)
            )
        }
        guard case .failure = fetch(provider, includePrereleases: true) else {
            fatalError("malformed release feed was accepted")
        }
        print("Release provider tests passed")
    }
}
