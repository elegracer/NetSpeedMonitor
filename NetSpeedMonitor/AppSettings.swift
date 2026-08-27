import Foundation

enum AppSettings {
    enum DisplayMode: String, CaseIterable {
        case both, download, upload
        var title: String {
            switch self { case .both: "Upload and Download"; case .download: "Download Only"; case .upload: "Upload Only" }
        }
    }

    enum UnitMode: String, CaseIterable {
        case bytesBinary, bitsDecimal
        var title: String { self == .bytesBinary ? "Bytes (KiB base)" : "Bits (SI base)" }
    }

    struct ReleaseVersion: Comparable, Equatable {
        let core: [Int]
        let prerelease: [String]

        init?(_ tag: String) {
            let value = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let coreParts = parts[0].split(separator: ".", omittingEmptySubsequences: false)
            guard !coreParts.isEmpty, coreParts.allSatisfy({ Int($0) != nil }) else { return nil }
            core = coreParts.compactMap { Int($0) }
            prerelease = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : []
            if parts.count == 2 && prerelease.isEmpty { return nil }
        }

        static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
            guard lhs.prerelease == rhs.prerelease else { return false }
            let count = max(lhs.core.count, rhs.core.count)
            return (0..<count).allSatisfy { index in
                (index < lhs.core.count ? lhs.core[index] : 0) ==
                    (index < rhs.core.count ? rhs.core[index] : 0)
            }
        }

        static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
            let count = max(lhs.core.count, rhs.core.count)
            for index in 0..<count {
                let left = index < lhs.core.count ? lhs.core[index] : 0
                let right = index < rhs.core.count ? rhs.core[index] : 0
                if left != right { return left < right }
            }
            if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }
            for index in 0..<max(lhs.prerelease.count, rhs.prerelease.count) {
                guard index < lhs.prerelease.count else { return true }
                guard index < rhs.prerelease.count else { return false }
                let left = lhs.prerelease[index]
                let right = rhs.prerelease[index]
                if left == right { continue }
                if let leftNumber = Int(left), let rightNumber = Int(right) { return leftNumber < rightNumber }
                if Int(left) != nil { return true }
                if Int(right) != nil { return false }
                return left.localizedStandardCompare(right) == .orderedAscending
            }
            return false
        }
    }

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
    static let speedUnits = [" B", "KB", "MB", "GB", "TB"]

    static func normalizedUpdateChannel(_ value: String?) -> UpdateChannel {
        guard let value, let channel = UpdateChannel(rawValue: value) else { return .stable }
        return channel
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
        tags.compactMap { tag -> (tag: String, version: ReleaseVersion)? in
            guard let version = ReleaseVersion(tag) else { return nil }
            if !includePrereleases && isPrereleaseTag(tag) { return nil }
            return (tag, version)
        }
        .max(by: { $0.version < $1.version })?
        .tag
    }

    static func normalizedUpdateInterval(_ value: Int) -> Int {
        guard value > 0 else { return updateIntervals[0] }
        if updateIntervals.contains(value) { return value }
        return updateIntervals.min(by: { abs($0 - value) < abs($1 - value) }) ?? updateIntervals[0]
    }

    static func normalizedIntegerSmallUnits(_ value: Any?) -> Bool {
        value as? Bool ?? false
    }

    static func normalizedDisplayMode(_ value: String?) -> DisplayMode { value.flatMap(DisplayMode.init(rawValue:)) ?? .both }
    static func normalizedUnitMode(_ value: String?) -> UnitMode { value.flatMap(UnitMode.init(rawValue:)) ?? .bytesBinary }

    static func speedValueAndUnit(bytesPerSecond: Double) -> (value: Double, unit: String) {
        var value = bytesPerSecond
        var index = 0
        while value >= 1024.0 && index < speedUnits.count - 1 {
            value /= 1024.0
            index += 1
        }
        return (value, speedUnits[index])
    }

    static func formattedSpeed(bytesPerSecond: Double, integerSmallUnits: Bool, unitMode: UnitMode = .bytesBinary) -> String {
        let valueAndUnit: (value: Double, unit: String)
        if unitMode == .bitsDecimal {
            var value = max(0, bytesPerSecond) * 8
            let units = [" b", "kb", "Mb", "Gb", "Tb"]
            var index = 0
            while value >= 1000, index < units.count - 1 { value /= 1000; index += 1 }
            valueAndUnit = (value, units[index])
        } else {
            valueAndUnit = speedValueAndUnit(bytesPerSecond: bytesPerSecond)
        }
        let (value, unit) = valueAndUnit
        let usesIntegerFormat = integerSmallUnits && (unit == " B" || unit == "KB")
        if usesIntegerFormat {
            return String(format: "%6.0lf %@/s", value.rounded(), unit)
        }
        return String(format: "%6.2lf %@/s", value, unit)
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard let left = ReleaseVersion(lhs), let right = ReleaseVersion(rhs) else {
            return lhs.compare(rhs, options: .numeric)
        }
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }

    static func maximumSampleAge(for interval: Int) -> Double {
        max(Double(interval) * 1.5, Double(interval) + 1.0)
    }
}
