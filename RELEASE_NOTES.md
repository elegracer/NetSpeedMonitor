# NetSpeedMonitor v1.11

## What's New

- Improves Check Update with a single in-window flow, download progress, and install confirmation.
- Uses a GitHub release redirect flow to avoid GitHub API rate-limit failures.
- Updates About and Check Update windows with a consistent material style.

## Fixes

- Shows update failures in the update window when checking, downloading, validating, or preparing installation fails.
- Separates Check Update and About menu items to avoid incorrect menu-item status icons or indentation.

## Requirements

- macOS 14.6 or later.
- Apple silicon and Intel Macs are supported by the universal build.

## Install or Upgrade

1. Download `NetSpeedMonitor.zip` below.
2. Unzip it and move `NetSpeedMonitor.app` to `/Applications`, replacing the previous version when upgrading.
3. If macOS blocks the ad-hoc signed app, run:

```bash
sudo xattr -rd com.apple.quarantine /Applications/NetSpeedMonitor.app
```

The app is ad-hoc signed by GitHub Actions and is not notarized with an Apple Developer ID.
