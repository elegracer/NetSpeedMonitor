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
    let launcherAppId = "elegracer.NetSpeedMonitorHelper" as String
    let keyIsStartAtLogin = "isStartAtLogin" as String
    let keyUpdateInteval = "updateInteval" as String
    
    @IBOutlet var menu: NSMenu!
    @IBOutlet var startAtLoginMenuItem: NSMenuItem!
    @IBAction func onPressStartAtLoginMenuItem(_ sender: NSMenuItem) {
        let isStartAtLogin = sender.state == .on
        if !SMLoginItemSetEnabled(launcherAppId as CFString, !isStartAtLogin) {
            print("Error when toggling item for ", keyIsStartAtLogin)
        } else {
            UserDefaults.standard.set(!isStartAtLogin, forKey: keyIsStartAtLogin)
            sender.state = !isStartAtLogin ? .on : .off
        }
    }
    @IBOutlet var quitButton: NSMenuItem!
    @IBAction func onPressQuitMenuItem(_ sender: NSMenuItem) {
        print("isStartAtLogin: ", UserDefaults.standard.bool(forKey: keyIsStartAtLogin), ", updateInteval: ", UserDefaults.standard.integer(forKey: keyUpdateInteval))
        NSApplication.shared.terminate(sender)
    }
    
    @IBOutlet var updateInteval1sMenuItem: NSMenuItem!
    @IBOutlet var updateInteval2sMenuItem: NSMenuItem!
    @IBOutlet var updateInteval4sMenuItem: NSMenuItem!
    @IBOutlet var updateInteval8sMenuItem: NSMenuItem!
    var updateIntevalMenuItemCollection: [NSMenuItem] {
        return [
            self.updateInteval1sMenuItem,
            self.updateInteval2sMenuItem,
            self.updateInteval4sMenuItem,
            self.updateInteval8sMenuItem
        ]
    }
    
    var updateIntevalInSec = 1.0
    let validUpdateIntevals : [Int] = [1, 2, 4, 8]
    
    func onClickUpdateIntevalMenuItem(_ sender: NSMenuItem, value: Int) {
        updateIntevalInSec = Double(value)
        for updateIntevalMenuItem in updateIntevalMenuItemCollection {
            updateIntevalMenuItem.state = .off
        }
        sender.state = .on
        UserDefaults.standard.set(value, forKey: keyUpdateInteval)
        resetTimer()
    }
    
    @IBAction func onClickUpdateInteval1s(_ sender: NSMenuItem) {
        onClickUpdateIntevalMenuItem(sender, value: 1)
    }
    @IBAction func onClickUpdateInteval2s(_ sender: NSMenuItem) {
        onClickUpdateIntevalMenuItem(sender, value: 2)
    }
    @IBAction func onClickUpdateInteval4s(_ sender: NSMenuItem) {
        onClickUpdateIntevalMenuItem(sender, value: 4)
    }
    @IBAction func onClickUpdateInteval8s(_ sender: NSMenuItem) {
        onClickUpdateIntevalMenuItem(sender, value: 8)
    }
    
    var uploadSpeed: Double = 0.0
    var downloadSpeed: Double = 0.0
    var uploadMetric: String = " B"
    var downloadMetric: String = " B"
    
    let speedMetrics: [String] = [" B", "KB", "MB", "GB"]
    
    var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    var primaryInterface: String?
    var netStat: NetSpeedStat!
    var timer: Timer!
    
    var statusBarTextAttributes : [NSAttributedString.Key : Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.maximumLineHeight = 10
        paragraphStyle.paragraphSpacing = -5
        var map = [NSAttributedString.Key : Any]()
        map[NSAttributedString.Key.font] = NSFont(name: "SFMono-Semibold", size: 8)!
        map[NSAttributedString.Key.baselineOffset] = -5
        map[NSAttributedString.Key.paragraphStyle] = paragraphStyle
        return map
    }
    
    func findPrimaryInterface() -> String? {
        let storeRef = SCDynamicStoreCreate(nil, "FindCurrentInterfaceIpMac" as CFString, nil, nil)
        let global = SCDynamicStoreCopyValue(storeRef, "State:/Network/Global/IPv4" as CFString)
        let primaryInterface = global?.value(forKey: "PrimaryInterface") as? String
        return primaryInterface
    }
    
    func updateSpeed() {
        if let button = statusItem.button {
            button.attributedTitle = NSAttributedString(string: "\n\(String(format: "%6.2lf", uploadSpeed)) \(uploadMetric)/s ↑\n\(String(format: "%6.2lf", downloadSpeed)) \(downloadMetric)/s ↓", attributes: statusBarTextAttributes)
        }
    }
    
    func startRepeatTimer() {
        self.timer = Timer.scheduledTimer(withTimeInterval: updateIntevalInSec, repeats: true) { _ in
            if (self.netStat == nil) {
                self.netStat = NetSpeedStat()
                self.downloadSpeed = 0.0
                self.downloadMetric = " B"
                self.uploadSpeed = 0.0
                self.uploadMetric = " B"
                return
            }
            
            if let statResult = self.netStat.getStatsForInterval(self.updateIntevalInSec) as NSDictionary? {
                if (self.primaryInterface == nil) {
                    self.primaryInterface = self.findPrimaryInterface();
                    if (self.primaryInterface == nil) {
                        return
                    }
                }
                if let dict = statResult.object(forKey: self.primaryInterface!) {
                    let list = dict as! Dictionary<String, UInt64>
                    self.downloadSpeed = Double(list["deltain"] ?? 0) / self.updateIntevalInSec
                    self.uploadSpeed = Double(list["deltaout"] ?? 0) / self.updateIntevalInSec
                    self.downloadMetric = self.speedMetrics.first!
                    self.uploadMetric = self.speedMetrics.first!
                    for metric in self.speedMetrics.dropFirst() {
                        if self.downloadSpeed > 1000.0 {
                            self.downloadSpeed /= 1024.0
                            self.downloadMetric = metric
                        }
                        if self.uploadSpeed > 1000.0 {
                            self.uploadSpeed /= 1024.0
                            self.uploadMetric = metric
                        }
                    }
                    self.updateSpeed()
                    print("deltaIn: \(self.downloadSpeed) \(self.downloadMetric)/s, deltaOut: \(self.uploadSpeed) \(self.uploadMetric)/s")
                }
            }
            
        }
        RunLoop.current.add(self.timer, forMode: .common)
    }
    
    func resetTimer() {
        if self.timer != nil {
            self.timer.invalidate()
        }
        startRepeatTimer()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == self.launcherAppId }

        if isRunning {
            DistributedNotificationCenter.default().post(name: .killLauncher, object: Bundle.main.bundleIdentifier!)
        }
        
        statusItem.length = 75
        statusItem.menu = menu
        startAtLoginMenuItem.state = UserDefaults.standard.bool(forKey: keyIsStartAtLogin) ? .on : .off
        
        let savedUpdateInteval = UserDefaults.standard.integer(forKey: keyUpdateInteval)
        if self.validUpdateIntevals.contains(savedUpdateInteval) {
            let index = self.validUpdateIntevals.firstIndex(of: savedUpdateInteval)!
            onClickUpdateIntevalMenuItem(updateIntevalMenuItemCollection[index], value: validUpdateIntevals[index])
        } else {
            onClickUpdateIntevalMenuItem(updateIntevalMenuItemCollection[0], value: validUpdateIntevals[0])
        }
        
        updateSpeed()
    }
}
