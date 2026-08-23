# NetSpeedMonitor Release Notes

## What's New

- Uses a single version source for local builds, CI artifacts, and releases.
- Builds releases with the macOS 26 SDK for consistent Liquid Glass controls.
- Adds automated tests for interval settings, version checks, checksums, and traffic counter wrap-around.

## Fixes

- Fixes the 60-second update interval incorrectly showing zero traffic.
- Prevents stale traffic values after a statistics read failure.
- Keeps automatic upload and download values on the same network interface.
- Moves update verification and extraction off the main thread.
- Strengthens update validation, rollback, restart checks, and failure reporting.

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
