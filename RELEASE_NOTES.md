# NetSpeedMonitor Release Notes

## What's New

- Uses GitHub web release pages for both official and pre-release update checks to avoid anonymous API rate limits.

## Fixes

- Keeps the default update channel on official releases only, while allowing testers to opt in to pre-release checks without calling `api.github.com`.

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
