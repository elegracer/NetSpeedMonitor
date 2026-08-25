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
