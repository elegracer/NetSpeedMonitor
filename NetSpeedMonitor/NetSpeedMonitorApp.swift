import SwiftUI

@main
struct NetSpeedMonitorApp: App {
    @StateObject private var menuBarState = MenuBarState()
    
    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(menuBarState)
        } label: {
            Image(nsImage: menuBarState.currentIcon)
                .tag("MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)
    }
}
