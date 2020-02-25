//
//  NetSpeedViewController.swift
//  NetSpeedMonitor
//
//  Created by Huang Kai on 2020/2/25.
//  Copyright © 2020 Team Elegracer. All rights reserved.
//

import Cocoa
import ServiceManagement

class NetSpeedViewController: NSViewController {

    @IBOutlet var tableView: NSTableView!
    @IBOutlet var startAtLoginButton: NSButton!

    @IBAction func quit(_ sender: NSButton) {
        NSApplication.shared.terminate(sender)
    }

    @IBAction func toggleStartAtLogin(_ sender: NSButton) {
        let launcherAppId = "elegracer.NetSpeedMonitorHelper"
        print(sender.state, NSButton.StateValue.on)
        if sender.state == .on {
            if !SMLoginItemSetEnabled(launcherAppId as CFString, true) {
                print("The login item was not successfull")
            } else {
                UserDefaults.standard.set(true, forKey: "isStartAtLogin")
            }
        } else {
            if !SMLoginItemSetEnabled(launcherAppId as CFString, false) {
                print("The login item was not successfull")
            } else {
                UserDefaults.standard.set(false, forKey: "isStartAtLogin")
            }
        }
    }

    var processes: [(name: String, download: Double, upload: Double)] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self

        startAtLoginButton.state = UserDefaults.standard.bool(forKey: "isStartAtLogin") ? .on : .off
    }
}

extension NetSpeedViewController: NSTableViewDelegate, NSTableViewDataSource {
    // MARK: Storyboard instantiation
    static func freshController() -> NetSpeedViewController {
        //1.
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        //2.
        let identifier = NSStoryboard.SceneIdentifier("NetSpeedViewController")
        //3.
        guard let viewcontroller = storyboard.instantiateController(withIdentifier: identifier) as? NetSpeedViewController else {
            fatalError("Why cant i find NetSpeedViewController? - Check Main.storyboard")
        }
        return viewcontroller
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return processes.count
    }

    fileprivate enum CellIdentifiers {
        static let ProcessNameCell = "ProcessNameCellID"
        static let DownloadSpeedCell = "DownloadSpeedCellID"
        static let UploadSpeedCell = "UploadSpeedCellID"
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        var speed: Double = 0.0
        var text: String = ""
        var cellIdentifier: String = ""

        if tableColumn == tableView.tableColumns[0] {
            text = processes[row].name
            cellIdentifier = CellIdentifiers.ProcessNameCell
        } else if tableColumn == tableView.tableColumns[1] {
            speed = processes[row].download
            if (speed > 1024.0) {
                text = String(format: "%.2lf MB/s", speed / 1024.0)
            } else {
                text = String(format: "%.2lf KB/s", speed)
            }
            cellIdentifier = CellIdentifiers.DownloadSpeedCell
        } else if tableColumn == tableView.tableColumns[2] {
            speed = processes[row].upload
            if (speed > 1024.0) {
                text = String(format: "%.2lf MB/s", speed / 1024.0)
            } else {
                text = String(format: "%.2lf KB/s", speed)
            }
            cellIdentifier = CellIdentifiers.UploadSpeedCell
        }

        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdentifier), owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }
        return nil
    }
}
