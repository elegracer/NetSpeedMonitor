import Foundation

struct PreparedUpdate {
    let scriptURL: URL
    let workDirectory: URL
    let version: String
}

final class UpdateInstaller {
    private let currentVersion: String
    private let currentAppPath: String
    private let currentProcessID: Int32

    init(currentVersion: String, currentAppPath: String, currentProcessID: Int32) {
        self.currentVersion = currentVersion
        self.currentAppPath = currentAppPath
        self.currentProcessID = currentProcessID
    }

    func prepare(
        downloadedZip: URL,
        workDirectory: URL,
        expectedDigest: String?,
        checksumURLString: String?
    ) throws -> PreparedUpdate {
        let fileManager = FileManager.default
        do {
            let checksumText: String?
            if expectedDigest == nil, let checksumURLString, let checksumURL = URL(string: checksumURLString) {
                checksumText = try String(contentsOf: checksumURL, encoding: .utf8)
            } else {
                checksumText = nil
            }
            guard let expectedSHA256 = UpdateValidation.expectedSHA256(digest: expectedDigest, checksumText: checksumText) else {
                throw updateError(3, "The release does not provide a checksum.")
            }
            guard UpdateValidation.matchesSHA256(data: try Data(contentsOf: downloadedZip), expected: expectedSHA256) else {
                throw updateError(3, "Downloaded update failed checksum verification.")
            }

            let extractDirectory = workDirectory.appendingPathComponent("Extracted")
            try fileManager.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
            try runProcess("/usr/bin/unzip", arguments: ["-q", "-o", downloadedZip.path, "-d", extractDirectory.path], errorMessage: "Could not extract the update.")

            let downloadedApp = extractDirectory.appendingPathComponent("NetSpeedMonitor.app")
            guard fileManager.fileExists(atPath: downloadedApp.path) else {
                throw updateError(2, "NetSpeedMonitor.app was not found in the update.")
            }
            guard let downloadedVersion = Bundle(url: downloadedApp)?.infoDictionary?["CFBundleShortVersionString"] as? String,
                  AppSettings.compareVersions(currentVersion, downloadedVersion) == .orderedAscending else {
                throw updateError(4, "The downloaded app is not newer than the installed version.")
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

            install_in_place_without_backup() {
                echo "Backup move failed; trying in-place rsync replacement"
                if /usr/bin/rsync -a --delete "$downloaded_app/" "$current_app/"; then
                    return 0
                fi
                return 1
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
                    echo "Backup move failed: $move_error"
                    install_in_place_without_backup || {
                        report_failure "The installed application could not be replaced: $move_error"
                        /usr/bin/open "$current_app" >/dev/null 2>&1 || true
                        /bin/rm -rf "$work_dir"
                        exit 12
                    }
                    installed_without_backup=1
                }
            fi

            if [ "${installed_without_backup:-0}" != "1" ]; then
                echo "Installing $downloaded_app"
                /usr/bin/ditto "$downloaded_app" "$current_app" || rollback "The new application could not be copied."
            fi
            /usr/bin/xattr -rd com.apple.quarantine "$current_app" 2>/dev/null || true
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
            return PreparedUpdate(scriptURL: helperScript, workDirectory: workDirectory, version: downloadedVersion)
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

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func updateError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "UpdateError", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
