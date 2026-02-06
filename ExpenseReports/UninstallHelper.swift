//
//  UninstallHelper.swift
//  ExpenseReports
//
//  Schedules removal of the app and all support files after quit (via LaunchAgent).
//  User runs "Uninstall ExpenseReports..." from the app menu — no Gatekeeper.
//

import AppKit
import Foundation

enum UninstallHelper {
    private static let appName = "ExpenseReports"
    private static let bundleId = "DarshanBodara.ExpenseReports"
    private static let launchAgentLabel = "\(bundleId).uninstall"

    /// Schedules uninstall to run after the app quits, then terminates the app.
    static func scheduleUninstallThenQuit() {
        let appPath = Bundle.main.bundlePath
        let scriptPath = "/tmp/\(appName.lowercased())-uninstall-\(UUID().uuidString.prefix(8)).sh"
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist").path

        let script = """
        #!/bin/bash
        sleep 2
        rm -rf "\(appPath)"
        rm -rf "$HOME/Library/Application Support/\(appName)"
        rm -rf "$HOME/Library/Application Support/\(bundleId)"
        rm -rf "$HOME/Library/Caches/\(bundleId)"
        rm -rf "$HOME/Library/Containers/\(bundleId)"
        rm -f "$HOME/Library/Preferences/\(bundleId).plist"
        rm -rf "$HOME/Library/Saved Application State/\(bundleId).savedState"
        rm -rf "$HOME/Library/Logs/\(appName)"
        rm -rf "$HOME/Library/Logs/\(bundleId)"
        launchctl unload "\(plistPath)" 2>/dev/null
        rm -f "\(plistPath)"
        rm -f "$0"
        """

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(scriptPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """

        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)

            let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents")
            try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["load", plistPath]
            try process.run()
            process.waitUntilExit()

            NSApplication.shared.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Uninstall could not be started"
            alert.informativeText = "Please use the Uninstall ExpenseReports.command file from the DMG, or drag the app to Trash and remove support files manually."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
