import SwiftUI
import os.log

public var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "elegracer")

struct MenuContentView: View {
    @EnvironmentObject var menuBarState: MenuBarState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Section {
                HStack {
                    Toggle("Start at Login", isOn: $menuBarState.autoLaunchEnabled)
                        .toggleStyle(.button)
                        .onChange(of: menuBarState.autoLaunchEnabled, initial: false) {oldState, newState in
                            logger.info("Toggle::StartAtLogin: oldState：\(oldState), newState: \(newState)")
                        }
                }.fixedSize()
            }
            
            Divider()
            
            Section {
                HStack {
                    ForEach(NetSpeedUpdateInterval.allCases) { interval in
                        Toggle(
                            interval.displayName,
                            isOn: Binding(
                                get: { menuBarState.netSpeedUpdateInterval == interval },
                                set: { if $0 { menuBarState.netSpeedUpdateInterval = interval } }
                            )
                        )
                        .toggleStyle(.button)
                    }
                }
            } header: {
                Text("Update Interval")
            }
            
            Divider()
            
            Section {
                Button("Open Activity Monitor", action: onClickOpenActivityMonitor)
            }
            
            Divider()
            
            Section {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .fixedSize()
    }
    
    private func onClickOpenActivityMonitor() {
        let bundleID = "com.apple.ActivityMonitor"
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            
            NSWorkspace.shared.openApplication(at: appURL,
                                               configuration: config,
                                               completionHandler: { app, error in
                if let error = error {
                    logger.warning("Open Activity Monitor failed: \(error.localizedDescription)")
                } else {
                    logger.info("Open Activity Monitor succeeded.")
                }
            })
        } else {
            logger.warning("Cannot find Activity Monitor.")
        }
    }
}
