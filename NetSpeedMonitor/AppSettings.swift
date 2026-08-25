import Foundation

enum AppSettings {
    enum UpdateChannel: String, CaseIterable {
        case stable
        case prerelease

        var title: String {
            switch self {
            case .stable: "Release Only"
            case .prerelease: "Include Pre-releases"
            }
        }

        var description: String {
            switch self {
            case .stable: "Only check official GitHub releases."
            case .prerelease: "Check GitHub pre-releases before official releases."
            }
        }
    }

    static let updateIntervals = [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60]

    static func normalizedUpdateChannel(_ value: String?) -> UpdateChannel {
        guard let value, let channel = UpdateChannel(rawValue: value) else { return .stable }
        return channel
    }

    static func releaseTags(in text: String) -> [String] {
        let pattern = #"/releases/tag/(v[0-9][A-Za-z0-9._-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var tags: [String] = []
        for match in regex.matches(in: text, range: nsRange) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let tag = String(text[range])
            if seen.insert(tag).inserted {
                tags.append(tag)
            }
        }
        return tags
    }

    static func version(fromReleaseTag tag: String) -> String? {
        guard tag.hasPrefix("v"), tag.count > 1 else { return nil }
        return String(tag.dropFirst())
    }

    static func appVersion(fromReleaseTag tag: String) -> String? {
        version(fromReleaseTag: tag)?.split(separator: "-", maxSplits: 1).first.map(String.init)
    }

    static func isPrereleaseTag(_ tag: String) -> Bool {
        version(fromReleaseTag: tag)?.contains("-") == true
    }

    static func newestReleaseTag(from tags: [String], includePrereleases: Bool) -> String? {
        tags.compactMap { tag -> (tag: String, version: String)? in
            guard let version = version(fromReleaseTag: tag) else { return nil }
            if !includePrereleases && isPrereleaseTag(tag) { return nil }
            return (tag, version)
        }
        .max { lhs, rhs in
            let lhsAppVersion = appVersion(fromReleaseTag: lhs.tag) ?? lhs.version
            let rhsAppVersion = appVersion(fromReleaseTag: rhs.tag) ?? rhs.version
            let appComparison = compareVersions(lhsAppVersion, rhsAppVersion)
            if appComparison != .orderedSame {
                return appComparison == .orderedAscending
            }

            let lhsIsPrerelease = isPrereleaseTag(lhs.tag)
            let rhsIsPrerelease = isPrereleaseTag(rhs.tag)
            if lhsIsPrerelease != rhsIsPrerelease {
                return lhsIsPrerelease && !rhsIsPrerelease
            }

            return compareVersions(lhs.version, rhs.version) == .orderedAscending
        }?
        .tag
    }

    static func normalizedUpdateInterval(_ value: Int) -> Int {
        guard value > 0 else { return updateIntervals[0] }
        if updateIntervals.contains(value) { return value }
        return updateIntervals.min(by: { abs($0 - value) < abs($1 - value) }) ?? updateIntervals[0]
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }

    static func maximumSampleAge(for interval: Int) -> Double {
        max(Double(interval) * 1.5, Double(interval) + 1.0)
    }
}
