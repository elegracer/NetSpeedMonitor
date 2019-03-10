//
//  AppDelegate.swift
//  NetSpeedMonitor
//
//  Created by Huang Kai on 2019/3/10.
//  Copyright © 2019 Team Elegracer. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var appendMap: [String: String] = ["B": " B", "K": "KB", "M": "MB"]
    var upgradeMap: [String: String] = ["B": "K", "K": "M"]
    var uploadSpeed: Double = 0.0
    var downloadSpeed: Double = 0.0
    var uploadMetric: String = ""
    var downloadMetric: String = ""
    var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    var timer: Timer!
    
    var textAttributes : [NSAttributedString.Key : Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.maximumLineHeight = 10
        paragraphStyle.paragraphSpacing = -7
        paragraphStyle.alignment = .right
        return [
            NSAttributedString.Key.font : NSFont.systemFont(ofSize: 9),
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ] as [NSAttributedString.Key : Any]
    }
    
    func updateSpeed() {
        while (downloadSpeed > 1024.0) {
            downloadSpeed = downloadSpeed / 1024.0
            downloadMetric = upgradeMap[downloadMetric] ?? "B"
        }
        while (uploadSpeed > 1024.0) {
            uploadSpeed = uploadSpeed / 1024.0
            uploadMetric = upgradeMap[uploadMetric] ?? "B"
        }
        if let button = statusItem.button {
            button.attributedTitle = NSAttributedString(string: "\n\(String(format: "%.2f", uploadSpeed)) \(appendMap[uploadMetric] ?? "??")/s U\n\(String(format: "%.2f", downloadSpeed)) \(appendMap[downloadMetric] ?? "??")/s D", attributes: textAttributes)
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem.length = 75
        if let button = statusItem.button {
            button.attributedTitle = NSAttributedString(string: "\n0.00 KB/s U\n0.00 KB/s D", attributes: textAttributes)
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start", action: #selector(AppDelegate.runTimer(_:)), keyEquivalent: "S"))
        menu.addItem(NSMenuItem(title: "Stop", action: #selector(AppDelegate.stopTimer(_:)), keyEquivalent: "T"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "Q"))
        statusItem.menu = menu
        
        runTimer(_: nil)
    }
    
    @objc func stopTimer(_ sender: Any?) {
        if (timer != nil) {
            timer.invalidate()
            timer = nil
        }
    }

    @objc func runTimer(_ sender: Any?) {
        if (timer != nil) {
            timer.invalidate()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            DispatchQueue.global(qos: .default).async {
                let topTask = Process()
                let grepTask = Process()
                topTask.launchPath = "/usr/bin/env"
                topTask.arguments = ["top", "-d", "-i", "1", "-l", "2"]
                grepTask.launchPath = "/usr/bin/env"
                grepTask.arguments = ["grep", "Networks"]
                
                let pipe = Pipe()
                let outpipe = Pipe()
                topTask.standardOutput = pipe
                grepTask.standardInput = pipe
                grepTask.standardOutput = outpipe
                
                topTask.launch()
                grepTask.launch()
                topTask.waitUntilExit()
                grepTask.waitUntilExit()
                
                if let outputString = String(data: outpipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                    let splitStrings = outputString.split(separator: " ")
                    if splitStrings.count == 11 {
                        var downloadSpeedString = splitStrings[7].split(separator: "/")[1]
                        var uploadSpeedString = splitStrings[9].split(separator: "/")[1]
//                        print("U: ", String(downloadSpeedString))
//                        print("D: ", String(uploadSpeedString))
                        self.downloadMetric = String(downloadSpeedString.popLast() ?? "?")
                        self.uploadMetric = String(uploadSpeedString.popLast() ?? "?")
                        self.downloadSpeed = Double(String(downloadSpeedString)) ?? 0.0
                        self.uploadSpeed = Double(String(uploadSpeedString)) ?? 0.0
//                        print("U: ", self.downloadSpeed, self.downloadMetric)
//                        print("D: ", self.uploadSpeed, self.uploadMetric)
                    }
                }
                
                topTask.terminate()
                grepTask.terminate()
                
                DispatchQueue.main.async {
                    self.updateSpeed()
                }
            }
        }
    }
}
