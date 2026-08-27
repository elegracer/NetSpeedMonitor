# NetSpeedMonitor Release Notes

## What's New

- Improves the Statistics and Settings layouts with clearer labels and responsive sizing.
- Keeps the Statistics window live while traffic samples continue to arrive and adds session averages.
- Adds configurable upload/download visibility and byte- or bit-based speed units.
- Adds bounded session history, peak rates, transferred totals, and a traffic chart.
- Adds friendly interface names, IPv4/IPv6 route detection, and clearer unavailable states.
- Adds automatic update checks with stable and pre-release channels.
- Reduces polling frequency in Low Power Mode and resets stale samples after wake.

## Fixes

- Shows the complete pre-release version, such as `1.21-beta.2`, in About.
- Uses one shared chart scale so upload and download rates can be compared visually.
- Uses 64-bit interface counters and handles counter resets and invalid route messages safely.
- Measures menu-bar text dynamically with monospaced fonts to avoid wrapping or truncation.
- Verifies update archives with a pinned Ed25519 public key, SHA-256 digest, bundle metadata, code signing, and archive safety checks.
- Restricts automatic replacement to applications installed directly in `/Applications` or `~/Applications`.

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
