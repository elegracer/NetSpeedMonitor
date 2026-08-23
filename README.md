# NetSpeedMonitor

NetSpeedMonitor is a minimal menu bar app for macOS 14.6 and later. It reads per-interface byte counters with `sysctl` and displays current upload and download rates.

## Features

1. Start at login.
2. Choose a 1s, 2s, 5s, 10s, or 30s update interval.
3. Open Activity Monitor directly from the menu.
4. Automatically follow the effective network interface when a VPN connects or disconnects.
5. Inspect all active interfaces or pin the display to a specific interface.

## Install

1. Download `NetSpeedMonitor.zip` from the latest GitHub release.
2. Unzip it and move `NetSpeedMonitor.app` to `/Applications`.
3. Open the app. If macOS blocks the ad-hoc signed build, run:

```bash
sudo xattr -rd com.apple.quarantine /Applications/NetSpeedMonitor.app
```

To upgrade, quit NetSpeedMonitor and replace the existing app in `/Applications`.

## VPN Behavior

Automatic mode asks the macOS Network framework which interface carries traffic to a public IPv4 endpoint. This follows full-tunnel and route-based VPN changes without polling. Split-tunnel VPNs can route different destinations over different interfaces, so no single interface can represent every flow.

Per-process traffic monitoring is intentionally not included because continuously running `nettop` has significantly higher CPU overhead.

## Screenshot

![](./screenshot.png)
