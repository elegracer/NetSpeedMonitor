import Cocoa
import Network
import ServiceManagement
import os.log
import CryptoKit

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

    private var updateProgressWindow: NSWindow?
    private var updateTitleLabel: NSTextField?
    private var updateProgressIndicator: NSProgressIndicator?
    private var updateProgressLabel: NSTextField?
    private var updatePrimaryButton: NSButton?
    private var updateSecondaryButton: NSButton?
    private var updateProgressObservation: NSKeyValueObservation?
    private var pendingUpdateRelease: [String: Any]?
    private var preparedUpdateScript: URL?
    private var preparedUpdateWorkDir: URL?
    private var aboutWindow: NSWindow?

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

    // MARK: - Check Update

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.9"
    }

    private var githubRepo: String { "elegracer/NetSpeedMonitor" }

    @objc private func checkUpdate(_ sender: NSMenuItem) {
        // Close the menu first to avoid run loop conflict with modal alerts
        menu.cancelTracking()
        pendingUpdateRelease = nil
        preparedUpdateScript = nil
        preparedUpdateWorkDir = nil
        showUpdateWindow(title: "Checking for Updates", message: "Checking the latest GitHub release...", progress: nil)
        setUpdateButtons(primaryTitle: nil, primaryAction: nil, secondaryTitle: nil, secondaryAction: nil)
        performUpdateCheck()
    }

    private func performUpdateCheck() {
        let urlString = "https://github.com/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            showUpdateFailure("Invalid GitHub release URL.")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("NetSpeedMonitor/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    self.showUpdateFailure("Could not check for updates: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    self.showUpdateFailure("GitHub returned an unexpected response (HTTP \(status)).")
                    return
                }

                guard let finalURL = httpResponse.url,
                      finalURL.pathComponents.contains("tag"),
                      let tagName = finalURL.pathComponents.last,
                      tagName.hasPrefix("v") else {
                    self.showUpdateFailure("Could not determine the latest release version.")
                    return
                }

                let latestVersion = String(tagName.dropFirst())
                let currentVersion = self.appVersion
                let comparison = currentVersion.compare(latestVersion, options: .numeric)
                if comparison == .orderedAscending {
                    let downloadBase = "https://github.com/\(self.githubRepo)/releases/download/\(tagName)"
                    self.pendingUpdateRelease = [
                        "tag_name": tagName,
                        "assets": [[
                            "name": "NetSpeedMonitor.zip",
                            "browser_download_url": "\(downloadBase)/NetSpeedMonitor.zip",
                            "sha256_download_url": "\(downloadBase)/NetSpeedMonitor.sha256",
                        ]],
                    ]
                    self.showUpdateWindow(title: "Update Available", message: "Version \(latestVersion) is available.\nCurrent version: \(currentVersion)", progress: nil)
                    self.setUpdateButtons(primaryTitle: "Download", primaryAction: #selector(self.startPendingUpdateDownload(_:)), secondaryTitle: "Cancel", secondaryAction: #selector(self.closeUpdateWindow(_:)))
                } else if comparison == .orderedSame {
                    self.showUpdateWindow(title: "Up to Date", message: "You are running the latest version (\(currentVersion)).", progress: nil)
                    self.setUpdateButtons(primaryTitle: "OK", primaryAction: #selector(self.closeUpdateWindow(_:)), secondaryTitle: nil, secondaryAction: nil)
                } else {
                    self.showUpdateWindow(title: "Up to Date", message: "You are running version \(currentVersion), which is newer than the latest release (\(latestVersion)).", progress: nil)
                    self.setUpdateButtons(primaryTitle: "OK", primaryAction: #selector(self.closeUpdateWindow(_:)), secondaryTitle: nil, secondaryAction: nil)
                }
            }
        }
        task.resume()
    }

    @objc private func startPendingUpdateDownload(_ sender: NSButton) {
        guard let release = pendingUpdateRelease else {
            showUpdateFailure("Release data is no longer available.")
            return
        }
        setUpdateButtons(primaryTitle: nil, primaryAction: nil, secondaryTitle: nil, secondaryAction: nil)
        downloadAndInstallLatestRelease(from: release)
    }

    private func downloadAndInstallLatestRelease(from json: [String: Any]) {
        // Find the asset named NetSpeedMonitor.zip
        guard let assets = json["assets"] as? [[String: Any]] else {
            showUpdateFailure("No assets found in the release.")
            return
        }

        guard let asset = assets.first(where: { ($0["name"] as? String) == "NetSpeedMonitor.zip" }),
              let downloadURLString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLString) else {
            showUpdateFailure("NetSpeedMonitor.zip asset not found in the release.")
            return
        }

        let expectedDigest = asset["digest"] as? String
        let checksumURLString = asset["sha256_download_url"] as? String

        showUpdateWindow(title: "Downloading Update", message: "Downloading update... 0%", progress: 0)
        setUpdateButtons(primaryTitle: nil, primaryAction: nil, secondaryTitle: nil, secondaryAction: nil)

        let downloadTask = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    self.showUpdateFailure("Could not download update: \(error.localizedDescription)")
                    return
                }

                guard let tempURL = tempURL else {
                    self.showUpdateFailure("No data received.")
                    return
                }

                let fileManager = FileManager.default
                let tmpDir = fileManager.temporaryDirectory
                let unzipDir = tmpDir.appendingPathComponent("NetSpeedMonitorUpdate-\(UUID().uuidString)")

                do {
                    // Clean up any previous failed attempts
                    if fileManager.fileExists(atPath: unzipDir.path) {
                        try fileManager.removeItem(at: unzipDir)
                    }
                    try fileManager.createDirectory(at: unzipDir, withIntermediateDirectories: true)

                    // Move downloaded zip to a stable location
                    let zipPath = unzipDir.appendingPathComponent("NetSpeedMonitor.zip")
                    if fileManager.fileExists(atPath: zipPath.path) {
                        try fileManager.removeItem(at: zipPath)
                    }
                    try fileManager.moveItem(at: tempURL, to: zipPath)

                    if let expectedSHA256 = try self.expectedSHA256(from: expectedDigest, checksumURLString: checksumURLString) {
                        let actualSHA256 = try self.sha256Hex(for: zipPath)
                        guard actualSHA256 == expectedSHA256 else {
                            throw NSError(domain: "UpdateError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Downloaded update failed checksum verification"])
                        }
                    }

                    // Unzip
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    process.arguments = ["-o", zipPath.path, "-d", unzipDir.path]
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        throw NSError(domain: "UpdateError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unzip failed with status \(process.terminationStatus)"])
                    }

                    let downloadedApp = unzipDir.appendingPathComponent("NetSpeedMonitor.app")
                    guard fileManager.fileExists(atPath: downloadedApp.path) else {
                        throw NSError(domain: "UpdateError", code: 2, userInfo: [NSLocalizedDescriptionKey: "NetSpeedMonitor.app not found after unzip"])
                    }

                    guard let downloadedVersion = Bundle(url: downloadedApp)?.infoDictionary?["CFBundleShortVersionString"] as? String,
                          self.appVersion.compare(downloadedVersion, options: .numeric) != .orderedDescending else {
                        throw NSError(domain: "UpdateError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Downloaded app version is invalid"])
                    }

                    // Current app bundle path
                    let currentAppPath = Bundle.main.bundlePath

                    // Set executable permissions
                    let execPath = downloadedApp.appendingPathComponent("Contents/MacOS/NetSpeedMonitor")
                    if fileManager.fileExists(atPath: execPath.path) {
                        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execPath.path)
                    }

                    // Replace the current app with the new one
                    // We need to use a helper script because we can't overwrite a running bundle easily
                    let helperScript = unzipDir.appendingPathComponent("update.sh")
                    let quotedCurrentAppPath = self.shellQuote(currentAppPath)
                    let quotedDownloadedAppPath = self.shellQuote(downloadedApp.path)
                    let quotedUnzipDirPath = self.shellQuote(unzipDir.path)
                    let scriptContent = """
                    #!/bin/bash
                    set -euo pipefail

                    current_app=\(quotedCurrentAppPath)
                    downloaded_app=\(quotedDownloadedAppPath)
                    work_dir=\(quotedUnzipDirPath)
                    backup_app="${current_app}.backup.$(/bin/date +%s)"

                    sleep 1

                    if [ ! -d "$downloaded_app" ]; then
                        exit 10
                    fi

                    if [ -d "$current_app" ]; then
                        if ! /bin/mv "$current_app" "$backup_app"; then
                            /usr/bin/open "$current_app" || true
                            exit 12
                        fi
                    fi

                    if ! /usr/bin/ditto "$downloaded_app" "$current_app"; then
                        /bin/rm -rf "$current_app"
                        if [ -d "$backup_app" ]; then
                            /bin/mv "$backup_app" "$current_app"
                            /usr/bin/open "$current_app" || true
                        fi
                        exit 11
                    fi

                    /usr/bin/xattr -rd com.apple.quarantine "$current_app" 2>/dev/null || true
                    /bin/chmod -R u+rwX,go+rX "$current_app" 2>/dev/null || true
                    /bin/chmod +x "$current_app/Contents/MacOS/NetSpeedMonitor" 2>/dev/null || true
                    /usr/bin/codesign --verify --deep --strict "$current_app" >/dev/null 2>&1 || true

                    /bin/rm -rf "$backup_app"
                    /bin/rm -rf "$work_dir"
                    /usr/bin/open "$current_app"
                    """
                    try scriptContent.write(to: helperScript, atomically: true, encoding: .utf8)
                    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperScript.path)

                    self.preparedUpdateScript = helperScript
                    self.preparedUpdateWorkDir = unzipDir
                    self.showUpdateWindow(title: "Ready to Install", message: "Version \(downloadedVersion) has been downloaded.\nInstall now? NetSpeedMonitor will restart.", progress: nil)
                    self.setUpdateButtons(primaryTitle: "Install", primaryAction: #selector(self.installPreparedUpdate(_:)), secondaryTitle: "Cancel", secondaryAction: #selector(self.closeUpdateWindow(_:)))

                } catch {
                    self.showUpdateFailure(error.localizedDescription)
                    // Cleanup
                    try? fileManager.removeItem(at: unzipDir)
                }
            }
        }

        updateProgressObservation = downloadTask.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.updateDownloadProgress(progress.fractionCompleted)
            }
        }
        downloadTask.resume()
    }

    private func sha256Hex(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func expectedSHA256(from digest: String?, checksumURLString: String?) throws -> String? {
        if let digest, digest.hasPrefix("sha256:") {
            return String(digest.dropFirst("sha256:".count)).lowercased()
        }

        guard let checksumURLString, let checksumURL = URL(string: checksumURLString) else {
            return nil
        }

        let checksumText = try String(contentsOf: checksumURL, encoding: .utf8)
        return checksumText.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map { String($0).lowercased() }
    }

    private func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func showUpdateWindow(title: String, message: String, progress: Double?) {
        let window: NSWindow
        if let existingWindow = updateProgressWindow {
            window = existingWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Software Update"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.hasShadow = true
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            window.standardWindowButton(.closeButton)?.target = self
            window.standardWindowButton(.closeButton)?.action = #selector(closeUpdateWindow(_:))

            let contentView = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
            contentView.material = .hudWindow
            contentView.blendingMode = .behindWindow
            contentView.state = .active
            contentView.wantsLayer = true
            window.contentView = contentView

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.alignment = .center
            titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
            contentView.addSubview(titleLabel)

            let messageLabel = NSTextField(labelWithString: message)
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.alignment = .center
            messageLabel.maximumNumberOfLines = 3
            messageLabel.lineBreakMode = .byWordWrapping
            contentView.addSubview(messageLabel)

            let progressIndicator = NSProgressIndicator()
            progressIndicator.translatesAutoresizingMaskIntoConstraints = false
            progressIndicator.isIndeterminate = false
            progressIndicator.minValue = 0
            progressIndicator.maxValue = 100
            contentView.addSubview(progressIndicator)

            let primaryButton = NSButton(title: "OK", target: nil, action: nil)
            primaryButton.translatesAutoresizingMaskIntoConstraints = false
            primaryButton.bezelStyle = .rounded
            primaryButton.keyEquivalent = "\r"
            contentView.addSubview(primaryButton)

            let secondaryButton = NSButton(title: "Cancel", target: nil, action: nil)
            secondaryButton.translatesAutoresizingMaskIntoConstraints = false
            secondaryButton.bezelStyle = .rounded
            contentView.addSubview(secondaryButton)

            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
                titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
                titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
                messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
                messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
                messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
                progressIndicator.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 14),
                progressIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
                progressIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
                primaryButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
                primaryButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
                secondaryButton.trailingAnchor.constraint(equalTo: primaryButton.leadingAnchor, constant: -8),
                secondaryButton.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            ])

            updateProgressWindow = window
            updateTitleLabel = titleLabel
            updateProgressLabel = messageLabel
            updateProgressIndicator = progressIndicator
            updatePrimaryButton = primaryButton
            updateSecondaryButton = secondaryButton
            window.center()
        }

        updateTitleLabel?.stringValue = title
        updateProgressLabel?.stringValue = message
        if let progress {
            updateProgressIndicator?.isHidden = false
            updateProgressIndicator?.doubleValue = max(0, min(100, progress * 100))
        } else {
            updateProgressIndicator?.isHidden = true
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setUpdateButtons(primaryTitle: String?, primaryAction: Selector?, secondaryTitle: String?, secondaryAction: Selector?) {
        configureUpdateButton(updatePrimaryButton, title: primaryTitle, action: primaryAction)
        configureUpdateButton(updateSecondaryButton, title: secondaryTitle, action: secondaryAction)
    }

    private func configureUpdateButton(_ button: NSButton?, title: String?, action: Selector?) {
        guard let button else { return }
        guard let title, let action else {
            button.isHidden = true
            button.target = nil
            button.action = nil
            return
        }
        button.title = title
        button.target = self
        button.action = action
        button.isHidden = false
    }

    private func updateDownloadProgress(_ fractionCompleted: Double) {
        let percent = max(0, min(100, fractionCompleted * 100))
        updateProgressIndicator?.doubleValue = percent
        updateProgressLabel?.stringValue = "Downloading update... \(Int(percent))%"
    }

    private func showUpdateFailure(_ message: String) {
        updateProgressObservation?.invalidate()
        updateProgressObservation = nil
        showUpdateWindow(title: "Update Failed", message: message, progress: nil)
        setUpdateButtons(primaryTitle: "OK", primaryAction: #selector(closeUpdateWindow(_:)), secondaryTitle: nil, secondaryAction: nil)
    }

    @objc private func installPreparedUpdate(_ sender: NSButton) {
        guard let script = preparedUpdateScript else {
            showUpdateFailure("The downloaded update is no longer available.")
            return
        }

        do {
            let helperProcess = Process()
            helperProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            helperProcess.arguments = [script.path]
            try helperProcess.run()
            NSApp.terminate(nil)
        } catch {
            showUpdateFailure("Could not start installation: \(error.localizedDescription)")
        }
    }

    @objc private func closeUpdateWindow(_ sender: NSButton) {
        updateProgressObservation?.invalidate()
        updateProgressObservation = nil
        if let preparedUpdateWorkDir {
            try? FileManager.default.removeItem(at: preparedUpdateWorkDir)
        }
        pendingUpdateRelease = nil
        preparedUpdateScript = nil
        preparedUpdateWorkDir = nil
        updateProgressWindow?.close()
        updateProgressWindow = nil
        updateTitleLabel = nil
        updateProgressIndicator = nil
        updateProgressLabel = nil
        updatePrimaryButton = nil
        updateSecondaryButton = nil
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
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 170),
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
        contentView.material = .hudWindow
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

        let okButton = NSButton(title: "OK", target: self, action: #selector(closeAboutWindow(_:)))
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        contentView.addSubview(okButton)

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
            okButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            okButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        aboutWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeAboutWindow(_ sender: NSButton) {
        aboutWindow?.close()
        aboutWindow = nil
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
