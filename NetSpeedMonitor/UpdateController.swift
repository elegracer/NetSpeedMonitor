import Cocoa

final class UpdateController: NSObject {
    private static let maximumDownloadSize: Int64 = 200 * 1024 * 1024
    private let appVersion: String
    private let githubRepo: String
    private let updateChannelProvider: () -> AppSettings.UpdateChannel
    private let releaseProvider = ReleaseProvider()
    private var currentReleaseVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "NetSpeedMonitorReleaseTag") as? String ?? appVersion
    }
    private lazy var installer = UpdateInstaller(
        currentVersion: appVersion,
        currentReleaseTag: currentReleaseVersion,
        currentAppPath: Bundle.main.bundlePath,
        currentProcessID: ProcessInfo.processInfo.processIdentifier
    )

    private var window: NSWindow?
    private var titleLabel: NSTextField?
    private var messageLabel: NSTextField?
    private var progressIndicator: NSProgressIndicator?
    private var primaryButton: NSButton?
    private var secondaryButton: NSButton?
    private var progressObservation: NSKeyValueObservation?
    private var checkTask: URLSessionDataTask?
    private var downloadTask: URLSessionDownloadTask?
    private var sessionID: UUID?
    private var pendingRelease: ReleaseDescriptor?
    private var preparedUpdate: PreparedUpdate?
    private var silentCheck = false
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private static let lastAutomaticCheckKey = "NetSpeedLastAutomaticUpdateCheck"

    init(appVersion: String, githubRepo: String, updateChannelProvider: @escaping () -> AppSettings.UpdateChannel) {
        self.appVersion = appVersion
        self.githubRepo = githubRepo
        self.updateChannelProvider = updateChannelProvider
    }

    func start() {
        start(silent: false)
    }

    private func start(silent: Bool) {
        resetSession(closeWindow: false)
        silentCheck = silent
        sessionID = UUID()
        let channel = updateChannelProvider()
        if !silent {
            showWindow(title: "Checking for Updates", message: "Checking GitHub \(channel.title.lowercased())...", progress: nil)
            setButtons(primaryTitle: nil, primaryAction: nil, secondaryTitle: nil, secondaryAction: nil)
        }
        checkReleases(includePrereleases: channel == .prerelease)
    }

    func checkAutomaticallyIfNeeded(now: Date = Date()) {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: Self.lastAutomaticCheckKey) as? Date, now.timeIntervalSince(last) < Self.automaticCheckInterval { return }
        defaults.set(now, forKey: Self.lastAutomaticCheckKey)
        start(silent: true)
    }

    func showPendingErrorIfNeeded() {
        let errorFile = updateErrorFile
        guard let message = try? String(contentsOf: errorFile, encoding: .utf8), !message.isEmpty else { return }
        try? FileManager.default.removeItem(at: errorFile)
        sessionID = UUID()
        DispatchQueue.main.async { [weak self] in
            self?.showFailure(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func checkReleases(includePrereleases: Bool) {
        guard let sessionID else { return }
        if let retry = releaseProvider.retryAfter(repo: githubRepo), retry > Date() {
            if silentCheck { resetSession(closeWindow: false) }
            else { showFailure("GitHub rate limit reached. Try again after \(retry.formatted()).") }
            return
        }
        checkTask = releaseProvider.fetch(repo: githubRepo, includePrereleases: includePrereleases, userAgent: "NetSpeedMonitor/\(appVersion)") { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.sessionID == sessionID else { return }
                switch result {
                case .success(let release):
                    let channel = includePrereleases ? AppSettings.UpdateChannel.prerelease : .stable
                    self.handleSelectedRelease(release, channelTitle: channel.title)
                case .failure(let error):
                    if self.silentCheck {
                        logger.warning("Automatic update check failed: \(error.localizedDescription)")
                        self.resetSession(closeWindow: false)
                    }
                    else { self.showFailure(error.localizedDescription) }
                }
            }
        }
    }

    private func handleSelectedRelease(_ release: ReleaseDescriptor, channelTitle: String) {
        switch AppSettings.compareVersions(currentReleaseVersion, release.tag) {
        case .orderedAscending:
            pendingRelease = release
            let releaseType = release.isPrerelease ? "pre-release" : "release"
            showWindow(title: "Update Available", message: "Version \(release.tag) (\(releaseType)) is available.\nCurrent version: \(currentReleaseVersion)", progress: nil)
            setButtons(primaryTitle: "Download", primaryAction: #selector(startDownload(_:)), secondaryTitle: "Cancel", secondaryAction: #selector(close(_:)))
        case .orderedSame:
            if silentCheck { resetSession(closeWindow: false); return }
            showWindow(title: "Up to Date", message: "You are running the latest version for \(channelTitle.lowercased()) (\(currentReleaseVersion)).", progress: nil)
            setButtons(primaryTitle: "OK", primaryAction: #selector(close(_:)), secondaryTitle: nil, secondaryAction: nil)
        case .orderedDescending:
            if silentCheck { resetSession(closeWindow: false); return }
            showWindow(title: "Up to Date", message: "You are running version \(currentReleaseVersion), which is newer than the latest release (\(release.tag)).", progress: nil)
            setButtons(primaryTitle: "OK", primaryAction: #selector(close(_:)), secondaryTitle: nil, secondaryAction: nil)
        }
    }

    @objc private func startDownload(_ sender: NSButton) {
        guard let release = pendingRelease, let sessionID else {
            showFailure("Release data is no longer available.")
            return
        }
        showWindow(title: "Downloading Update", message: "Downloading update... 0%", progress: 0)
        setButtons(primaryTitle: nil, primaryAction: nil, secondaryTitle: nil, secondaryAction: nil)

        var signatureRequest = URLRequest(url: release.signatureURL)
        signatureRequest.timeoutInterval = 15
        let signatureTask = URLSession.shared.dataTask(with: signatureRequest) { [weak self] signatureData, signatureResponse, signatureError in
            guard let self else { return }
            guard signatureError == nil,
                  let signatureResponse = signatureResponse as? HTTPURLResponse,
                  (200...299).contains(signatureResponse.statusCode),
                  let signatureData, signatureData.count <= 1024,
                  let signatureBase64 = String(data: signatureData, encoding: .utf8) else {
                self.onMain(sessionID) { $0.showFailure("Could not download a valid release signature.") }
                return
            }
            self.download(release: release, signatureBase64: signatureBase64, sessionID: sessionID)
        }
        checkTask = signatureTask
        signatureTask.resume()
    }

    private func download(release: ReleaseDescriptor, signatureBase64: String, sessionID: UUID) {
        let task = URLSession.shared.downloadTask(with: release.downloadURL) { [weak self] tempURL, response, error in
            guard let self else { return }
            if let error {
                self.onMain(sessionID) { $0.showFailure("Could not download update: \(error.localizedDescription)") }
                return
            }
            guard let tempURL else {
                self.onMain(sessionID) { $0.showFailure("No data received.") }
                return
            }
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  response.expectedContentLength <= Self.maximumDownloadSize else {
                self.onMain(sessionID) { $0.showFailure("GitHub returned an invalid or oversized update.") }
                return
            }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
                  let fileSize = attributes[.size] as? NSNumber,
                  fileSize.int64Value > 0, fileSize.int64Value <= Self.maximumDownloadSize else {
                self.onMain(sessionID) { $0.showFailure("The downloaded update is empty or too large.") }
                return
            }

            let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("NetSpeedMonitorUpdate-\(UUID().uuidString)")
            let stableZip = workDirectory.appendingPathComponent("NetSpeedMonitor.zip")
            do {
                try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: tempURL, to: stableZip)
            } catch {
                try? FileManager.default.removeItem(at: workDirectory)
                self.onMain(sessionID) { $0.showFailure("Could not save the downloaded update: \(error.localizedDescription)") }
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result {
                    try self.installer.prepare(
                        downloadedZip: stableZip,
                        workDirectory: workDirectory,
                        expectedDigest: release.digest,
                        signatureBase64: signatureBase64,
                        targetReleaseTag: release.tag
                    )
                }
                self.onMain(sessionID) { controller in
                    switch result {
                    case .success(let prepared):
                        controller.preparedUpdate = prepared
                        controller.showWindow(title: "Ready to Install", message: "Version \(prepared.version) has been downloaded.\nInstall now? NetSpeedMonitor will restart.", progress: nil)
                        controller.setButtons(primaryTitle: "Install", primaryAction: #selector(controller.install(_:)), secondaryTitle: "Cancel", secondaryAction: #selector(controller.close(_:)))
                    case .failure(let error):
                        controller.showFailure(error.localizedDescription)
                    }
                } onExpired: {
                    try? FileManager.default.removeItem(at: workDirectory)
                }
            }
        }

        progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            self?.onMain(sessionID) { $0.updateProgress(progress.fractionCompleted) }
        }
        downloadTask = task
        task.resume()
    }

    private func onMain(_ expectedSessionID: UUID, action: @escaping (UpdateController) -> Void, onExpired: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionID == expectedSessionID else {
                onExpired?()
                return
            }
            action(self)
        }
    }

    @objc private func install(_ sender: NSButton) {
        guard let preparedUpdate else {
            showFailure("The downloaded update is no longer available.")
            return
        }
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            process.arguments = ["/bin/bash", preparedUpdate.scriptURL.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            NSApp.terminate(nil)
        } catch {
            showFailure("Could not start installation: \(error.localizedDescription)")
        }
    }

    private func showWindow(title: String, message: String, progress: Double?) {
        let updateWindow: NSWindow
        if let window {
            updateWindow = window
        } else {
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            newWindow.title = "Software Update"
            newWindow.isMovableByWindowBackground = false
            newWindow.isReleasedWhenClosed = false
            newWindow.standardWindowButton(.closeButton)?.target = self
            newWindow.standardWindowButton(.closeButton)?.action = #selector(close(_:))

            let contentView = NSVisualEffectView(frame: newWindow.contentView?.bounds ?? .zero)
            contentView.material = .popover
            contentView.blendingMode = .behindWindow
            contentView.state = .active
            newWindow.contentView = contentView

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.alignment = .center
            titleLabel.font = .boldSystemFont(ofSize: 15)
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
            primaryButton.keyEquivalent = "\r"
            contentView.addSubview(primaryButton)

            let secondaryButton = NSButton(title: "Cancel", target: nil, action: nil)
            secondaryButton.translatesAutoresizingMaskIntoConstraints = false
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

            window = newWindow
            self.titleLabel = titleLabel
            self.messageLabel = messageLabel
            self.progressIndicator = progressIndicator
            self.primaryButton = primaryButton
            self.secondaryButton = secondaryButton
            newWindow.center()
            updateWindow = newWindow
        }

        titleLabel?.stringValue = title
        messageLabel?.stringValue = message
        progressIndicator?.isHidden = progress == nil
        if let progress { progressIndicator?.doubleValue = max(0, min(100, progress * 100)) }
        updateWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setButtons(primaryTitle: String?, primaryAction: Selector?, secondaryTitle: String?, secondaryAction: Selector?) {
        configureButton(primaryButton, title: primaryTitle, action: primaryAction)
        configureButton(secondaryButton, title: secondaryTitle, action: secondaryAction)
    }

    private func configureButton(_ button: NSButton?, title: String?, action: Selector?) {
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

    private func updateProgress(_ fraction: Double) {
        let percent = max(0, min(100, fraction * 100))
        progressIndicator?.doubleValue = percent
        messageLabel?.stringValue = "Downloading update... \(Int(percent))%"
    }

    private func showFailure(_ message: String) {
        progressObservation?.invalidate()
        progressObservation = nil
        showWindow(title: "Update Failed", message: message, progress: nil)
        setButtons(primaryTitle: "OK", primaryAction: #selector(close(_:)), secondaryTitle: nil, secondaryAction: nil)
    }

    @objc private func close(_ sender: NSButton) {
        resetSession(closeWindow: true)
    }

    private func resetSession(closeWindow: Bool) {
        checkTask?.cancel()
        checkTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation?.invalidate()
        progressObservation = nil
        if let preparedUpdate { try? FileManager.default.removeItem(at: preparedUpdate.workDirectory) }
        sessionID = nil
        pendingRelease = nil
        preparedUpdate = nil
        silentCheck = false
        if closeWindow {
            window?.close()
            window = nil
            titleLabel = nil
            messageLabel = nil
            progressIndicator = nil
            primaryButton = nil
            secondaryButton = nil
        }
    }

    private var updateErrorFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.elegracer.NetSpeedMonitor/update-error.txt")
    }
}
