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
        performUpdateCheck()
    }

    private func performUpdateCheck() {
        let urlString = "https://api.github.com/repos/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            showAlert(title: "Update Check Failed", message: "Invalid GitHub API URL.")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    self.showAlert(title: "Update Check Failed", message: "Network error: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let data = data else {
                    self.showAlert(title: "Update Check Failed", message: "Unexpected server response.")
                    return
                }

                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let tagName = json["tag_name"] as? String else {
                        self.showAlert(title: "Update Check Failed", message: "Failed to parse release data.")
                        return
                    }

                    let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                    let currentVersion = self.appVersion

                    let comparison = currentVersion.compare(latestVersion, options: .numeric)
                    if comparison == .orderedAscending {
                        // New version available — ask to download
                        let shouldUpdate = self.showQuestionAlert(
                            title: "Update Available",
                            message: "Version \(latestVersion) is available (current: \(currentVersion)).\nDownload and install now?"
                        )
                        if shouldUpdate {
                            self.downloadAndInstallLatestRelease(from: json)
                        }
                    } else if comparison == .orderedSame {
                        self.showAlert(title: "Up to Date", message: "You are running the latest version (\(currentVersion)).")
                    } else {
                        self.showAlert(title: "Up to Date",
                                       message: "You are running version \(currentVersion), which is newer than the latest release (\(latestVersion)).")
                    }
                } catch {
                    self.showAlert(title: "Update Check Failed", message: "Parse error: \(error.localizedDescription)")
                }
            }
        }
        task.resume()
    }

    private func downloadAndInstallLatestRelease(from json: [String: Any]) {
        // Find the asset named NetSpeedMonitor.zip
        guard let assets = json["assets"] as? [[String: Any]] else {
            showAlert(title: "Update Failed", message: "No assets found in the release.")
            return
        }

        guard let asset = assets.first(where: { ($0["name"] as? String) == "NetSpeedMonitor.zip" }),
              let downloadURLString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLString) else {
            showAlert(title: "Update Failed", message: "NetSpeedMonitor.zip asset not found in the release.")
            return
        }

        let expectedDigest = asset["digest"] as? String

        let downloadTask = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    self.showAlert(title: "Download Failed", message: "Could not download update: \(error.localizedDescription)")
                    return
                }

                guard let tempURL = tempURL else {
                    self.showAlert(title: "Download Failed", message: "No data received.")
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

                    if let expectedDigest, expectedDigest.hasPrefix("sha256:") {
                        let expectedSHA256 = String(expectedDigest.dropFirst("sha256:".count)).lowercased()
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

                    // Launch the helper script and quit
                    let helperProcess = Process()
                    helperProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                    helperProcess.arguments = [helperScript.path]
                    try helperProcess.run()

                    // Quit the app
                    NSApp.terminate(nil)

                } catch {
                    self.showAlert(title: "Update Failed", message: error.localizedDescription)
                    // Cleanup
                    try? fileManager.removeItem(at: unzipDir)
                }
            }
        }
        downloadTask.resume()
    }

    private func sha256Hex(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        menu.cancelTracking()
        let version = appVersion
        let repo = githubRepo

        let alert = NSAlert()
        alert.messageText = "NetSpeedMonitor"
        alert.informativeText = "Version \(version)\n\nA minimal menu bar network speed monitor for macOS.\n\nGitHub: https://github.com/\(repo)\nAuthor: elegracer"
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Alert Helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.icon = NSImage(size: .zero)
        alert.runModal()
    }

    private func showQuestionAlert(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        alert.icon = NSImage(size: .zero)
        return alert.runModal() == .alertFirstButtonReturn
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
