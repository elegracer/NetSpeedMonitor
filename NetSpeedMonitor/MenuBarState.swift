import SwiftUI
import Combine
import ServiceManagement

enum NetSpeedUpdateInterval: Int, CaseIterable, Identifiable {
    case Sec1 = 1
    case Sec2 = 2
    case Sec5 = 5
    case Sec10 = 10
    case Sec30 = 30

    var id: Int { self.rawValue }

    var displayName: String {
        switch self {
        case .Sec1: return "1s"
        case .Sec2: return "2s"
        case .Sec5: return "5s"
        case .Sec10: return "10s"
        case .Sec30: return "30s"
        }
    }
}

class MenuBarState: ObservableObject {
    @AppStorage("AutoLaunchEnabled") var autoLaunchEnabled: Bool = false {
        didSet { updateAutoLaunchStatus() }
    }
    @AppStorage("NetSpeedUpdateInterval") var netSpeedUpdateInterval: NetSpeedUpdateInterval = .Sec1 {
        didSet { updateNetSpeedUpdateIntervalStatus() }
    }
    @Published var menuText = "↑ \(String(format: "%6.2lf", 0)) \(" B")/s\n↓ \(String(format: "%6.2lf", 0)) \(" B")/s"

    var currentIcon: NSImage {
        return MenuBarIconGenerator.generateIcon(text: menuText)
    }

    private var timer: Timer?
    private var netTrafficStat = NetTrafficStatReceiver()

    private var uploadSpeed: Double = 0.0
    private var downloadSpeed: Double = 0.0
    private var uploadMetric: String = " B"
    private var downloadMetric: String = " B"
    private let speedMetrics: [String] = [" B", "KB", "MB", "GB", "TB"]

    private func currentAutoLaunchStatus() -> Bool {
        let service = SMAppService.mainApp
        let status = service.status
        return status == .enabled
    }

    private func updateAutoLaunchStatus() {
        let service = SMAppService.mainApp

        do {
            if autoLaunchEnabled {
                if service.status == .notFound || service.status == .notRegistered {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
            logger.info("updateAutoLaunchStatus succeeded, autoLaunchEnabled: \(String(self.autoLaunchEnabled)), service.enabled: \(String(service.status == .enabled))")
        } catch {
            logger.warning("updateAutoLaunchStatus failed: \(error.localizedDescription), autoLaunchEnabled: \(String(self.autoLaunchEnabled)), service.enabled: \(String(service.status == .enabled))")
            autoLaunchEnabled = currentAutoLaunchStatus()
        }
    }

    private func updateNetSpeedUpdateIntervalStatus() {
        logger.info("netSpeedUpdateInterval, \(self.netSpeedUpdateInterval.displayName)")
        self.stopTimer()
        self.startTimer()
    }

    private func startTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(self.netSpeedUpdateInterval.rawValue), repeats: true) { _ in

            guard let netTrafficStatMap = self.netTrafficStat.getNetTrafficStatMap() else {
                return
            }

            var maxDownloadSpeed: Double = 0.0
            var maxUploadSpeed: Double = 0.0
            for (_, stat) in netTrafficStatMap {
                if let netStat = stat as? NetTrafficStatOC {
                    let down = netStat.ibytes_per_sec.doubleValue
                    let up = netStat.obytes_per_sec.doubleValue
                    if down > maxDownloadSpeed {
                        maxDownloadSpeed = down
                    }
                    if up > maxUploadSpeed {
                        maxUploadSpeed = up
                    }
                }
            }

            self.downloadSpeed = maxDownloadSpeed
            self.uploadSpeed = maxUploadSpeed
            self.downloadMetric = self.speedMetrics.first!
            self.uploadMetric = self.speedMetrics.first!
            for metric in self.speedMetrics.dropFirst() {
                if self.downloadSpeed > 1000.0 {
                    self.downloadSpeed /= 1024.0
                    self.downloadMetric = metric
                }
                if self.uploadSpeed > 1000.0 {
                    self.uploadSpeed /= 1024.0
                    self.uploadMetric = metric
                }
            }
            self.menuText = "↑ \(String(format: "%6.2lf", self.uploadSpeed)) \(self.uploadMetric)/s\n↓ \(String(format: "%6.2lf", self.downloadSpeed)) \(self.downloadMetric)/s"
            
            logger.info("deltaIn: \(String(format:"%.6f", self.downloadSpeed)) \(self.downloadMetric)/s, deltaOut: \(String(format:"%.6f", self.uploadSpeed)) \(self.uploadMetric)/s")
        }
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
        logger.info("startTimer")
    }

    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
        logger.info("stopTimer")
    }

    init() {
        DispatchQueue.main.async {
            self.autoLaunchEnabled = self.currentAutoLaunchStatus()
            self.startTimer()
        }
    }

    deinit {
        DispatchQueue.main.async {
            self.stopTimer()
        }
    }
}
