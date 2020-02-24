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

    @IBOutlet var menu: NSMenu!
    @IBOutlet var quitMenuItem: NSMenuItem!
    @IBOutlet var item1: NSMenuItem!
    @IBOutlet var item2: NSMenuItem!
    @IBOutlet var item3: NSMenuItem!
    @IBOutlet var item4: NSMenuItem!
    @IBOutlet var item5: NSMenuItem!
    @IBOutlet var item6: NSMenuItem!
    @IBOutlet var item7: NSMenuItem!
    @IBOutlet var item8: NSMenuItem!
    @IBOutlet var item9: NSMenuItem!
    @IBOutlet var item10: NSMenuItem!
    
    lazy var menuItems: [NSMenuItem] = [
        item1, item2, item3, item4, item5, item6, item7, item8, item9, item10
    ]
    
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
        downloadSpeed = 0.0
        uploadSpeed = 0.0
        for speed in processSpeeds {
            downloadSpeed += speed.download
            uploadSpeed += speed.upload
        }
        downloadMetric = "KB"
        if (downloadSpeed > 1024.0) {
            downloadSpeed /= 1024.0
            downloadMetric = "MB"
        }
        uploadMetric = "KB"
        if (uploadSpeed > 1024.0) {
            uploadSpeed /= 1024.0
            uploadMetric = "MB"
        }
        
        if let button = statusItem.button {
            button.attributedTitle = NSAttributedString(string: "\n\(String(format: "%7.2lf", uploadSpeed)) \(uploadMetric)/s ↑\n\(String(format: "%7.2lf", downloadSpeed)) \(downloadMetric)/s ↓", attributes: statusBarTextAttributes)
        }
        for i in 0..<menuItems.count {
            downloadMetric = "KB"
            if (processSpeeds[i].download > 1024.0) {
                processSpeeds[i].download /= 1024.0
                downloadMetric = "MB"
            }
            uploadMetric = "KB"
            if (processSpeeds[i].upload > 1024.0) {
                processSpeeds[i].upload /= 1024.0
                uploadMetric = "MB"
            }
            menuItems[i].isHidden = false
            menuItems[i].attributedTitle = NSAttributedString(string: "\(processSpeeds[i].name)  \(String(format: "%7.2lf", processSpeeds[i].download)) \(downloadMetric)/s ↓  \(String(format: "%7.2lf", processSpeeds[i].upload)) \(uploadMetric)/s ↑", attributes: menuItemTextAttributes)
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem.length = 75
        if let button = statusItem.button {
            button.attributedTitle = NSAttributedString(string: "\n\(String(format: "%7.2lf", 0.0)) KB/s ↑\n\(String(format: "%7.2lf", 0.0)) KB/s ↓", attributes: statusBarTextAttributes)
        }
        
        quitMenuItem.action = #selector(NSApplication.terminate(_:))
        
        statusItem.menu = menu
    
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
                    let length = splitStrings.count / 2
                    self.processSpeeds.removeAll()
                    for i in 1 + length ..< splitStrings.count {
                        let cells = splitStrings[i].split(separator: ",")
                        self.processSpeeds.append((name: String(cells[1].split(separator: ".")[0]), download: Double(cells[2])! / 1024.0, upload: Double(cells[3])! / 1024.0))
                    }
                    self.processSpeeds.sort(by: {$0.download > $1.download})
                }
                
                topTask.terminate()
                
                DispatchQueue.main.async {
                    self.updateSpeed()
                }
            }
        }
        RunLoop.current.add(timer, forMode: .common)
    }
}
