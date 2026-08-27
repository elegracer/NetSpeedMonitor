import Foundation

struct PreparedUpdate {
    let scriptURL: URL
    let workDirectory: URL
    let version: String
}

final class UpdateInstaller {
    typealias SignatureVerifier = (_ signatureBase64: String, _ releaseTag: String, _ sha256: String) -> Bool
    private static let maximumExtractedSize: UInt64 = 500 * 1024 * 1024
    private let currentVersion: String
    private let currentReleaseTag: String
    private let currentAppPath: String
    private let currentProcessID: Int32
    private let signatureVerifier: SignatureVerifier

    init(currentVersion: String, currentReleaseTag: String, currentAppPath: String, currentProcessID: Int32, signatureVerifier: @escaping SignatureVerifier = ReleaseSignature.verify) {
        self.currentVersion = currentVersion
        self.currentReleaseTag = currentReleaseTag
        self.currentAppPath = currentAppPath
        self.currentProcessID = currentProcessID
        self.signatureVerifier = signatureVerifier
    }

    func prepare(
        downloadedZip: URL,
        workDirectory: URL,
        expectedDigest: String?,
        signatureBase64: String,
        targetReleaseTag: String
    ) throws -> PreparedUpdate {
        let fileManager = FileManager.default
        do {
            guard let expectedSHA256 = UpdateValidation.expectedSHA256(digest: expectedDigest, checksumText: nil) else {
                throw updateError(3, "The release does not provide a checksum.")
            }
            guard signatureVerifier(signatureBase64, targetReleaseTag, expectedSHA256) else {
                throw updateError(3, "The release signature is missing or invalid.")
            }
            guard try UpdateValidation.matchesSHA256(fileURL: downloadedZip, expected: expectedSHA256) else {
                throw updateError(3, "Downloaded update failed checksum verification.")
            }

            let extractDirectory = workDirectory.appendingPathComponent("Extracted")
            try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
            try validateArchiveEntries(downloadedZip)
            try runProcess("/usr/bin/unzip", arguments: ["-q", "-o", downloadedZip.path, "-d", extractDirectory.path], errorMessage: "Could not extract the update.")

            let downloadedApp = extractDirectory.appendingPathComponent("NetSpeedMonitor.app")
            guard fileManager.fileExists(atPath: downloadedApp.path) else {
                throw updateError(2, "NetSpeedMonitor.app was not found in the update.")
            }
            let extractedContents = try fileManager.contentsOfDirectory(at: extractDirectory, includingPropertiesForKeys: nil)
            guard extractedContents.count == 1, extractedContents[0].lastPathComponent == "NetSpeedMonitor.app" else {
                throw updateError(2, "The update archive contains unexpected top-level files.")
            }
            var extractedSize: UInt64 = 0
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
            guard let enumerator = fileManager.enumerator(at: downloadedApp, includingPropertiesForKeys: keys) else {
                throw updateError(2, "Could not inspect the extracted update.")
            }
            for case let itemURL as URL in enumerator {
                let values = try itemURL.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true {
                    throw updateError(2, "The update contains an unsupported symbolic link.")
                }
                if values.isRegularFile == true {
                    extractedSize += UInt64(values.fileSize ?? 0)
                    if extractedSize > Self.maximumExtractedSize {
                        throw updateError(2, "The extracted update is too large.")
                    }
                }
            }
            let downloadedBundle = Bundle(url: downloadedApp)
            guard let downloadedVersion = downloadedBundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
                  downloadedVersion == AppSettings.appVersion(fromReleaseTag: targetReleaseTag),
                  AppSettings.compareVersions(currentReleaseTag, targetReleaseTag) == .orderedAscending else {
                throw updateError(4, "The downloaded app version does not match the selected release.")
            }
            guard downloadedBundle?.bundleIdentifier == "com.elegracer.NetSpeedMonitor" else {
                throw updateError(5, "The downloaded app has an unexpected bundle identifier.")
            }
            guard downloadedBundle?.object(forInfoDictionaryKey: "NetSpeedMonitorReleaseTag") as? String == targetReleaseTag else {
                throw updateError(5, "The downloaded app does not identify itself as the selected release.")
            }

            let executable = downloadedApp.appendingPathComponent("Contents/MacOS/NetSpeedMonitor")
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            try runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", downloadedApp.path], errorMessage: "The downloaded app failed signature verification.")

            let helperScript = workDirectory.appendingPathComponent("update.sh")
            let errorFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.elegracer.NetSpeedMonitor/update-error.txt")
            let logFile = errorFile.deletingLastPathComponent().appendingPathComponent("update.log")
            let scriptContent = """
            #!/bin/bash
            set -u

            current_app=\(shellQuote(currentAppPath))
            downloaded_app=\(shellQuote(downloadedApp.path))
            work_dir=\(shellQuote(workDirectory.path))
            backup_app="${current_app}.backup.$(/bin/date +%s)"
            error_file=\(shellQuote(errorFile.path))
            log_file=\(shellQuote(logFile.path))
            old_pid=\(currentProcessID)

            /bin/mkdir -p "$(/usr/bin/dirname "$log_file")"
            exec >>"$log_file" 2>&1
            /usr/bin/printf '%s\n' \(shellQuote("Starting update from \(currentVersion) to \(downloadedVersion)"))

            report_failure() {
                /bin/mkdir -p "$(/usr/bin/dirname "$error_file")"
                /usr/bin/printf '%s\n' "$1" > "$error_file"
            }

            current_parent=$(/usr/bin/dirname "$current_app")
            case "$current_parent" in
              /Applications|"$HOME"/Applications) ;;
              *) report_failure "Automatic update is only supported for applications installed in an Applications folder."; exit 2 ;;
            esac

            fail_before_replace() {
                report_failure "$1"
                /usr/bin/open "$current_app" >/dev/null 2>&1 || true
                /bin/rm -rf "$work_dir"
                exit 1
            }

            rollback() {
                report_failure "$1"
                /bin/rm -rf "$current_app"
                if [ -d "$backup_app" ]; then
                    /bin/mv "$backup_app" "$current_app"
                    /usr/bin/open "$current_app" >/dev/null 2>&1 || true
                fi
                /bin/rm -rf "$work_dir"
                exit 1
            }

            fail_after_install() {
                if [ -d "$backup_app" ]; then
                    rollback "$1"
                fi
                report_failure "$1"
                /usr/bin/open "$current_app" >/dev/null 2>&1 || true
                /bin/rm -rf "$work_dir"
                exit 1
            }

            updated_app_is_running() {
                for pid in $(/usr/bin/pgrep -x NetSpeedMonitor 2>/dev/null); do
                    command_path=$(/bin/ps -ww -p "$pid" -o comm= 2>/dev/null || true)
                    if [ "$command_path" = "$current_app/Contents/MacOS/NetSpeedMonitor" ]; then
                        return 0
                    fi
                done
                return 1
            }

            for attempt in {1..80}; do
                if ! /bin/kill -0 "$old_pid" 2>/dev/null; then
                    break
                fi
                sleep 0.25
            done
            if /bin/kill -0 "$old_pid" 2>/dev/null; then
                fail_before_replace "NetSpeedMonitor did not quit before installation."
            fi

            [ -d "$downloaded_app" ] || {
                fail_before_replace "The downloaded application disappeared before installation."
            }
            /usr/bin/codesign --verify --deep --strict "$downloaded_app" >/dev/null 2>&1 || {
                fail_before_replace "The downloaded application failed signature verification."
            }

            if [ -d "$current_app" ]; then
                echo "Backing up $current_app"
                move_error=$(/bin/mv "$current_app" "$backup_app" 2>&1) || {
                    fail_before_replace "The installed application could not be backed up: $move_error"
                }
            fi

            echo "Installing $downloaded_app"
            /usr/bin/ditto "$downloaded_app" "$current_app" || rollback "The new application could not be copied."
            /bin/chmod -R u+rwX,go+rX "$current_app" 2>/dev/null || true
            /bin/chmod +x "$current_app/Contents/MacOS/NetSpeedMonitor" 2>/dev/null || true
            /usr/bin/codesign --verify --deep --strict "$current_app" >/dev/null 2>&1 || fail_after_install "The installed update failed signature verification."
            /usr/bin/open "$current_app" >/dev/null 2>&1 || fail_after_install "The updated application could not be restarted."
            launched=0
            for attempt in {1..10}; do
                if updated_app_is_running; then
                    launched=1
                    break
                fi
                sleep 0.5
            done
            [ "$launched" -eq 1 ] || fail_after_install "The updated application exited immediately after launch."

            echo "Update completed successfully"
            /bin/rm -f "$error_file"
            /bin/rm -rf "$backup_app"
            /bin/rm -rf "$work_dir"
            """
            try scriptContent.write(to: helperScript, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperScript.path)
            return PreparedUpdate(scriptURL: helperScript, workDirectory: workDirectory, version: targetReleaseTag)
        } catch {
            try? fileManager.removeItem(at: workDirectory)
            throw error
        }
    }

    private func runProcess(_ executablePath: String, arguments: [String], errorMessage: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw updateError(Int(process.terminationStatus), errorMessage)
        }
    }

    private func validateArchiveEntries(_ archive: URL) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archive.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 5 * 1024 * 1024,
              let listing = String(data: data, encoding: .utf8) else {
            throw updateError(2, "Could not inspect the update archive.")
        }
        let entries = listing.split(separator: "\n", omittingEmptySubsequences: true)
        guard !entries.isEmpty, entries.count <= 10_000 else {
            throw updateError(2, "The update archive has an invalid number of files.")
        }
        for entrySlice in entries {
            let entry = String(entrySlice)
            let components = entry.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.hasPrefix("/"), !components.contains(".."),
                  entry == "NetSpeedMonitor.app" || entry.hasPrefix("NetSpeedMonitor.app/") else {
                throw updateError(2, "The update archive contains an unsafe path.")
            }
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func updateError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "UpdateError", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
