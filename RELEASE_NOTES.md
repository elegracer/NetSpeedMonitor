# NetSpeedMonitor v1.12

## What's New

- Replaces Update Interval menu choices with a multi-stop slider from 1 to 60 seconds.
- Adds clear interval labels and a live selected-value indicator.
- Refines About and Check Update windows with a more native macOS material style.

## Fixes

- Improves interface-rate readability and menu spacing.
- Prevents closed update checks from reopening their window when an asynchronous request finishes.

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
