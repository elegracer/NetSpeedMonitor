import Foundation

struct TrafficSample: Equatable {
    let timestamp: Date
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}

struct TrafficSummary: Equatable {
    let sampleCount: Int
    let averageDownload: Double
    let averageUpload: Double
    let peakDownload: Double
    let peakUpload: Double
    let sessionDownloadBytes: Double
    let sessionUploadBytes: Double
}

final class TrafficHistory {
    private(set) var samples: [TrafficSample] = []
    private(set) var smoothedDownload: Double = 0
    private(set) var smoothedUpload: Double = 0
    private(set) var sessionDownloadBytes: Double = 0
    private(set) var sessionUploadBytes: Double = 0
    private var previousTimestamp: Date?
    let capacity: Int
    let smoothingFactor: Double

    init(capacity: Int = 300, smoothingFactor: Double = 0.35) {
        self.capacity = max(1, capacity)
        self.smoothingFactor = min(1, max(0, smoothingFactor))
    }

    @discardableResult
    func append(timestamp: Date = Date(), download: Double, upload: Double) -> TrafficSample {
        let down = sanitize(download)
        let up = sanitize(upload)
        if samples.isEmpty {
            smoothedDownload = down
            smoothedUpload = up
        } else {
            smoothedDownload = smoothingFactor * down + (1 - smoothingFactor) * smoothedDownload
            smoothedUpload = smoothingFactor * up + (1 - smoothingFactor) * smoothedUpload
        }
        if let previousTimestamp {
            let duration = min(300, max(0, timestamp.timeIntervalSince(previousTimestamp)))
            sessionDownloadBytes += down * duration
            sessionUploadBytes += up * duration
        }
        previousTimestamp = timestamp
        let sample = TrafficSample(timestamp: timestamp, downloadBytesPerSecond: down, uploadBytesPerSecond: up)
        samples.append(sample)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        return sample
    }

    func reset() {
        samples.removeAll(keepingCapacity: true)
        smoothedDownload = 0
        smoothedUpload = 0
        sessionDownloadBytes = 0
        sessionUploadBytes = 0
        previousTimestamp = nil
    }

    var summary: TrafficSummary {
        let count = samples.count
        let down = samples.map(\.downloadBytesPerSecond)
        let up = samples.map(\.uploadBytesPerSecond)
        return TrafficSummary(sampleCount: count, averageDownload: count == 0 ? 0 : down.reduce(0, +) / Double(count), averageUpload: count == 0 ? 0 : up.reduce(0, +) / Double(count), peakDownload: down.max() ?? 0, peakUpload: up.max() ?? 0, sessionDownloadBytes: sessionDownloadBytes, sessionUploadBytes: sessionUploadBytes)
    }

    private func sanitize(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }
}
