From v1.8, the UI is built using SwiftUI, on macOS 15, with minimum system version macOS 14.6.

Since I haven't successfully built it with lower version of github action runner images, it is what it is now. Later if I have the chance, I would make it compatible with lower version of macOS.

Any PR for feature enhancement or compatibility improvement is welcomed!

---

Now this app is automatically built with github actions. So it may require some processing before running.
Run the following command to make the app runnable.

```bash
sudo xattr -rd com.apple.quarantine ./NetSpeedMonitor.app
```
