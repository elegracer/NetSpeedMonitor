# NetSpeedMonitor Release Notes

## What's New

- Adds persistent update installation logging for diagnostics.

## Fixes

- Waits for the running app process to exit before replacing the app bundle.
- Runs the installer independently so it continues after NetSpeedMonitor quits.
- Verifies the exact updated app process starts and rolls back on failure.

## Requirements

- macOS 26 or later.
- Apple silicon and Intel Macs are supported by the universal build.

## Install or Upgrade

1. Download `NetSpeedMonitor.zip` below.
2. Unzip it and move `NetSpeedMonitor.app` to `/Applications`, replacing the previous version when upgrading.
3. If macOS blocks the ad-hoc signed app, run:

```bash
sudo xattr -rd com.apple.quarantine /Applications/NetSpeedMonitor.app
```

The app is ad-hoc signed by GitHub Actions and is not notarized with an Apple Developer ID.
