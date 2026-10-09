import Foundation

struct ReleaseDescriptor: Equatable {
    let version: String
    let tag: String
    let isPrerelease: Bool
    let downloadURL: URL
    let checksumURL: URL
    let signatureURL: URL
}

final class ReleaseProvider {
    enum ProviderError: LocalizedError {
        case invalidURL, network(String), http(Int), invalidResponse, noRelease
        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid GitHub release URL."
            case .network(let message): "Could not check for updates: \(message)"
            case .http(let code): "GitHub returned an unexpected response (HTTP \(code))."
            case .invalidResponse: "GitHub returned an invalid release response."
            case .noRelease: "Could not find a usable GitHub release."
            }
        }
    }

    private let session: URLSession
    private let defaults: UserDefaults
    private let maximumResponseSize = 5 * 1024 * 1024

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    @discardableResult
    func fetch(repo: String, includePrereleases: Bool, userAgent: String, completion: @escaping (Result<ReleaseDescriptor, Error>) -> Void) -> URLSessionDataTask? {
        guard Self.validRepository(repo) else {
            completion(.failure(ProviderError.invalidURL))
            return nil
        }
        if includePrereleases {
            return fetchReleaseFeed(repo: repo, userAgent: userAgent, completion: completion)
        }
        return fetchLatestRelease(repo: repo, userAgent: userAgent, completion: completion)
    }

    private func fetchLatestRelease(
        repo: String,
        userAgent: String,
        completion: @escaping (Result<ReleaseDescriptor, Error>) -> Void
    ) -> URLSessionDataTask? {
        guard let url = URL(string: "https://github.com/\(repo)/releases/latest") else {
            completion(.failure(ProviderError.invalidURL))
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { _, response, error in
            if let error {
                completion(.failure(ProviderError.network(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(ProviderError.invalidResponse))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                completion(.failure(ProviderError.http(http.statusCode)))
                return
            }
            guard let tag = Self.releaseTag(from: http.url, repo: repo),
                  !AppSettings.isPrereleaseTag(tag),
                  let release = Self.descriptor(repo: repo, tag: tag) else {
                completion(.failure(ProviderError.noRelease))
                return
            }
            completion(.success(release))
        }
        task.resume()
        return task
    }

    private func fetchReleaseFeed(
        repo: String,
        userAgent: String,
        completion: @escaping (Result<ReleaseDescriptor, Error>) -> Void
    ) -> URLSessionDataTask? {
        guard let url = URL(string: "https://github.com/\(repo)/releases.atom") else {
            completion(.failure(ProviderError.invalidURL))
            return nil
        }
        let prefix = "ReleaseFeedProvider.\(repo)"
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        if let etag = defaults.string(forKey: "\(prefix).etag") { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let task = session.dataTask(with: request) { [defaults, maximumResponseSize] data, response, error in
            if let error { completion(.failure(ProviderError.network(error.localizedDescription))); return }
            guard let http = response as? HTTPURLResponse else { completion(.failure(ProviderError.invalidResponse)); return }
            let responseData: Data?
            if http.statusCode == 304 {
                responseData = defaults.data(forKey: "\(prefix).data")
            } else if (200...299).contains(http.statusCode) {
                responseData = data
                if let data, data.count <= maximumResponseSize {
                    defaults.set(data, forKey: "\(prefix).data")
                    if let etag = http.value(forHTTPHeaderField: "ETag") { defaults.set(etag, forKey: "\(prefix).etag") }
                }
            } else { completion(.failure(ProviderError.http(http.statusCode))); return }
            guard let responseData, responseData.count <= maximumResponseSize,
                  let tags = GitHubReleaseFeedParser.tags(from: responseData) else {
                completion(.failure(ProviderError.invalidResponse))
                return
            }
            guard let tag = AppSettings.newestReleaseTag(from: tags, includePrereleases: true),
                  let release = Self.descriptor(repo: repo, tag: tag) else {
                completion(.failure(ProviderError.noRelease))
                return
            }
            completion(.success(release))
        }
        task.resume()
        return task
    }

    private static func releaseTag(from url: URL?, repo: String) -> String? {
        guard let url, url.scheme == "https", url.host == "github.com" else { return nil }
        let prefix = "/\(repo)/releases/tag/"
        guard url.path.hasPrefix(prefix) else { return nil }
        let tag = String(url.path.dropFirst(prefix.count))
        return AppSettings.ReleaseVersion(tag) == nil ? nil : tag
    }

    private static func descriptor(repo: String, tag: String) -> ReleaseDescriptor? {
        guard let version = AppSettings.appVersion(fromReleaseTag: tag),
              let baseURL = releaseAssetBaseURL(repo: repo, tag: tag) else {
            return nil
        }
        return ReleaseDescriptor(
            version: version,
            tag: tag,
            isPrerelease: AppSettings.isPrereleaseTag(tag),
            downloadURL: baseURL.appendingPathComponent("NetSpeedMonitor.zip"),
            checksumURL: baseURL.appendingPathComponent("NetSpeedMonitor.sha256"),
            signatureURL: baseURL.appendingPathComponent("NetSpeedMonitor.sig")
        )
    }

    private static func releaseAssetBaseURL(repo: String, tag: String) -> URL? {
        guard var url = URL(string: "https://github.com") else { return nil }
        for component in repo.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        url.appendPathComponent("releases")
        url.appendPathComponent("download")
        url.appendPathComponent(tag)
        return url
    }

    private static func validRepository(_ repo: String) -> Bool {
        let components = repo.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return components.count == 2 && components.allSatisfy {
            !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains)
        }
    }
}

private final class GitHubReleaseFeedParser: NSObject, XMLParserDelegate {
    private var entryDepth = 0
    private var capturesTitle = false
    private var title = ""
    private(set) var releaseTags: [String] = []

    static func tags(from data: Data) -> [String]? {
        let delegate = GitHubReleaseFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        return parser.parse() ? delegate.releaseTags : nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "entry" {
            entryDepth += 1
        } else if elementName == "title", entryDepth > 0 {
            capturesTitle = true
            title = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturesTitle {
            title += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "title", capturesTitle {
            let tag = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tag.isEmpty {
                releaseTags.append(tag)
            }
            capturesTitle = false
        } else if elementName == "entry" {
            entryDepth = max(0, entryDepth - 1)
        }
    }
}
