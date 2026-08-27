import Foundation

struct ReleaseDescriptor: Equatable {
    let version: String
    let tag: String
    let isPrerelease: Bool
    let downloadURL: URL
    let digest: String?
    let signatureURL: URL
}

final class ReleaseProvider {
    enum ProviderError: LocalizedError {
        case invalidURL, network(String), http(Int), rateLimited(Date?), invalidResponse, noRelease
        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid GitHub release URL."
            case .network(let message): "Could not check for updates: \(message)"
            case .http(let code): "GitHub returned an unexpected response (HTTP \(code))."
            case .rateLimited(let date): date.map { "GitHub rate limit reached. Try again after \($0.formatted())." } ?? "GitHub rate limit reached. Try again later."
            case .invalidResponse: "GitHub returned an invalid release response."
            case .noRelease: "Could not find a usable GitHub release."
            }
        }
    }

    private struct GitHubRelease: Codable {
        struct Asset: Codable {
            let name: String
            let browserDownloadURL: URL
            let digest: String?
            enum CodingKeys: String, CodingKey { case name, digest; case browserDownloadURL = "browser_download_url" }
        }
        let tagName: String
        let prerelease: Bool
        let draft: Bool
        let assets: [Asset]
        enum CodingKeys: String, CodingKey { case prerelease, draft, assets; case tagName = "tag_name" }
    }

    private let session: URLSession
    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let maximumResponseSize = 5 * 1024 * 1024

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    @discardableResult
    func fetch(repo: String, includePrereleases: Bool, userAgent: String, completion: @escaping (Result<ReleaseDescriptor, Error>) -> Void) -> URLSessionDataTask? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=100") else { completion(.failure(ProviderError.invalidURL)); return nil }
        let prefix = "ReleaseProvider.\(repo)"
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let etag = defaults.string(forKey: "\(prefix).etag") { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let task = session.dataTask(with: request) { [defaults, decoder, maximumResponseSize] data, response, error in
            if let error { completion(.failure(ProviderError.network(error.localizedDescription))); return }
            guard let http = response as? HTTPURLResponse else { completion(.failure(ProviderError.invalidResponse)); return }
            if http.statusCode == 403 || http.statusCode == 429 {
                let retry = Self.retryDate(from: http)
                if let retry { defaults.set(retry, forKey: "\(prefix).retryAfter") }
                completion(.failure(ProviderError.rateLimited(retry))); return
            }
            let responseData: Data?
            if http.statusCode == 304 {
                responseData = defaults.data(forKey: "\(prefix).data")
            } else if (200...299).contains(http.statusCode) {
                responseData = data
                defaults.removeObject(forKey: "\(prefix).retryAfter")
                if let data, data.count <= maximumResponseSize {
                    defaults.set(data, forKey: "\(prefix).data")
                    if let etag = http.value(forHTTPHeaderField: "ETag") { defaults.set(etag, forKey: "\(prefix).etag") }
                }
            } else { completion(.failure(ProviderError.http(http.statusCode))); return }
            guard let responseData, responseData.count <= maximumResponseSize,
                  let releases = try? decoder.decode([GitHubRelease].self, from: responseData) else { completion(.failure(ProviderError.invalidResponse)); return }
            guard let release = releases.filter({ !$0.draft && (includePrereleases || !$0.prerelease) }).compactMap(Self.descriptor).max(by: { AppSettings.compareVersions($0.tag, $1.tag) == .orderedAscending }) else { completion(.failure(ProviderError.noRelease)); return }
            completion(.success(release))
        }
        task.resume()
        return task
    }

    func retryAfter(repo: String) -> Date? { defaults.object(forKey: "ReleaseProvider.\(repo).retryAfter") as? Date }

    private static func descriptor(_ response: GitHubRelease) -> ReleaseDescriptor? {
        guard AppSettings.ReleaseVersion(response.tagName) != nil,
              let version = AppSettings.appVersion(fromReleaseTag: response.tagName),
              let zip = response.assets.first(where: { $0.name == "NetSpeedMonitor.zip" }),
              let signature = response.assets.first(where: { $0.name == "NetSpeedMonitor.sig" }),
              let digest = zip.digest, digest.hasPrefix("sha256:"), digest.count == 71,
              trusted(zip.browserDownloadURL), trusted(signature.browserDownloadURL) else { return nil }
        return ReleaseDescriptor(version: version, tag: response.tagName, isPrerelease: response.prerelease, downloadURL: zip.browserDownloadURL, digest: digest, signatureURL: signature.browserDownloadURL)
    }

    private static func trusted(_ url: URL) -> Bool { url.scheme == "https" && url.host == "github.com" }

    private static func retryDate(from response: HTTPURLResponse) -> Date? {
        if let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) { return Date().addingTimeInterval(seconds) }
        if let timestamp = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init) { return Date(timeIntervalSince1970: timestamp) }
        return nil
    }
}
