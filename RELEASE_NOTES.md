# NetSpeedMonitor v1.10

## What's New

- Adds Check Update to install newer GitHub releases from the menu.
- Adds About with the current version, GitHub link, and author.
- Automatically follows the effective network interface when a VPN connects or disconnects.
- Shows the interface selected by Auto mode, for example `Auto (utun4)`.
- Adds an interface submenu with live upload and download rates.
- Allows pinning the status display to a specific interface.
- Replaces the SwiftUI menu with an AppKit implementation.

## Fixes

- Fixes incorrect or zero traffic readings when a VPN changes the active route.
- Removes stale interfaces when they disappear.
- Correctly handles both download and upload 32-bit byte-counter wrap-around.
- Avoids changing menu structure while the menu is open.

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
