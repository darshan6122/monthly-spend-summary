//
//  AccountsHelper.swift
//  ExpenseReports
//
//  Uses a fixed app folder for month data and runs the Python report/merge scripts.
//

import Combine
import Foundation
import AppKit
import UniformTypeIdentifiers
import UserNotifications

final class AccountsHelper: ObservableObject {
    @Published var monthFolders: [String] = []
    @Published var selectedFolder: String = ""
    @Published var statusMessage: String = ""
    @Published var isWorking: Bool = false
    @Published var stepMessage: String = ""
    @Published var lastScriptOutput: String = ""
    /// Shown when setup is needed (e.g. scripts missing). Empty when ready.
    @Published var setupInstructions: String = ""
    /// Path to the app's accounts folder (where you put month folders). Always valid.
    @Published var accountsFolderPath: String = ""
    /// Callback to retry last failed action (merge/report).
    var lastFailedAction: (() -> Void)?
    /// When the last merge/report completed successfully (for display in Advanced).
    @Published var lastRunDate: Date?
    /// Short "what to do" when a script or setup fails (e.g. "Install Python: brew install python3").
    @Published var errorRecoveryHint: String = ""
    /// Path to the last successfully generated report (for "Open last report").
    @Published var lastReportPath: URL?

    private var accountsDirURL: URL?

    private static let recentFoldersKey = "ExpenseReports.recentFolders"
    private static let pinnedFolderKey = "ExpenseReports.pinnedFolder"
    private static let maxRecentCount = 5

    /// Fixed folder: ~/Library/Application Support/ExpenseReports/Accounts
    private static func appAccountsDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("ExpenseReports", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
    }

    init() {
        ensureAccountsFolderAndLoad()
    }

    /// Create the app's Accounts folder if needed and load month folders from it.
    private func ensureAccountsFolderAndLoad() {
        let dir = Self.appAccountsDirectory()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                accountsDirURL = nil
                accountsFolderPath = dir.path
                monthFolders = []
                statusMessage = "Could not create folder: \(error.localizedDescription)"
                return
            }
        }
        accountsDirURL = dir
        accountsFolderPath = dir.path
        loadMonthFolders(from: dir)
        updateSetupInstructions(dir: dir)
        if monthFolders.isEmpty && statusMessage.isEmpty && setupInstructions.isEmpty {
            statusMessage = "Put month folders (with cibc*.csv) here, plus .venv and the Python scripts."
        }
    }

    private func updateSetupInstructions(dir: URL) {
        let fm = FileManager.default
        let needsMerge = !fm.fileExists(atPath: dir.appendingPathComponent("merge_and_categorize.py").path)
        let needsReport = !fm.fileExists(atPath: dir.appendingPathComponent("make_monthly_report.py").path)
        if needsMerge || needsReport {
            setupInstructions = "Copy the environment from your Desktop ACCOUNTS folder (make_monthly_report.py, merge_and_categorize.py, .venv) into the data folder, then open the data folder and add month folders."
        } else {
            setupInstructions = ""
        }
    }

    /// Copy scripts and .venv from ~/Desktop/ACCOUNTS into the app's Accounts folder.
    func copySetupFromDesktop() -> (success: Bool, message: String) {
        guard let dest = accountsDirURL else { return (false, "Accounts folder not found.") }
        let desktopAccounts = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/ACCOUNTS", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: desktopAccounts.path) else {
            return (false, "Desktop/ACCOUNTS folder not found.")
        }
        let toCopy = ["make_monthly_report.py", "merge_and_categorize.py", ".venv"]
        for name in toCopy {
            let src = desktopAccounts.appendingPathComponent(name, isDirectory: name == ".venv")
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dest.appendingPathComponent(name, isDirectory: name == ".venv")
            do {
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.copyItem(at: src, to: dst)
            } catch {
                return (false, "Failed to copy \(name): \(error.localizedDescription)")
            }
        }
        updateSetupInstructions(dir: dest)
        loadMonthFolders(from: dest)
        return (true, "Copied from Desktop ACCOUNTS.")
    }

    func retryLastAction() {
        lastFailedAction?()
    }

    /// Open the accounts folder in Finder.
    func openAccountsFolderInFinder() {
        guard let url = accountsDirURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Open the selected month folder in Finder (where the report .xlsx is saved).
    func openMonthFolderInFinder() {
        guard let base = accountsDirURL, !selectedFolder.isEmpty else { return }
        let monthURL = base.appendingPathComponent(selectedFolder, isDirectory: true)
        NSWorkspace.shared.open(monthURL)
    }

    func refreshFolders() {
        guard let dir = accountsDirURL else { return }
        loadMonthFolders(from: dir)
        updateSetupInstructions(dir: dir)
    }

    private func loadMonthFolders(from accountsDir: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: accountsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            monthFolders = []
            return
        }
        var folders: [String] = []
        for item in contents {
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = item.lastPathComponent
            if name.hasPrefix(".") { continue }
            let parent = item
            guard let sub = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            let hasCibc = sub.contains { $0.lastPathComponent.hasPrefix("cibc") && $0.lastPathComponent.hasSuffix(".csv") }
            if hasCibc {
                folders.append(name)
            }
        }
        monthFolders = folders.sorted()
        if selectedFolder.isEmpty || !monthFolders.contains(selectedFolder) {
            if let pinned = UserDefaults.standard.string(forKey: Self.pinnedFolderKey), monthFolders.contains(pinned) {
                selectedFolder = pinned
            } else if let first = monthFolders.first {
                selectedFolder = first
            } else {
                selectedFolder = ""
            }
        }
        if !selectedFolder.isEmpty { addToRecent(selectedFolder) }
        if monthFolders.isEmpty {
            statusMessage = "Put month folders (with cibc*.csv) here, plus .venv and the Python scripts."
        } else {
            statusMessage = ""
        }
    }

    private func addToRecent(_ name: String) {
        var recent = UserDefaults.standard.stringArray(forKey: Self.recentFoldersKey) ?? []
        recent.removeAll { $0 == name }
        recent.insert(name, at: 0)
        recent = Array(recent.prefix(Self.maxRecentCount))
        UserDefaults.standard.set(recent, forKey: Self.recentFoldersKey)
    }

    func recentFolderNames() -> [String] {
        (UserDefaults.standard.stringArray(forKey: Self.recentFoldersKey) ?? []).filter { monthFolders.contains($0) }
    }

    var pinnedFolder: String? {
        get {
            guard let p = UserDefaults.standard.string(forKey: Self.pinnedFolderKey), monthFolders.contains(p) else { return nil }
            return p
        }
        set {
            if let n = newValue { UserDefaults.standard.set(n, forKey: Self.pinnedFolderKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.pinnedFolderKey) }
        }
    }
    
    /// Resolve symlinks until we get the real binary.
    private func resolveToRealBinary(_ url: URL) -> URL? {
        let fm = FileManager.default
        var current = url
        for _ in 0..<20 {
            guard fm.fileExists(atPath: current.path) else { return nil }
            guard (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else {
                return current
            }
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: current.path) else { return nil }
            if dest.hasPrefix("/") {
                current = URL(fileURLWithPath: dest)
            } else {
                current = current.deletingLastPathComponent().appendingPathComponent(dest)
            }
        }
        return nil
    }

    /// Prefer venv's Python (resolved) + VIRTUAL_ENV; else system Python (resolved).
    private func findWorkingPython(base: URL) -> (path: String, virtualEnvPath: String?)? {
        let fm = FileManager.default
        let venvPython = base.appendingPathComponent(".venv/bin/python")
        if fm.fileExists(atPath: venvPython.path),
           let resolved = resolveToRealBinary(venvPython) {
            return (resolved.path, base.path + "/.venv")
        }
        let systemCandidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/python3"),
            URL(fileURLWithPath: "/usr/local/bin/python3"),
            URL(fileURLWithPath: "/usr/bin/python3"),
        ]
        for url in systemCandidates where fm.fileExists(atPath: url.path) {
            if let resolved = resolveToRealBinary(url) {
                return (resolved.path, nil)
            }
            return (url.path, nil)
        }
        return nil
    }

    /// Find venv site-packages dir (e.g. .venv/lib/python3.13/site-packages).
    private func venvSitePackages(venvPath: String) -> String? {
        let lib = (venvPath as NSString).appendingPathComponent("lib")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: lib) else { return nil }
        let pythonDir = contents.first { $0.hasPrefix("python3.") }
        guard let dir = pythonDir else { return nil }
        let libDir = (lib as NSString).appendingPathComponent(dir)
        let sitePackages = (libDir as NSString).appendingPathComponent("site-packages")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: sitePackages, isDirectory: &isDir) && isDir.boolValue ? sitePackages : nil
    }

    /// Escape a path for use inside single-quoted shell snippet (replace ' with '\'').
    private func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private func runScript(name: String, folder: String) -> (success: Bool, message: String) {
        guard let base = accountsDirURL else { return (false, "ACCOUNTS folder not found.") }
        let scriptURL = base.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            DispatchQueue.main.async { [weak self] in
                self?.errorRecoveryHint = "Copy make_monthly_report.py and merge_and_categorize.py from your Desktop ACCOUNTS folder into the data folder (Open Data Folder → paste files)."
            }
            return (false, "Put make_monthly_report.py and merge_and_categorize.py in the accounts folder.")
        }
        guard let (pythonPath, venvPath) = findWorkingPython(base: base) else {
            DispatchQueue.main.async { [weak self] in
                self?.errorRecoveryHint = "Install Python: brew install python3 — or add a .venv with Python to your data folder (Copy from Desktop if you have one)."
            }
            return (false, "No Python found. Install from python.org or run: brew install python3")
        }
        DispatchQueue.main.async { [weak self] in self?.errorRecoveryHint = "" }
        // Run via /bin/sh so we never exec Python directly (avoids "python3.13 doesn't exist" dialog).
        var exports = "export EXPENSE_REPORTS_ACCOUNTS_DIR='\(shellEscape(base.path))'; "
        if let venv = venvPath {
            exports += "export VIRTUAL_ENV='\(shellEscape(venv))'; "
            if let sitePackages = venvSitePackages(venvPath: venv) {
                exports += "export PYTHONPATH='\(shellEscape(sitePackages))'; "
            }
        }
        let cmd = "\(exports)exec '\(shellEscape(pythonPath))' '\(shellEscape(scriptURL.path))' '\(shellEscape(folder))'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", cmd]
        process.currentDirectoryURL = base
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let outData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""
            let combined = (out + (err.isEmpty ? "" : "\n--- stderr ---\n" + err)).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { [weak self] in
                self?.lastScriptOutput = combined.isEmpty ? "(no output)" : combined
            }
            if process.terminationStatus == 0 {
                return (true, out.isEmpty ? "Done." : out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return (false, err.isEmpty ? out : err)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func mergeThenGenerate() {
        guard !selectedFolder.isEmpty else {
            statusMessage = "Select a month folder first."
            return
        }
        let folderName = selectedFolder
        isWorking = true
        stepMessage = "Merging CSVs…"
        lastFailedAction = { [weak self] in self?.mergeThenGenerate() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let mergeResult = self.runScript(name: "merge_and_categorize.py", folder: self.selectedFolder)
            guard mergeResult.success else {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.stepMessage = ""
                    self.statusMessage = "✗ \(mergeResult.message)"
                }
                return
            }
            DispatchQueue.main.async { self.stepMessage = "Generating report…" }
            let reportResult = self.runScript(name: "make_monthly_report.py", folder: self.selectedFolder)
            DispatchQueue.main.async {
                self.isWorking = false
                self.stepMessage = ""
                if reportResult.success {
                    self.lastFailedAction = nil
                    self.lastRunDate = Date()
                    self.statusMessage = "✓ Report saved in \(folderName) folder."
                    let reportURL = self.accountsDirURL?.appendingPathComponent(self.selectedFolder).appendingPathComponent("\(folderName)_Report.xlsx")
                    if let url = reportURL, FileManager.default.fileExists(atPath: url.path) {
                        self.lastReportPath = url
                        Self.sendReportReadyNotification(month: folderName)
                    }
                    if AppSettings.openFolderAfterReport { self.openMonthFolderInFinder() }
                } else {
                    self.statusMessage = "✗ \(reportResult.message)"
                }
            }
        }
    }

    func generateReport() {
        guard !selectedFolder.isEmpty else {
            statusMessage = "Select a month folder first."
            return
        }
        isWorking = true
        stepMessage = "Generating report…"
        statusMessage = "Generating report…"
        let folderName = selectedFolder
        lastFailedAction = { [weak self] in self?.generateReport() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runScript(name: "make_monthly_report.py", folder: self?.selectedFolder ?? "") ?? (success: false, message: "Error")
            DispatchQueue.main.async {
                self?.isWorking = false
                self?.stepMessage = ""
                if result.success {
                    self?.lastFailedAction = nil
                    self?.lastRunDate = Date()
                    self?.statusMessage = "✓ Report saved in \(folderName) folder."
                    if let base = self?.accountsDirURL {
                        let reportURL = base.appendingPathComponent(folderName).appendingPathComponent("\(folderName)_Report.xlsx")
                        if FileManager.default.fileExists(atPath: reportURL.path) {
                            self?.lastReportPath = reportURL
                            Self.sendReportReadyNotification(month: folderName)
                        }
                    }
                    if AppSettings.openFolderAfterReport { self?.openMonthFolderInFinder() }
                } else {
                    self?.statusMessage = "✗ \(result.message)"
                }
            }
        }
    }

    func mergeCSVs() {
        guard !selectedFolder.isEmpty else {
            statusMessage = "Select a month folder first."
            return
        }
        isWorking = true
        stepMessage = "Merging CSVs…"
        statusMessage = "Merging CSVs…"
        lastFailedAction = { [weak self] in self?.mergeCSVs() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runScript(name: "merge_and_categorize.py", folder: self?.selectedFolder ?? "") ?? (success: false, message: "Error")
            DispatchQueue.main.async {
                self?.isWorking = false
                self?.stepMessage = ""
                self?.statusMessage = result.success ? "✓ \(result.message)" : "✗ \(result.message)"
                if result.success {
                    self?.lastFailedAction = nil
                    self?.lastRunDate = Date()
                }
            }
        }
    }

    /// If the dropped URL is a month folder inside our accounts dir, select it. Returns true if selected.
    func trySelectDroppedFolder(_ url: URL) -> Bool {
        guard let base = accountsDirURL, url.isFileURL else { return false }
        let path = url.path
        let basePath = base.path
        guard path.hasPrefix(basePath) else { return false }
        let relative = path.dropFirst(basePath.hasSuffix("/") ? basePath.count : basePath.count + 1)
        let firstComponent = relative.split(separator: "/").first.flatMap(String.init) ?? ""
        guard !firstComponent.isEmpty, firstComponent != ".venv" else { return false }
        let monthURL = base.appendingPathComponent(firstComponent, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: monthURL.path, isDirectory: &isDir), isDir.boolValue else { return false }
        selectedFolder = firstComponent
        statusMessage = ""
        return true
    }

    /// CSV count and report file date for the selected month (if any).
    func selectedMonthStats() -> (csvCount: Int, reportDate: Date?)? {
        guard let base = accountsDirURL, !selectedFolder.isEmpty else { return nil }
        let monthURL = base.appendingPathComponent(selectedFolder, isDirectory: true)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: monthURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        let csvCount = contents.filter { $0.lastPathComponent.hasPrefix("cibc") && $0.lastPathComponent.hasSuffix(".csv") }.count
        let reportName = "\(selectedFolder)_Report.xlsx"
        let reportURL = monthURL.appendingPathComponent(reportName)
        var reportDate: Date?
        if let attrs = try? fm.attributesOfItem(atPath: reportURL.path), let d = attrs[.modificationDate] as? Date {
            reportDate = d
        }
        return (csvCount, reportDate)
    }

    /// Open the selected month's report .xlsx in the default app.
    func openReportFile() {
        guard let base = accountsDirURL, !selectedFolder.isEmpty else { return }
        let reportURL = base.appendingPathComponent(selectedFolder).appendingPathComponent("\(selectedFolder)_Report.xlsx")
        guard FileManager.default.fileExists(atPath: reportURL.path) else { return }
        NSWorkspace.shared.open(reportURL)
    }

    /// Open the last successfully generated report (from menu or UI).
    func openLastReport() {
        guard let url = lastReportPath, FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Copy the current (or last) report file path to the pasteboard. Returns true if copied.
    func copyReportPathToClipboard() -> Bool {
        let url: URL?
        if let last = lastReportPath, FileManager.default.fileExists(atPath: last.path) {
            url = last
        } else if let base = accountsDirURL, !selectedFolder.isEmpty {
            url = base.appendingPathComponent(selectedFolder).appendingPathComponent("\(selectedFolder)_Report.xlsx")
            if !FileManager.default.fileExists(atPath: url!.path) { return false }
        } else {
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url!.path, forType: .string)
        return true
    }

    private static let hasRequestedNotificationKey = "ExpenseReports.hasRequestedNotification"

    private static func sendReportReadyNotification(month: String) {
        if !UserDefaults.standard.bool(forKey: hasRequestedNotificationKey) {
            UserDefaults.standard.set(true, forKey: hasRequestedNotificationKey)
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "Report ready"
        content.body = "\(month)_Report.xlsx has been created."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "report-\(UUID().uuidString)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    /// Create a new month folder (e.g. "FEBRUARY 2026") in the data folder. Returns (success, message).
    func createNewMonthFolder() -> (success: Bool, message: String) {
        guard let base = accountsDirURL else { return (false, "Data folder not found.") }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US")
        let name = formatter.string(from: Date()).uppercased()
        let folderURL = base.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: folderURL.path) {
            return (false, "Folder \"\(name)\" already exists.")
        }
        do {
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            addToRecent(name)
            loadMonthFolders(from: base)
            selectedFolder = name
            return (true, "Created \"\(name)\". Add your CIBC CSV files and refresh.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Present Save panel to export the selected month as a zip.
    func exportMonthBackupWithSavePanel() {
        guard !selectedFolder.isEmpty else {
            statusMessage = "✗ Select a month first."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export month as zip"
        panel.nameFieldStringValue = "\(selectedFolder).zip"
        panel.allowedContentTypes = [.zip]
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            let r = self.exportMonthBackup(to: url)
            self.statusMessage = r.success ? "✓ \(r.message)" : "✗ \(r.message)"
        }
    }

    /// Export only the selected month folder as a zip to the given URL.
    func exportMonthBackup(to destinationURL: URL) -> (success: Bool, message: String) {
        guard let base = accountsDirURL, !selectedFolder.isEmpty else { return (false, "Select a month first.") }
        let monthURL = base.appendingPathComponent(selectedFolder, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: monthURL.path) else { return (false, "Month folder not found.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", monthURL.path, destinationURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return (true, "Exported \(selectedFolder) to \(destinationURL.lastPathComponent)")
            }
            return (false, "Export failed.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Present Save panel to export the current report; on OK copies to chosen URL and updates status.
    func exportReportWithSavePanel() {
        guard let base = accountsDirURL, !selectedFolder.isEmpty else {
            statusMessage = "✗ Select a month and create a report first."
            return
        }
        let reportName = "\(selectedFolder)_Report.xlsx"
        let sourceURL = base.appendingPathComponent(selectedFolder).appendingPathComponent(reportName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            statusMessage = "✗ Report not found. Create a report first."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Report"
        panel.nameFieldStringValue = reportName
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let r = self.exportReport(to: url)
            self.statusMessage = r.success ? "✓ \(r.message)" : "✗ \(r.message)"
        }
    }

    /// Copy the current month's report to a chosen URL (e.g. from Save panel). Returns (success, message).
    func exportReport(to destinationURL: URL) -> (success: Bool, message: String) {
        guard let base = accountsDirURL, !selectedFolder.isEmpty else { return (false, "No month selected.") }
        let reportName = "\(selectedFolder)_Report.xlsx"
        let sourceURL = base.appendingPathComponent(selectedFolder).appendingPathComponent(reportName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return (false, "Report not found. Create a report first.") }
        do {
            if fm.fileExists(atPath: destinationURL.path) { try fm.removeItem(at: destinationURL) }
            try fm.copyItem(at: sourceURL, to: destinationURL)
            return (true, "Saved to \(destinationURL.lastPathComponent)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Copy the current month's report to the user's Desktop. Returns (success, message).
    func exportReportToDesktop() -> (success: Bool, message: String) {
        guard !selectedFolder.isEmpty else { return (false, "Select a month first.") }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let name = "\(selectedFolder)_Report.xlsx"
        let dest = desktop.appendingPathComponent(name)
        return exportReport(to: dest)
    }

    /// Present Save panel for backup zip; on OK creates zip and updates status.
    func exportBackupWithSavePanel() {
        let panel = NSSavePanel()
        panel.title = "Export Backup"
        panel.nameFieldStringValue = "ExpenseReports-Backup-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            let r = self.exportBackup(to: url)
            self.statusMessage = r.success ? "✓ \(r.message)" : "✗ \(r.message)"
        }
    }

    /// Present Open panel to choose a backup zip; on OK restores and updates status.
    func restoreBackupWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Restore from Backup"
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            let r = self.restoreBackup(from: url)
            self.statusMessage = r.success ? "✓ \(r.message)" : "✗ \(r.message)"
        }
    }

    /// Create a zip of the entire Accounts folder and save to the given URL. Returns (success, message).
    func exportBackup(to destinationURL: URL) -> (success: Bool, message: String) {
        guard let base = accountsDirURL else { return (false, "Data folder not found.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", base.path, destinationURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return (true, "Backup saved to \(destinationURL.lastPathComponent)")
            }
            return (false, "Backup failed (exit \(process.terminationStatus)).")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Restore from a backup zip: expand into a temp dir, then replace Accounts contents (or merge). Returns (success, message).
    func restoreBackup(from sourceURL: URL) -> (success: Bool, message: String) {
        guard let base = accountsDirURL else { return (false, "Data folder not found.") }
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return (false, "Backup file not found.") }
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", "-q", sourceURL.path, "-d", tempDir.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                try? fm.removeItem(at: tempDir)
                return (false, "Could not read backup file.")
            }
            // unzip often creates one top-level folder; find the first folder that looks like our data
            let contents = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            let sourceRoot: URL
            if let single = contents.first, contents.count == 1,
               (try? single.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                sourceRoot = single
            } else {
                sourceRoot = tempDir
            }
            // Copy contents into Accounts (overwrite)
            for item in try fm.contentsOfDirectory(at: sourceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                let dest = base.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: item, to: dest)
            }
            try fm.removeItem(at: tempDir)
            refreshFolders()
            return (true, "Backup restored. Refreshed folder list.")
        } catch {
            try? fm.removeItem(at: tempDir)
            return (false, error.localizedDescription)
        }
    }
}
