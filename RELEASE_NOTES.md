# NetSpeedMonitor Release Notes

## What's New

- Removes App Sandbox from the ad-hoc release build so the updater helper can replace the app in `/Applications`.

## Fixes

- Fixes update failures where macOS denied app replacement with `Operation not permitted`.

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
