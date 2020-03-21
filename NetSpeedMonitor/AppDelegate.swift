//
//  AppDelegate.swift
//  NetSpeedMonitor
//
//  Created by Huang Kai on 2019/3/10.
//  Copyright © 2019 Team Elegracer. All rights reserved.
//

import Cocoa
import ServiceManagement
import SystemConfiguration

extension Notification.Name {
    static let killLauncher = Notification.Name("killLauncher")
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var menu: NSMenu!
    @IBOutlet var startAtLoginButton: NSMenuItem!
    @IBAction func toggleStartAtLoginButton(_ sender: NSMenuItem) {
        let launcherAppId = "elegracer.NetSpeedMonitorHelper"
//        print(sender.state, NSButton.StateValue.on)
        if sender.state == .off {
            if !SMLoginItemSetEnabled(launcherAppId as CFString, true) {
                print("The login item was not successfull")
            } else {
                UserDefaults.standard.set(true, forKey: "isStartAtLogin")
                sender.state = .on
            }
        } else {
            if !SMLoginItemSetEnabled(launcherAppId as CFString, false) {
                print("The login item was not successfull")
            } else {
                UserDefaults.standard.set(false, forKey: "isStartAtLogin")
                sender.state = .off
            }
        }
    }
    @IBOutlet var quitButton: NSMenuItem!
    @IBAction func pressQuitButton(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(sender)
    }

    var uploadSpeed: Double = 0.0
    var downloadSpeed: Double = 0.0
    var uploadMetric: String = "KB"
    var downloadMetric: String = "KB"
    var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var primaryInterface: String = {
        let storeRef = SCDynamicStoreCreate(nil, "FindCurrentInterfaceIpMac" as CFString, nil, nil)
        let global = SCDynamicStoreCopyValue(storeRef, "State:/Network/Global/IPv4" as CFString)
        let primaryInterface = global?.value(forKey: "PrimaryInterface") as? String
        return primaryInterface ?? ""
    }()
    var netStat: NetSpeedStat!
    var timer: Timer!

    var statusBarTextAttributes : [NSAttributedString.Key : Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.maximumLineHeight = 10
        paragraphStyle.paragraphSpacing = -7
        paragraphStyle.alignment = .right
        return [
            NSAttributedString.Key.font : NSFont.monospacedDigitSystemFont(ofSize: 9, weight: NSFont.Weight.regular),
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ] as [NSAttributedString.Key : Any]
    }
    var menuItemTextAttributes: [NSAttributedString.Key : Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        return [
            NSAttributedString.Key.font : NSFont.monospacedDigitSystemFont(ofSize: 12, weight: NSFont.Weight.regular),
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ] as [NSAttributedString.Key : Any]
    }

    func updateSpeed() {
        if let button = statusItem.button {
            button.attributedTitle = NSAttributedString(string: "\n\(String(format: "%7.2lf", uploadSpeed)) \(uploadMetric)/s ↑\n\(String(format: "%7.2lf", downloadSpeed)) \(downloadMetric)/s ↓", attributes: statusBarTextAttributes)
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let launcherAppId = "elegracer.NetSpeedMonitorHelper"
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = !runningApps.filter { $0.bundleIdentifier == launcherAppId }.isEmpty

        if isRunning {
            DistributedNotificationCenter.default().post(name: .killLauncher, object: Bundle.main.bundleIdentifier!)
        }

        statusItem.length = 75
        if let button = statusItem.button {
            button.attributedTitle = NSAttributedString(string: "\n\(String(format: "%7.2lf", 0.0)) KB/s ↑\n\(String(format: "%7.2lf", 0.0)) KB/s ↓", attributes: statusBarTextAttributes)
        }

        startAtLoginButton.state = UserDefaults.standard.bool(forKey: "isStartAtLogin") ? .on : .off

        statusItem.menu = menu

        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if (self.netStat == nil) {
                self.netStat = NetSpeedStat()
//                print(String(format: "netStat: %p", self.netStat))
                self.downloadSpeed = 0.0
                self.downloadMetric = "KB"
                self.uploadSpeed = 0.0
                self.uploadMetric = "KB"
            } else {
                if let statResult = self.netStat.getStatsForInterval(1.0) as NSDictionary? {
                    if let dict = statResult.object(forKey: self.primaryInterface) {
                        let list = dict as! Dictionary<String, UInt64>
                        let deltain: Double = Double(list["deltain"] ?? 0) / 1024.0
                        let deltaout: Double = Double(list["deltaout"] ?? 0) / 1024.0
                        if (deltain > 1000.0) {
                            self.downloadSpeed = deltain / 1024.0
                            self.downloadMetric = "MB"
                        } else {
                            self.downloadSpeed = deltain
                            self.downloadMetric = "KB"
                        }
                        if (deltaout > 1000.0) {
                            self.uploadSpeed = deltaout / 1024.0
                            self.uploadMetric = "MB"
                        } else {
                            self.uploadSpeed = deltaout
                            self.uploadMetric = "KB"
                        }
                        self.updateSpeed()
//                        print("deltaIn: \(self.downloadSpeed) \(self.downloadMetric)/s, deltaOut: \(self.uploadSpeed) \(self.uploadMetric)/s")
                    }
                }
            }
        }
        RunLoop.current.add(self.timer, forMode: .common)
    }
}
