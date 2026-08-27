import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }

@main
struct TrafficHistoryTests {
    static func main() {
        let base = Date(timeIntervalSince1970: 1_000)
        let history = TrafficHistory(capacity: 2, smoothingFactor: 0.5)
        history.append(timestamp: base, download: 100, upload: 50)
        history.append(timestamp: base.addingTimeInterval(2), download: 300, upload: 150)
        require(history.smoothedDownload == 200, "EMA download")
        require(history.sessionDownloadBytes == 600, "integrated download")
        history.append(timestamp: base.addingTimeInterval(3), download: .nan, upload: -1)
        require(history.samples.count == 2, "bounded capacity")
        require(history.samples.last?.downloadBytesPerSecond == 0, "NaN clamp")
        require(history.samples.last?.uploadBytesPerSecond == 0, "negative clamp")
        require(history.summary.peakDownload == 300, "summary peak")
        history.reset()
        require(history.samples.isEmpty && history.summary.sessionDownloadBytes == 0, "reset")
        print("Traffic history tests passed")
    }
}
