import Cocoa
import Network
import ServiceManagement
import os.log

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "elegracer")

enum NetSpeedUpdateInterval: Int, CaseIterable {
    case Sec1 = 1
    case Sec2 = 2
    case Sec5 = 5
    case Sec10 = 10
    case Sec30 = 30

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

private enum UDKeys {
    static let selectedInterface = "SelectedInterfaceName"
    static let updateInterval = "NetSpeedUpdateInterval"
}

class MenuSpacerView: NSView {
    var spacerWidth: CGFloat = 100 {
        didSet { invalidateIntrinsicContentSize() }
    }
    override var intrinsicContentSize: NSSize {
        return NSSize(width: spacerWidth, height: 0)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private var interfaceMenuItem: NSMenuItem!
    private var interfaceSubmenu: NSMenu!
    private var autoInterfaceItem: NSMenuItem!
    private var interfaceItemsMap: [String: NSMenuItem] = [:]
    private var interfaceViewsMap: [String: InterfaceItemView] = [:]
    private var interfaceSizingItem: NSMenuItem!

    private let interfaceItemRowHeight: CGFloat = 22

    private var autoLaunchItem: NSMenuItem!
    private var intervalItems: [NetSpeedUpdateInterval: NSMenuItem] = [:]

    private var timer: Timer?
    private let netTrafficStat = NetTrafficStatReceiver()

    private var isMenuOpen: Bool = false
    private var latestSpeeds: [String: (down: Double, up: Double, isUp: Bool)] = [:]

    private var activeAutoInterfaceName: String?
    private var routeConnection: NWConnection?

    private let speedMetrics = [" B", "KB", "MB", "GB", "TB"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIconGenerator.generateIcon(
            text: "↑ \(String(format: "%6.2lf", 0)) \(" B")/s\n↓ \(String(format: "%6.2lf", 0)) \(" B")/s"
        )
        statusItem.button?.imagePosition = .imageOnly

        buildMenu()
        updateAutoLaunchStateFromSystem()
        updateIntervalCheckmarks()
        updateInterfaceCheckmarks()
        startRouteMonitoring()
        startTimer()
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        interfaceMenuItem = NSMenuItem(title: "Interface", action: nil, keyEquivalent: "")
        interfaceSubmenu = NSMenu(title: "Network Interface")
        interfaceMenuItem.submenu = interfaceSubmenu
        menu.addItem(interfaceMenuItem)

        autoInterfaceItem = NSMenuItem(title: "Auto", action: #selector(selectAutoInterface(_:)), keyEquivalent: "")
        autoInterfaceItem.target = self
        interfaceSubmenu.addItem(autoInterfaceItem)
        interfaceSubmenu.addItem(NSMenuItem.separator())

        interfaceSizingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        interfaceSizingItem.isEnabled = false
        let spacerView = MenuSpacerView(frame: NSRect(x: 0, y: 0, width: 200, height: 0))
        spacerView.spacerWidth = 200
        interfaceSizingItem.view = spacerView
        interfaceSubmenu.addItem(interfaceSizingItem)

        menu.addItem(NSMenuItem.separator())

        autoLaunchItem = NSMenuItem(title: "Start at Login", action: #selector(toggleAutoLaunch(_:)), keyEquivalent: "")
        autoLaunchItem.target = self
        menu.addItem(autoLaunchItem)

        menu.addItem(NSMenuItem.separator())

        let intervalHeader = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        intervalHeader.isEnabled = false
        menu.addItem(intervalHeader)

        for interval in NetSpeedUpdateInterval.allCases {
            let item = NSMenuItem(title: interval.displayName, action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = interval.rawValue
            intervalItems[interval] = item
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let activityItem = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor(_:)), keyEquivalent: "")
        activityItem.target = self
        menu.addItem(activityItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Settings

    private var selectedInterfaceName: String {
        get { UserDefaults.standard.string(forKey: UDKeys.selectedInterface) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: UDKeys.selectedInterface)
            updateInterfaceCheckmarks()
            tick()
        }
    }

    private var isAutoMode: Bool { selectedInterfaceName.isEmpty }

    private var updateInterval: NetSpeedUpdateInterval {
        get {
            let raw = UserDefaults.standard.integer(forKey: UDKeys.updateInterval)
            return NetSpeedUpdateInterval(rawValue: raw) ?? .Sec1
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: UDKeys.updateInterval)
            updateIntervalCheckmarks()
            stopTimer()
            startTimer()
        }
    }

    // MARK: - Timer

    private func startRouteMonitoring() {
        routeConnection?.cancel()
        let connection = NWConnection(host: "1.1.1.1", port: 53, using: .udp)
        connection.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let interfaceName = path.availableInterfaces.first?.name
            if self.activeAutoInterfaceName != interfaceName {
                self.activeAutoInterfaceName = interfaceName
                logger.info("Effective route interface: \(interfaceName ?? "unavailable", privacy: .public)")
                self.updateInterfaceCheckmarks()
                self.tick()
            }
        }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed(let error) = state {
                logger.warning("Route monitoring failed: \(error.localizedDescription)")
                guard let self, self.routeConnection === connection else { return }
                self.routeConnection = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.startRouteMonitoring()
                }
            }
        }
        connection.start(queue: .main)
        routeConnection = connection
    }

    private func startTimer() {
        let interval = TimeInterval(updateInterval.rawValue)
        let timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
        logger.info("Timer started interval=\(interval)")
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        logger.info("Timer stopped")
    }

    @objc private func tick() {
        guard let statMap = netTrafficStat.getNetTrafficStatMap() else { return }

        var speeds: [String: (down: Double, up: Double, isUp: Bool)] = [:]

        for (key, val) in statMap {
            guard let name = key as? String,
                  let s = val as? NetTrafficStatOC else { continue }
            let down = s.ibytes_per_sec.doubleValue
            let up = s.obytes_per_sec.doubleValue
            let isUp = s.isUp
            let hasTraffic = s.total_ibytes > 0 || s.total_obytes > 0
                || s.delta_ibytes > 0 || s.delta_obytes > 0
                || down > 0 || up > 0
            if isUp || hasTraffic {
                speeds[name] = (down, up, isUp)
            }
        }

        latestSpeeds = speeds
        let activeIfaces = speeds.keys.sorted()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let doStructure = !self.isMenuOpen
            self.updateIcon(with: speeds)
            self.syncInterfaceMenu(with: activeIfaces, speeds: speeds, structuralChanges: doStructure)
        }
    }

    // MARK: - Menu UI Updates

    private func syncInterfaceMenu(with ifaces: [String], speeds: [String: (down: Double, up: Double, isUp: Bool)], structuralChanges: Bool = true) {
        if structuralChanges {
            let currentSet = Set(interfaceItemsMap.keys)
            let newSet = Set(ifaces)

            let removed = currentSet.subtracting(newSet)
            for name in removed {
                if let item = interfaceItemsMap[name] {
                    interfaceSubmenu.removeItem(item)
                    interfaceItemsMap.removeValue(forKey: name)
                    interfaceViewsMap.removeValue(forKey: name)
                }
            }

            for name in ifaces where interfaceItemsMap[name] == nil {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.target = self
                item.representedObject = name as NSString

                let v = InterfaceItemView(frame: NSRect(x: 0, y: 0, width: 280, height: interfaceItemRowHeight))
                v.interfaceName = name
                v.autoresizingMask = [.width]
                v.onAction = { [weak self] in
                    self?.selectedInterfaceName = name
                }
                item.view = v

                interfaceSubmenu.addItem(item)
                interfaceItemsMap[name] = item
                interfaceViewsMap[name] = v
            }
        }

        for name in interfaceViewsMap.keys {
            guard let v = interfaceViewsMap[name],
                  let sp = speeds[name] else { continue }
            let (downVal, downMetric) = iconSpeed(sp.down)
            let (upVal, upMetric) = iconSpeed(sp.up)
            let upStr = String(format: "%6.2lf %@/s", upVal, upMetric)
            let downStr = String(format: "%6.2lf %@/s", downVal, downMetric)
            v.speedText = "↓\(downStr)  ↑\(upStr)"
        }

        if structuralChanges {
            var maxNameW: CGFloat = 0
            for name in interfaceViewsMap.keys {
                maxNameW = max(maxNameW, InterfaceItemView.measureNameWidth(name))
            }

            let speedColW = InterfaceItemView.measureSpeedWidth(InterfaceItemView.speedSampleText)

            let autoAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 13)]
            let autoWidth = ("Auto" as NSString).size(withAttributes: autoAttrs).width + 32

            let totalW = max(InterfaceItemView.totalWidth(for: maxNameW, speedColW: speedColW), autoWidth + 20)
            interfaceSubmenu.minimumWidth = totalW
            (interfaceSizingItem.view as? MenuSpacerView)?.spacerWidth = totalW

            for (_, v) in interfaceViewsMap {
                v.nameColumnWidth = maxNameW
                v.speedColumnWidth = speedColW
            }
        }

        updateInterfaceCheckmarks()
    }

    private func updateInterfaceCheckmarks() {
        autoInterfaceItem.state = isAutoMode ? .on : .off
        for (name, v) in interfaceViewsMap {
            v.isChecked = (selectedInterfaceName == name)
        }
        if isAutoMode {
            if let activeAutoInterfaceName {
                interfaceMenuItem.title = "Interface: Auto (\(activeAutoInterfaceName))"
            } else {
                interfaceMenuItem.title = "Interface: Auto"
            }
        } else {
            interfaceMenuItem.title = "Interface: \(selectedInterfaceName)"
        }
    }

    private func updateIntervalCheckmarks() {
        let current = updateInterval
        for (interval, item) in intervalItems {
            item.state = (interval == current) ? .on : .off
        }
    }

    @objc private func updateAutoLaunchStateFromSystem() {
        let enabled = SMAppService.mainApp.status == .enabled
        autoLaunchItem.state = enabled ? .on : .off
    }

    // MARK: - Icon Update

    private func updateIcon(with speeds: [String: (down: Double, up: Double, isUp: Bool)]) {
        var downBps: Double = 0
        var upBps: Double = 0

        if isAutoMode {
            if let activeAutoInterfaceName, let sp = speeds[activeAutoInterfaceName] {
                downBps = sp.down
                upBps = sp.up
            } else {
                for (_, sp) in speeds {
                    if sp.down > downBps { downBps = sp.down }
                    if sp.up > upBps { upBps = sp.up }
                }
            }
        } else if let sp = speeds[selectedInterfaceName] {
            downBps = sp.down
            upBps = sp.up
        }

        let (downVal, downMetric) = iconSpeed(downBps)
        let (upVal, upMetric) = iconSpeed(upBps)
        let text = "↑ \(String(format: "%6.2lf", upVal)) \(upMetric)/s\n↓ \(String(format: "%6.2lf", downVal)) \(downMetric)/s"
        statusItem.button?.image = MenuBarIconGenerator.generateIcon(text: text)
    }

    private func iconSpeed(_ bytesPerSec: Double) -> (Double, String) {
        var v = bytesPerSec
        var idx = 0
        while v > 1000.0 && idx < speedMetrics.count - 1 {
            v /= 1024.0
            idx += 1
        }
        return (v, speedMetrics[idx])
    }

    // MARK: - Menu Actions

    @objc private func selectAutoInterface(_ sender: NSMenuItem) {
        selectedInterfaceName = ""
    }

    @objc private func toggleAutoLaunch(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            autoLaunchItem.state = service.status == .enabled ? .on : .off
            logger.info("AutoLaunch toggled, now: \(service.status == .enabled)")
        } catch {
            logger.warning("Failed to toggle auto launch: \(error.localizedDescription)")
        }
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let interval = NetSpeedUpdateInterval(rawValue: sender.tag) else { return }
        updateInterval = interval
    }

    @objc private func openActivityMonitor(_ sender: NSMenuItem) {
        let bundleID = "com.apple.ActivityMonitor"
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, error in
                if let error = error {
                    logger.warning("Open Activity Monitor failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        updateAutoLaunchStateFromSystem()
        DispatchQueue.main.async { [weak self] in
            self?.tick()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        let activeIfaces = latestSpeeds.keys.sorted()
        syncInterfaceMenu(with: activeIfaces, speeds: latestSpeeds, structuralChanges: true)
    }
}
