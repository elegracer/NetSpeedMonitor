//
//  AppDelegate.swift
//  NetSpeedMonitor
//
//  Created by Huang Kai on 2019/3/10.
//  Copyright © 2019 Team Elegracer. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let killLauncher = Notification.Name("killLauncher")
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let popover = NSPopover()
    let netspeedViewController = NetSpeedViewController.freshController()

    var processSpeeds: [(name: String, download: Double, upload: Double)] = []

    var uploadSpeed: Double = 0.0
    var downloadSpeed: Double = 0.0
    var uploadMetric: String = "KB"
    var downloadMetric: String = "KB"
    var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer: Timer!

    var statusBarTextAttributes : [NSAttributedString.Key : Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.maximumLineHeight = 10
        paragraphStyle.paragraphSpacing = -9
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

        if let tableView = netspeedViewController.tableView {
            netspeedViewController.processes = processSpeeds
            tableView.reloadData()
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
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = NSPopover.Behavior.transient
        popover.contentViewController = netspeedViewController

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            DispatchQueue.global(qos: .background).async {
                let topTask = Process()
                topTask.launchPath = "/usr/bin/env"
                topTask.arguments = ["nettop", "-d", "-P", "-J", "bytes_in,bytes_out", "-x", "-L", "2", "-c"]

                let outpipe = Pipe()
                topTask.standardOutput = outpipe
                topTask.launch()
                topTask.waitUntilExit()

                if let outputString = String(data: outpipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                    let splitStrings = outputString.split(separator: "\n")
                    self.processSpeeds.removeAll()
                    if splitStrings.count > 0 {
                        for i in 1 + splitStrings.count / 2 ..< splitStrings.count {
                            let cells = splitStrings[i].split(separator: ",")
                            self.processSpeeds.append((name: String(cells[1].split(separator: ".")[0]), download: Double(cells[2])! / 1024.0, upload: Double(cells[3])! / 1024.0))
                        }
                    }
                    self.processSpeeds.sort(by: {$0.download > $1.download})
                }

                topTask.terminate()

                self.downloadSpeed = 0.0
                self.uploadSpeed = 0.0
                for speed in self.processSpeeds {
                    self.downloadSpeed += speed.download
                    self.uploadSpeed += speed.upload
                }
                if (self.downloadSpeed > 1024.0) {
                    self.downloadSpeed /= 1024.0
                    self.downloadMetric = "MB"
                } else {
                    self.downloadMetric = "KB"
                }
                if (self.uploadSpeed > 1024.0) {
                    self.uploadSpeed /= 1024.0
                    self.uploadMetric = "MB"
                } else {
                    self.uploadMetric = "KB"
                }

                DispatchQueue.main.async {
                    self.updateSpeed()
                }
            }
        }
        RunLoop.current.add(timer, forMode: .common)
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }

    func showPopover(sender: Any?) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
    }

    func closePopover(sender: Any?) {
        popover.performClose(sender)
    }
}
