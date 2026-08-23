import Cocoa
import Network
import ServiceManagement
import os.log

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "elegracer")

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
    private var intervalMenuView: IntervalMenuView!

    private var timer: Timer?
    private let netTrafficStat = NetTrafficStatReceiver()

    private var aboutWindow: NSWindow?
    private lazy var updateController = UpdateController(appVersion: appVersion, githubRepo: githubRepo)

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
        statusItem.button?.toolTip = "NetSpeedMonitor"
        statusItem.button?.setAccessibilityLabel("Network speed")

        buildMenu()
        updateAutoLaunchStateFromSystem()
        updateInterfaceCheckmarks()
        startRouteMonitoring()
        startTimer()
        updateController.showPendingErrorIfNeeded()
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

        menu.addItem(NSMenuItem.separator())

        let checkUpdateItem = NSMenuItem(title: "Check Update", action: #selector(checkUpdate(_:)), keyEquivalent: "")
        checkUpdateItem.target = self
        configurePlainMenuItem(checkUpdateItem)
        menu.addItem(checkUpdateItem)

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
            tick()
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
        let interval = TimeInterval(updateInterval)
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
        guard let statMap = netTrafficStat.getNetTrafficStatMap() else {
            latestSpeeds = [:]
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateIcon(with: [:])
                self.syncInterfaceMenu(with: [], speeds: [:], structuralChanges: !self.isMenuOpen)
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
            guard let v = interfaceViewsMap[name] else { continue }
            guard let sp = speeds[name] else {
                v.speedText = "↓  0.00  B/s  ↑  0.00  B/s"
                continue
            }
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
            } else if let sp = speeds.values.max(by: { ($0.down + $0.up) < ($1.down + $1.up) }) {
                downBps = sp.down
                upBps = sp.up
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

    // MARK: - Check Update

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var githubRepo: String { "elegracer/NetSpeedMonitor" }

    @objc private func checkUpdate(_ sender: NSMenuItem) {
        menu.cancelTracking()
        updateController.start()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        menu.cancelTracking()
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let version = appVersion
        let repo = githubRepo

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
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

        let versionLabel = NSTextField(labelWithString: "Version \(version)")
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
