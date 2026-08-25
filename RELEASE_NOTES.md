# NetSpeedMonitor Release Notes

## What's New

- Improves update installer diagnostics and restart validation.

## Fixes

- Avoids false rollback when macOS launches the updated app with extra process arguments.
- Safely writes update version details to the installer log.

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
