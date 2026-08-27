import Cocoa
import Network
import ServiceManagement
import os.log

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "elegracer")

private enum UDKeys {
    static let selectedInterface = "SelectedInterfaceName"
    static let updateInterval = "NetSpeedUpdateInterval"
    static let updateChannel = "NetSpeedUpdateChannel"
    static let integerSmallUnits = "NetSpeedIntegerSmallUnits"
    static let displayMode = "NetSpeedDisplayMode"
    static let unitMode = "NetSpeedUnitMode"
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
    private var intervalMenuView: IntervalMenuView!

    private var timer: Timer?
    private let netTrafficStat = NetTrafficStatReceiver()
    private let trafficHistory = TrafficHistory()

    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statisticsWindow: NSWindow?
    private var statisticsSummaryLabel: NSTextField?
    private var statisticsChart: TrafficChartView?
    private var updateChannelPopUp: NSPopUpButton?
    private var updateChannelHelpLabel: NSTextField?
    private var integerSmallUnitsButton: NSButton?
    private var displayModePopUp: NSPopUpButton?
    private var unitModePopUp: NSPopUpButton?
    private lazy var updateController = UpdateController(appVersion: appVersion, githubRepo: githubRepo) { [weak self] in
        self?.updateChannel ?? .stable
    }

    private var isMenuOpen: Bool = false
    private var latestSpeeds: [String: (down: Double, up: Double, isUp: Bool)] = [:]

    private var activeAutoInterfaceName: String?
    private var routeMonitor: NWPathMonitor?
    private var powerObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let zeroSpeed = formattedSpeed(0)
        statusItem.button?.image = MenuBarIconGenerator.generateIcon(
            text: "↑ \(zeroSpeed)\n↓ \(zeroSpeed)"
        )
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "NetSpeedMonitor"
        statusItem.button?.setAccessibilityLabel("Network speed")

        buildMenu()
        updateAutoLaunchStateFromSystem()
        updateInterfaceCheckmarks()
        startRouteMonitoring()
        startTimer()
        tick()
        startSystemObservers()
        updateController.showPendingErrorIfNeeded()
        updateController.checkAutomaticallyIfNeeded()
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

        let intervalItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        intervalMenuView = IntervalMenuView(frame: NSRect(x: 0, y: 0, width: 340, height: 108))
        intervalMenuView.intervalSeconds = updateInterval
        intervalMenuView.onIntervalChange = { [weak self] seconds in
            self?.updateInterval = seconds
        }
        intervalItem.view = intervalMenuView
        menu.addItem(intervalItem)

        menu.addItem(NSMenuItem.separator())

        let activityItem = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor(_:)), keyEquivalent: "")
        activityItem.target = self
        menu.addItem(activityItem)
        let statisticsItem = NSMenuItem(title: "Session Statistics", action: #selector(showSessionStatistics(_:)), keyEquivalent: "")
        statisticsItem.target = self
        menu.addItem(statisticsItem)

        menu.addItem(NSMenuItem.separator())

        let checkUpdateItem = NSMenuItem(title: "Check Update", action: #selector(checkUpdate(_:)), keyEquivalent: "")
        checkUpdateItem.target = self
        configurePlainMenuItem(checkUpdateItem)
        menu.addItem(checkUpdateItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        configurePlainMenuItem(settingsItem)
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        configurePlainMenuItem(aboutItem)
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func configurePlainMenuItem(_ item: NSMenuItem) {
        item.image = nil
        item.state = .off
        item.indentationLevel = 0
        item.onStateImage = nil
        item.offStateImage = nil
        item.mixedStateImage = nil
    }

    // MARK: - Settings

    private var selectedInterfaceName: String {
        get { UserDefaults.standard.string(forKey: UDKeys.selectedInterface) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: UDKeys.selectedInterface)
            updateInterfaceCheckmarks()
            renderLatestSpeeds()
        }
    }

    private var isAutoMode: Bool { selectedInterfaceName.isEmpty }

    private var updateInterval: Int {
        get {
            let raw = UserDefaults.standard.integer(forKey: UDKeys.updateInterval)
            return AppSettings.normalizedUpdateInterval(raw)
        }
        set {
            let seconds = AppSettings.normalizedUpdateInterval(newValue)
            UserDefaults.standard.set(seconds, forKey: UDKeys.updateInterval)
            intervalMenuView?.intervalSeconds = seconds
            stopTimer()
            startTimer()
        }
    }

    private var updateChannel: AppSettings.UpdateChannel {
        get { AppSettings.normalizedUpdateChannel(UserDefaults.standard.string(forKey: UDKeys.updateChannel)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UDKeys.updateChannel) }
    }

    private var integerSmallUnits: Bool {
        get { AppSettings.normalizedIntegerSmallUnits(UserDefaults.standard.object(forKey: UDKeys.integerSmallUnits)) }
        set {
            UserDefaults.standard.set(newValue, forKey: UDKeys.integerSmallUnits)
            renderLatestSpeeds()
        }
    }

    private var displayMode: AppSettings.DisplayMode {
        get { AppSettings.normalizedDisplayMode(UserDefaults.standard.string(forKey: UDKeys.displayMode)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UDKeys.displayMode); renderLatestSpeeds() }
    }

    private var unitMode: AppSettings.UnitMode {
        get { AppSettings.normalizedUnitMode(UserDefaults.standard.string(forKey: UDKeys.unitMode)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: UDKeys.unitMode); renderLatestSpeeds() }
    }

    // MARK: - Timer

    private func startRouteMonitoring() {
        routeMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            DispatchQueue.main.async {
                let interfaceName = RouteInterfaceResolver.currentDefaultInterface()
                    ?? path.availableInterfaces.first(where: { path.usesInterfaceType($0.type) })?.name
                if self.activeAutoInterfaceName != interfaceName {
                    self.activeAutoInterfaceName = interfaceName
                    logger.info("Effective route interface: \(interfaceName ?? "unavailable", privacy: .public)")
                    self.updateInterfaceCheckmarks()
                    self.renderLatestSpeeds()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.elegracer.NetSpeedMonitor.route"))
        routeMonitor = monitor
    }

    private func startTimer() {
        let configured = TimeInterval(updateInterval)
        let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? max(5, configured) : configured
        let timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
        logger.info("Timer started interval=\(interval)")
    }

    private func startSystemObservers() {
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.stopTimer(); self?.startTimer()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.netTrafficStat.reset()
            self.trafficHistory.reset()
            self.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        logger.info("Timer stopped")
    }

    @objc private func tick() {
        guard let statMap = netTrafficStat.getNetTrafficStatMap() else {
            latestSpeeds = [:]
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateIcon(with: [:])
                self.syncInterfaceMenu(with: [], speeds: [:], structuralChanges: !self.isMenuOpen)
                self.refreshStatisticsWindow()
            }
            return
        }

        var speeds: [String: (down: Double, up: Double, isUp: Bool)] = [:]
        let maximumSampleAge = AppSettings.maximumSampleAge(for: updateInterval)

        for (key, val) in statMap {
            guard let name = key as? String,
                  let s = val as? NetTrafficStatOC else { continue }
            let isFreshSample = s.delta_ts_sec.doubleValue <= maximumSampleAge
            let down = isFreshSample ? s.ibytes_per_sec.doubleValue : 0
            let up = isFreshSample ? s.obytes_per_sec.doubleValue : 0
            let isUp = s.isUp
            let hasTraffic = s.total_ibytes > 0 || s.total_obytes > 0
                || s.delta_ibytes > 0 || s.delta_obytes > 0
                || down > 0 || up > 0
            if isUp || hasTraffic {
                speeds[name] = (down, up, isUp)
            }
        }

        latestSpeeds = speeds
        let displayed = displayedSpeed(from: speeds)
        trafficHistory.append(download: displayed.down, upload: displayed.up)
        let activeIfaces = speeds.keys.sorted()

        renderLatestSpeeds(activeIfaces: activeIfaces)
    }

    private func renderLatestSpeeds(activeIfaces: [String]? = nil) {
        let speeds = latestSpeeds
        let ifaces = activeIfaces ?? speeds.keys.sorted()
        let doStructure = !isMenuOpen
        updateIcon(with: speeds)
        syncInterfaceMenu(with: ifaces, speeds: speeds, structuralChanges: doStructure)
        refreshStatisticsWindow()
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
                v.interfaceName = InterfaceNameResolver.displayName(forBSDName: name)
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
            guard let v = interfaceViewsMap[name] else { continue }
            guard let sp = speeds[name] else {
                let zeroSpeed = formattedSpeed(0)
                v.speedText = "↓\(zeroSpeed)  ↑\(zeroSpeed)"
                continue
            }
            let downStr = formattedSpeed(sp.down)
            let upStr = formattedSpeed(sp.up)
            v.speedText = "↓\(downStr)  ↑\(upStr)"
        }

        if structuralChanges {
            var maxNameW: CGFloat = 0
            for name in interfaceViewsMap.keys {
                maxNameW = max(maxNameW, InterfaceItemView.measureNameWidth(InterfaceNameResolver.displayName(forBSDName: name)))
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
                interfaceMenuItem.title = "Interface: Auto (\(InterfaceNameResolver.displayName(forBSDName: activeAutoInterfaceName)))"
            } else {
                interfaceMenuItem.title = "Interface: Auto (Unavailable)"
            }
        } else {
            let available = latestSpeeds[selectedInterfaceName] != nil
            interfaceMenuItem.title = available
                ? "Interface: \(InterfaceNameResolver.displayName(forBSDName: selectedInterfaceName))"
                : "Interface: \(InterfaceNameResolver.displayName(forBSDName: selectedInterfaceName)) (Unavailable)"
        }
    }

    @objc private func updateAutoLaunchStateFromSystem() {
        let enabled = SMAppService.mainApp.status == .enabled
        autoLaunchItem.state = enabled ? .on : .off
    }

    // MARK: - Icon Update

    private func updateIcon(with speeds: [String: (down: Double, up: Double, isUp: Bool)]) {
        let displayed = displayedSpeed(from: speeds)
        let downBps = displayed.down
        let upBps = displayed.up

        let text: String
        switch displayMode {
        case .both: text = "↑ \(formattedSpeed(upBps))\n↓ \(formattedSpeed(downBps))"
        case .download: text = "↓ \(formattedSpeed(downBps))"
        case .upload: text = "↑ \(formattedSpeed(upBps))"
        }
        statusItem.button?.image = MenuBarIconGenerator.generateIcon(text: text)
        statusItem.button?.toolTip = "Download \(formattedSpeed(downBps)), upload \(formattedSpeed(upBps))"
        statusItem.button?.setAccessibilityValue("Download \(formattedSpeed(downBps)), upload \(formattedSpeed(upBps))")
    }

    private func displayedSpeed(from speeds: [String: (down: Double, up: Double, isUp: Bool)]) -> (down: Double, up: Double) {
        if isAutoMode, let activeAutoInterfaceName, let speed = speeds[activeAutoInterfaceName] { return (speed.down, speed.up) }
        if !isAutoMode, let speed = speeds[selectedInterfaceName] { return (speed.down, speed.up) }
        return (0, 0)
    }

    private func formattedSpeed(_ bytesPerSec: Double) -> String {
        AppSettings.formattedSpeed(bytesPerSecond: bytesPerSec, integerSmallUnits: integerSmallUnits, unitMode: unitMode)
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
            if service.status == .requiresApproval {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "Login Item Needs Approval"
                alert.informativeText = "Allow NetSpeedMonitor in System Settings → General → Login Items."
                alert.runModal()
            }
        } catch {
            logger.warning("Failed to toggle auto launch: \(error.localizedDescription)")
            updateAutoLaunchStateFromSystem()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could Not Change Login Item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
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

    @objc private func showSessionStatistics(_ sender: NSMenuItem) {
        menu.cancelTracking()
        if let statisticsWindow {
            refreshStatisticsWindow(force: true)
            statisticsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 320), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Session Statistics"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 440, height: 300)

        let content = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        content.material = .popover
        content.blendingMode = .behindWindow
        content.state = .active

        let summaryLabel = NSTextField(wrappingLabelWithString: "")
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        summaryLabel.maximumNumberOfLines = 5
        summaryLabel.lineBreakMode = .byWordWrapping

        let legend = NSTextField(labelWithString: "● Download    ● Upload")
        legend.translatesAutoresizingMaskIntoConstraints = false
        let legendText = NSMutableAttributedString(string: legend.stringValue)
        legendText.addAttribute(.foregroundColor, value: NSColor.systemCyan, range: NSRange(location: 0, length: 1))
        if let uploadDot = legend.stringValue.range(of: "●", range: legend.stringValue.index(after: legend.stringValue.startIndex)..<legend.stringValue.endIndex) {
            legendText.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: NSRange(uploadDot, in: legend.stringValue))
        }
        legend.attributedStringValue = legendText

        let chart = TrafficChartView(frame: .zero)
        chart.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(summaryLabel)
        content.addSubview(legend)
        content.addSubview(chart)
        NSLayoutConstraint.activate([
            summaryLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            summaryLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            summaryLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            legend.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 10),
            legend.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            chart.topAnchor.constraint(equalTo: legend.bottomAnchor, constant: 8),
            chart.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            chart.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            chart.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            chart.heightAnchor.constraint(greaterThanOrEqualToConstant: 130),
        ])
        window.contentView = content
        statisticsWindow = window
        statisticsSummaryLabel = summaryLabel
        statisticsChart = chart
        refreshStatisticsWindow(force: true)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshStatisticsWindow(force: Bool = false) {
        guard force || statisticsWindow?.isVisible == true else { return }
        let summary = trafficHistory.summary
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let route: String
        if isAutoMode {
            route = activeAutoInterfaceName.map(InterfaceNameResolver.displayName) ?? "Unavailable"
        } else {
            let name = InterfaceNameResolver.displayName(forBSDName: selectedInterfaceName)
            route = latestSpeeds[selectedInterfaceName] == nil ? "\(name) (Unavailable)" : name
        }
        let interval = timer?.timeInterval ?? TimeInterval(updateInterval)
        statisticsSummaryLabel?.stringValue = "Current interface: \(route)    Sample interval: \(String(format: "%.0f", interval)) s\nSession transferred: ↓ \(formatter.string(fromByteCount: Int64(summary.sessionDownloadBytes)))    ↑ \(formatter.string(fromByteCount: Int64(summary.sessionUploadBytes)))\nSession average: ↓ \(formattedSpeed(summary.averageDownload))    ↑ \(formattedSpeed(summary.averageUpload))\nSession peak: ↓ \(formattedSpeed(summary.peakDownload))    ↑ \(formattedSpeed(summary.peakUpload))"
        statisticsChart?.samples = trafficHistory.samples
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTimer()
        routeMonitor?.cancel()
        routeMonitor = nil
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    // MARK: - Check Update

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var githubRepo: String { "elegracer/NetSpeedMonitor" }

    @objc private func checkUpdate(_ sender: NSMenuItem) {
        menu.cancelTracking()
        updateController.start()
    }

    @objc private func showSettings(_ sender: NSMenuItem) {
        menu.cancelTracking()
        if let settingsWindow {
            syncSettingsControls()
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "NetSpeedMonitor Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false

        let contentView = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        contentView.material = .popover
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.wantsLayer = true
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Software Update")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        contentView.addSubview(titleLabel)

        let channelLabel = NSTextField(labelWithString: "Update channel:")
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(channelLabel)

        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.target = self
        popUp.action = #selector(updateChannelChanged(_:))
        for channel in AppSettings.UpdateChannel.allCases {
            popUp.addItem(withTitle: channel.title)
            popUp.lastItem?.representedObject = channel.rawValue
        }
        contentView.addSubview(popUp)
        updateChannelPopUp = popUp

        let displayLabel = NSTextField(labelWithString: "Menu Bar Display")
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        displayLabel.font = NSFont.boldSystemFont(ofSize: 13)
        contentView.addSubview(displayLabel)

        let integerButton = NSButton(checkboxWithTitle: "Show B/s and KB/s as integers", target: self, action: #selector(integerSmallUnitsChanged(_:)))
        integerButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(integerButton)
        integerSmallUnitsButton = integerButton

        let modePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        modePopUp.translatesAutoresizingMaskIntoConstraints = false
        modePopUp.target = self
        modePopUp.action = #selector(displayModeChanged(_:))
        AppSettings.DisplayMode.allCases.forEach { modePopUp.addItem(withTitle: $0.title); modePopUp.lastItem?.representedObject = $0.rawValue }
        contentView.addSubview(modePopUp)
        displayModePopUp = modePopUp

        let modeLabel = NSTextField(labelWithString: "Traffic:")
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(modeLabel)

        let unitPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        unitPopUp.translatesAutoresizingMaskIntoConstraints = false
        unitPopUp.target = self
        unitPopUp.action = #selector(unitModeChanged(_:))
        AppSettings.UnitMode.allCases.forEach { unitPopUp.addItem(withTitle: $0.title); unitPopUp.lastItem?.representedObject = $0.rawValue }
        contentView.addSubview(unitPopUp)
        unitModePopUp = unitPopUp

        let unitLabel = NSTextField(labelWithString: "Units:")
        unitLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(unitLabel)

        let helpLabel = NSTextField(wrappingLabelWithString: "")
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.maximumNumberOfLines = 2
        helpLabel.lineBreakMode = .byWordWrapping
        helpLabel.textColor = .secondaryLabelColor
        contentView.addSubview(helpLabel)
        updateChannelHelpLabel = helpLabel

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            channelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            channelLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            channelLabel.widthAnchor.constraint(equalToConstant: 92),
            popUp.centerYAnchor.constraint(equalTo: channelLabel.centerYAnchor),
            popUp.leadingAnchor.constraint(equalTo: channelLabel.trailingAnchor, constant: 12),
            popUp.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            helpLabel.topAnchor.constraint(equalTo: popUp.bottomAnchor, constant: 8),
            helpLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            helpLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            displayLabel.topAnchor.constraint(equalTo: helpLabel.bottomAnchor, constant: 22),
            displayLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            displayLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            modeLabel.topAnchor.constraint(equalTo: displayLabel.bottomAnchor, constant: 12),
            modeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            modeLabel.widthAnchor.constraint(equalToConstant: 92),
            modePopUp.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            modePopUp.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 12),
            modePopUp.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            unitLabel.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 14),
            unitLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            unitLabel.widthAnchor.constraint(equalTo: modeLabel.widthAnchor),
            unitPopUp.centerYAnchor.constraint(equalTo: unitLabel.centerYAnchor),
            unitPopUp.leadingAnchor.constraint(equalTo: unitLabel.trailingAnchor, constant: 12),
            unitPopUp.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            integerButton.topAnchor.constraint(equalTo: unitLabel.bottomAnchor, constant: 16),
            integerButton.leadingAnchor.constraint(equalTo: modePopUp.leadingAnchor),
            integerButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            integerButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
        ])

        settingsWindow = window
        syncSettingsControls()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func updateChannelChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        updateChannel = AppSettings.normalizedUpdateChannel(rawValue)
        syncSettingsControls()
    }

    @objc private func integerSmallUnitsChanged(_ sender: NSButton) {
        integerSmallUnits = sender.state == .on
    }

    @objc private func displayModeChanged(_ sender: NSPopUpButton) {
        displayMode = AppSettings.normalizedDisplayMode(sender.selectedItem?.representedObject as? String)
    }

    @objc private func unitModeChanged(_ sender: NSPopUpButton) {
        unitMode = AppSettings.normalizedUnitMode(sender.selectedItem?.representedObject as? String)
    }

    private func syncSettingsControls() {
        let rawValue = updateChannel.rawValue
        for item in updateChannelPopUp?.itemArray ?? [] where item.representedObject as? String == rawValue {
            updateChannelPopUp?.select(item)
            break
        }
        integerSmallUnitsButton?.state = integerSmallUnits ? .on : .off
        displayModePopUp?.selectItem(withTitle: displayMode.title)
        unitModePopUp?.selectItem(withTitle: unitMode.title)
        updateChannelHelpLabel?.stringValue = updateChannel.description
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        menu.cancelTracking()
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let releaseTag = Bundle.main.object(forInfoDictionaryKey: "NetSpeedMonitorReleaseTag") as? String
        let version = AppSettings.displayVersion(marketingVersion: appVersion, releaseTag: releaseTag)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let repo = githubRepo

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About NetSpeedMonitor"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false

        let contentView = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        contentView.material = .popover
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.wantsLayer = true
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "NetSpeedMonitor")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.isSelectable = true
        contentView.addSubview(titleLabel)

        let buildSuffix = build.map { " (Build \($0))" } ?? ""
        let versionLabel = NSTextField(labelWithString: "Version \(version)\(buildSuffix)")
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.alignment = .center
        versionLabel.isSelectable = true
        contentView.addSubview(versionLabel)

        let githubURLString = "https://github.com/\(repo)"
        let linkLabel = NSTextField(labelWithString: githubURLString)
        linkLabel.translatesAutoresizingMaskIntoConstraints = false
        linkLabel.alignment = .center
        linkLabel.isSelectable = true
        linkLabel.allowsEditingTextAttributes = true
        linkLabel.attributedStringValue = NSAttributedString(
            string: githubURLString,
            attributes: [
                .link: githubURLString,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        contentView.addSubview(linkLabel)

        let authorLabel = NSTextField(labelWithString: "Author: elegracer")
        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        authorLabel.alignment = .center
        authorLabel.isSelectable = true
        contentView.addSubview(authorLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            versionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            linkLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 6),
            linkLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            linkLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            authorLabel.topAnchor.constraint(equalTo: linkLabel.bottomAnchor, constant: 6),
            authorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            authorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            authorLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
        ])

        aboutWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        updateAutoLaunchStateFromSystem()
        renderLatestSpeeds()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        let activeIfaces = latestSpeeds.keys.sorted()
        syncInterfaceMenu(with: activeIfaces, speeds: latestSpeeds, structuralChanges: true)
    }
}
