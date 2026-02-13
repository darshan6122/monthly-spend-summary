//
//  AccountsHelper.swift
//  ExpenseReports
//
//  Uses a fixed app folder for month data and runs the Python report/merge scripts.
//

import Combine
import CoreText
import Foundation
import AppKit
import UniformTypeIdentifiers
import UserNotifications

final class AccountsHelper: ObservableObject {
    private static let monthlyReminderID = "ExpenseReports.monthlyReportReminder"

    @Published var monthFolders: [String] = []
    @Published var selectedFolder: String = ""
    @Published var statusMessage: String = ""
    @Published var isWorking: Bool = false
    @Published var stepMessage: String = ""
    @Published var lastScriptOutput: String = ""
    /// True when the last script run failed (non-zero exit). Used to show "Script failed" in Log.
    @Published var lastScriptFailed: Bool = false
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
    /// Path to the last generated PDF report (from generate_spending_report_pdf_FULL.py when present).
    @Published var lastPDFPath: URL?
    /// When set to true, the UI should present the in-app report summary sheet (no Excel needed).
    @Published var requestShowReportSummary: Bool = false
    /// When set to true, the UI should run subscription scan (e.g. from View menu ⌘R).
    @Published var requestSubscriptionScan: Bool = false
    /// When Downloads watcher finds a new cibc*.csv, set here; UI shows "Move to [Current Month]?" and clears on action.
    @Published var detectedDownloadedCSV: URL?

    private var accountsDirURL: URL?
    private var downloadsWatcherTimer: Timer?
    private var downloadedCSVNotifiedPaths: Set<String> = []

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
        if AppSettings.watchDownloadsFolder {
            DispatchQueue.main.async { [weak self] in self?.updateDownloadsWatcher() }
        }
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
            setupInstructions = "Copy the Scripts folder and .venv from Desktop/ACCOUNTS/ExpenseReports into the data folder (Open Data Folder), then add month folders with your CSVs."
        } else {
            setupInstructions = ""
        }
    }

    /// Project root: all app scripts and assets live under Desktop/ACCOUNTS/ExpenseReports.
    /// Copy scripts from ExpenseReports/Scripts and .venv from ExpenseReports into the app's data folder.
    func copySetupFromDesktop() -> (success: Bool, message: String) {
        guard let dest = accountsDirURL else { return (false, "Accounts folder not found.") }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        // Canonical project location: ~/Desktop/ACCOUNTS/ExpenseReports
        let projectRoot = home.appendingPathComponent("Desktop/ACCOUNTS/ExpenseReports", isDirectory: true)
        let scriptsDir = projectRoot.appendingPathComponent("Scripts", isDirectory: true)
        guard fm.fileExists(atPath: projectRoot.path) else {
            return (false, "Desktop/ACCOUNTS/ExpenseReports folder not found.")
        }
        guard fm.fileExists(atPath: scriptsDir.path) else {
            return (false, "ExpenseReports/Scripts folder not found.")
        }
        let scriptNames = ["make_monthly_report.py", "merge_and_categorize.py", "pdf_to_csv.py"]
        for name in scriptNames {
            let src = scriptsDir.appendingPathComponent(name, isDirectory: false)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dest.appendingPathComponent(name, isDirectory: false)
            do {
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.copyItem(at: src, to: dst)
            } catch {
                return (false, "Failed to copy \(name): \(error.localizedDescription)")
            }
        }
        // Copy .venv from ExpenseReports or from Desktop/ACCOUNTS
        let venvInProject = projectRoot.appendingPathComponent(".venv", isDirectory: true)
        let venvInAccounts = home.appendingPathComponent("Desktop/ACCOUNTS/.venv", isDirectory: true)
        let venvSrc = fm.fileExists(atPath: venvInProject.path) ? venvInProject : venvInAccounts
        if fm.fileExists(atPath: venvSrc.path) {
            let venvDst = dest.appendingPathComponent(".venv", isDirectory: true)
            do {
                if fm.fileExists(atPath: venvDst.path) { try fm.removeItem(at: venvDst) }
                try fm.copyItem(at: venvSrc, to: venvDst)
            } catch {
                return (false, "Failed to copy .venv: \(error.localizedDescription)")
            }
        }
        updateSetupInstructions(dir: dest)
        loadMonthFolders(from: dest)
        return (true, "Copied from Desktop/ACCOUNTS/ExpenseReports.")
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

    private func runScript(name: String, folder: String, useMergedCategories: Bool = false) -> (success: Bool, message: String) {
        guard let base = accountsDirURL else { return (false, "ACCOUNTS folder not found.") }
        let scriptURL = base.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            DispatchQueue.main.async { [weak self] in
                self?.errorRecoveryHint = "Copy the Scripts folder from Desktop/ACCOUNTS/ExpenseReports into the data folder (Open Data Folder → paste script files)."
            }
            return (false, "Copy Scripts from Desktop/ACCOUNTS/ExpenseReports into the data folder.")
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
        if useMergedCategories { exports += "export USE_MERGED_CATEGORIES=1; " }
        if name == "merge_and_categorize.py" {
            let threshold = String(format: "%.2f", max(0, min(1, AppSettings.mlConfidenceThreshold)))
            exports += "export ML_CONFIDENCE_THRESHOLD='\(threshold)'; "
        }
        if let venv = venvPath {
            exports += "export VIRTUAL_ENV='\(shellEscape(venv))'; "
            if let sitePackages = venvSitePackages(venvPath: venv) {
                exports += "export PYTHONPATH='\(shellEscape(sitePackages))'; "
            }
        }
        let cmd = "\(exports)exec '\(shellEscape(pythonPath))' '\(shellEscape(scriptURL.path))' '\(shellEscape(folder))'"
        return runProcessWithOutput(cwd: base, command: cmd)
    }

    /// Run a shell command and return (success, stdout message). Used by runScript and runPDFToCSV.
    private func runProcessWithOutput(cwd: URL, command: String) -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = cwd
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
                self?.lastScriptFailed = (process.terminationStatus != 0)
            }
            if process.terminationStatus == 0 {
                return (true, out.isEmpty ? "Done." : out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return (false, err.isEmpty ? out : err)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Run pdf_to_csv.py to extract table from PDF; creates month folder and writes cibc_pdf_export.csv. Returns (success, message, monthFolderName?).
    func importDroppedPDF(_ url: URL) -> (success: Bool, message: String, monthFolder: String?) {
        guard url.isFileURL, let base = accountsDirURL else { return (false, "Invalid file or Accounts folder missing.", nil) }
        let path = url.path
        guard path.lowercased().hasSuffix(".pdf") else { return (false, "Not a PDF file.", nil) }
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return (false, "File not found.", nil) }
        let scriptURL = base.appendingPathComponent("pdf_to_csv.py")
        guard fm.fileExists(atPath: scriptURL.path) else {
            return (false, "Copy Scripts (pdf_to_csv.py) into the data folder. Install: pip install pdfplumber", nil)
        }
        guard let (pythonPath, venvPath) = findWorkingPython(base: base) else {
            return (false, "No Python found. Install Python and pdfplumber.", nil)
        }
        var exports = "export EXPENSE_REPORTS_ACCOUNTS_DIR='\(shellEscape(base.path))'; "
        if let venv = venvPath {
            exports += "export VIRTUAL_ENV='\(shellEscape(venv))'; "
            if let sitePackages = venvSitePackages(venvPath: venv) {
                exports += "export PYTHONPATH='\(shellEscape(sitePackages))'; "
            }
        }
        let cmd = "\(exports)exec '\(shellEscape(pythonPath))' '\(shellEscape(scriptURL.path))' '\(shellEscape(path))'"
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
            let out = String(data: outData, encoding: .utf8) ?? ""
            let monthLine = out.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
            if process.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: errData, encoding: .utf8) ?? ""
                return (false, err.isEmpty ? "PDF extraction failed." : err, nil)
            }
            loadMonthFolders(from: base)
            if !monthFolders.contains(monthLine) { monthFolders.append(monthLine); monthFolders.sort() }
            selectedFolder = monthLine
            statusMessage = "✓ PDF imported to \(monthLine)."
            return (true, "Imported to \(monthLine).", monthLine)
        } catch {
            return (false, error.localizedDescription, nil)
        }
    }

    /// Export a zip of the Accounts folder with all CSV description columns replaced by "Vendor 1", "Vendor 2", etc. (stable by content). Saves to destinationURL.
    func exportAnonymizedForDebugging(destinationURL: URL) -> (success: Bool, message: String) {
        guard let base = accountsDirURL else { return (false, "Accounts folder not found.") }
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("ExpenseReports_anon_\(UUID().uuidString.prefix(8))")
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return (false, "Could not create temp dir: \(error.localizedDescription)")
        }
        defer { try? fm.removeItem(at: tempDir) }
        var descToVendor: [String: String] = [:]
        /// Description column index (0-based) from header; -1 if not found.
        func descriptionColumnIndex(from headerLine: String) -> Int {
            let lower = headerLine.lowercased()
            if lower.contains("description") { return 1 }
            let parts = headerLine.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if let i = parts.firstIndex(where: { $0.lowercased().contains("desc") }) { return i }
            return parts.count >= 2 ? 1 : -1
        }
        func anonymizeCSV(source: URL, dest: URL) {
            guard let content = try? String(contentsOf: source, encoding: .utf8) else { return }
            let lines = content.components(separatedBy: .newlines)
            guard !lines.isEmpty else { return }
            let header = lines[0]
            let descIdx = descriptionColumnIndex(from: header)
            if descIdx < 0 { try? content.write(to: dest, atomically: true, encoding: .utf8); return }
            var out: [String] = [header]
            for line in lines.dropFirst() {
                if line.isEmpty { out.append(line); continue }
                var parts = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                if descIdx < parts.count {
                    let orig = parts[descIdx]
                    let label = descToVendor[orig] ?? {
                        let n = descToVendor.count + 1
                        let v = "Vendor \(n)"
                        descToVendor[orig] = v
                        return v
                    }()
                    parts[descIdx] = label
                }
                out.append(parts.joined(separator: ","))
            }
            try? out.joined(separator: "\n").write(to: dest, atomically: true, encoding: .utf8)
        }
        func copyTree(src: URL, dest: URL) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { return }
            if isDir.boolValue {
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
                (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil))?.forEach { child in
                    copyTree(src: child, dest: dest.appendingPathComponent(child.lastPathComponent))
                }
            } else {
                if src.pathExtension.lowercased() == "csv" {
                    anonymizeCSV(source: src, dest: dest)
                } else {
                    try? fm.copyItem(at: src, to: dest)
                }
            }
        }
        copyTree(src: base, dest: tempDir)
        let zipURL = fm.temporaryDirectory.appendingPathComponent("ExpenseReports_debug_\(UUID().uuidString.prefix(8)).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", zipURL.path, "."]
        process.currentDirectoryURL = tempDir
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                try? fm.removeItem(at: zipURL)
                return (false, "zip failed.")
            }
            if fm.fileExists(atPath: destinationURL.path) { try? fm.removeItem(at: destinationURL) }
            try fm.moveItem(at: zipURL, to: destinationURL)
            return (true, "Exported to \(destinationURL.lastPathComponent)")
        } catch {
            try? fm.removeItem(at: zipURL)
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
            let reportResult = self.runScript(name: "make_monthly_report.py", folder: self.selectedFolder, useMergedCategories: true)
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
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        self?.runPDFScriptIfPresent(folder: folderName)
                    }
                } else {
                    self.statusMessage = "✗ \(reportResult.message)"
                }
            }
        }
    }

    /// If generate_spending_report_pdf_FULL.py exists in Accounts folder, run it for the given folder and set lastPDFPath (on main).
    private func runPDFScriptIfPresent(folder: String) {
        guard let base = accountsDirURL else { return }
        let scriptURL = base.appendingPathComponent("generate_spending_report_pdf_FULL.py", isDirectory: false)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { return }
        let result = runScript(name: "generate_spending_report_pdf_FULL.py", folder: folder)
        if result.success {
            let candidate = base.appendingPathComponent(folder).appendingPathComponent("\(folder)_Report.pdf", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                DispatchQueue.main.async { [weak self] in
                    self?.lastPDFPath = candidate
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
            let result = self?.runScript(name: "make_monthly_report.py", folder: self?.selectedFolder ?? "", useMergedCategories: true) ?? (success: false, message: "Error")
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
                    Self.sendMergeCompleteNotification(month: self?.selectedFolder ?? "")
                }
            }
        }
    }

    private static func sendMergeCompleteNotification(month: String) {
        if !UserDefaults.standard.bool(forKey: hasRequestedNotificationKey) {
            UserDefaults.standard.set(true, forKey: hasRequestedNotificationKey)
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "Merge complete"
        content.body = "\(month): CSVs merged and categorized."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "merge-\(UUID().uuidString)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        UNUserNotificationCenter.current().add(request)
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

    /// Import a dropped CSV: detect month from first date in file (or file creation date), create month folder if needed, copy file as cibc*.csv.
    func importDroppedCSV(_ url: URL) -> (success: Bool, message: String) {
        guard url.isFileURL, let base = accountsDirURL else { return (false, "Invalid file or Accounts folder missing.") }
        let path = url.path
        guard path.lowercased().hasSuffix(".csv") else { return (false, "Not a CSV file.") }
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return (false, "File not found.") }

        let folderName: String
        if let fromContent = parseFirstDateFromCSV(at: url) {
            folderName = monthFolderName(from: fromContent)
        } else if let attrs = try? fm.attributesOfItem(atPath: path), let created = attrs[.creationDate] as? Date {
            folderName = monthFolderName(from: created)
        } else {
            folderName = monthFolderName(from: Date())
        }

        let monthURL = base.appendingPathComponent(folderName, isDirectory: true)
        do {
            if !fm.fileExists(atPath: monthURL.path) {
                try fm.createDirectory(at: monthURL, withIntermediateDirectories: true)
            }
            let baseName = url.deletingPathExtension().lastPathComponent
            let destName = baseName.lowercased().hasPrefix("cibc") ? url.lastPathComponent : "cibc_\(baseName).csv"
            let destURL = monthURL.appendingPathComponent(destName)
            if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
            try fm.copyItem(at: url, to: destURL)
        } catch {
            return (false, "Failed to copy: \(error.localizedDescription)")
        }
        loadMonthFolders(from: base)
        if !monthFolders.contains(folderName) { monthFolders.append(folderName); monthFolders.sort() }
        selectedFolder = folderName
        statusMessage = "✓ Imported to \(folderName)."
        return (true, "Imported to \(folderName).")
    }

    private func parseFirstDateFromCSV(at url: URL) -> Date? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        let header = lines[0]
        let firstData = lines[1]
        let headerParts = header.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
        let dateIdx = headerParts.firstIndex { $0.contains("date") } ?? 0
        let dataParts = firstData.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard dateIdx < dataParts.count else { return nil }
        let dateStr = dataParts[dateIdx].trimmingCharacters(in: .whitespaces)
        let formatters: [DateFormatter] = [
            { let f = DateFormatter(); f.dateFormat = "MM/dd/yyyy"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
            { let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
            { let f = DateFormatter(); f.dateFormat = "M/d/yyyy"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
        ]
        for formatter in formatters {
            if let d = formatter.date(from: dateStr) { return d }
        }
        return nil
    }

    private func monthFolderName(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date).uppercased()
    }

    /// Regenerate merge + report for every month folder. Runs on background; updates stepMessage and statusMessage on main.
    func batchRegenerateAllReports() {
        guard accountsDirURL != nil else {
            statusMessage = "Accounts folder not found."
            return
        }
        let folders = monthFolders
        guard !folders.isEmpty else {
            statusMessage = "No month folders to process."
            return
        }
        isWorking = true
        lastFailedAction = { [weak self] in self?.batchRegenerateAllReports() }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var done = 0
            var failed: String?
            for (idx, folder) in folders.enumerated() {
                DispatchQueue.main.async { self.stepMessage = "Processing \(folder) (\(idx + 1)/\(folders.count))…" }
                let mergeResult = self.runScript(name: "merge_and_categorize.py", folder: folder)
                if !mergeResult.success {
                    failed = "\(folder): \(mergeResult.message)"
                    break
                }
                let reportResult = self.runScript(name: "make_monthly_report.py", folder: folder, useMergedCategories: true)
                if !reportResult.success {
                    failed = "\(folder) report: \(reportResult.message)"
                    break
                }
                done += 1
            }
            DispatchQueue.main.async {
                self.isWorking = false
                self.stepMessage = ""
                self.lastFailedAction = failed == nil ? nil : { self.batchRegenerateAllReports() }
                self.refreshFolders()
                self.statusMessage = failed.map { "✗ \($0)" } ?? "✓ Regenerated \(done) report(s)."
            }
        }
    }

    /// Start or stop watching ~/Downloads for new cibc*.csv based on AppSettings.watchDownloadsFolder.
    func updateDownloadsWatcher() {
        if AppSettings.watchDownloadsFolder {
            startDownloadsWatcher()
        } else {
            stopDownloadsWatcher()
        }
    }

    private func startDownloadsWatcher() {
        stopDownloadsWatcher()
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let dir = downloads else { return }
        downloadsWatcherTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollDownloadsForCSV(downloadsDir: dir)
        }
        RunLoop.main.add(downloadsWatcherTimer!, forMode: .common)
        pollDownloadsForCSV(downloadsDir: dir)
    }

    private func stopDownloadsWatcher() {
        downloadsWatcherTimer?.invalidate()
        downloadsWatcherTimer = nil
    }

    private func pollDownloadsForCSV(downloadsDir: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        let cibcCSVs = contents.filter { $0.lastPathComponent.lowercased().hasPrefix("cibc") && $0.lastPathComponent.lowercased().hasSuffix(".csv") }
        for url in cibcCSVs {
            let path = url.path
            if !downloadedCSVNotifiedPaths.contains(path) {
                downloadedCSVNotifiedPaths.insert(path)
                DispatchQueue.main.async { [weak self] in
                    self?.detectedDownloadedCSV = url
                }
                return
            }
        }
    }

    /// Call after user moves or dismisses the detected CSV prompt; clears detectedDownloadedCSV.
    func clearDetectedDownloadedCSV() {
        detectedDownloadedCSV = nil
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

    /// URL of the current month's Excel report, if it exists.
    func currentReportURL() -> URL? {
        guard let base = accountsDirURL, !selectedFolder.isEmpty else { return nil }
        let url = base.appendingPathComponent(selectedFolder).appendingPathComponent("\(selectedFolder)_Report.xlsx")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Open the selected month's report .xlsx in the default app (Numbers, Excel, etc.). Tries Numbers if default fails.
    /// - Returns: true if opened successfully, false otherwise (e.g. no app to open .xlsx).
    @discardableResult
    func openPDFReport() -> Bool {
        guard let url = lastPDFPath, FileManager.default.fileExists(atPath: url.path) else { return false }
        return NSWorkspace.shared.open(url)
    }

    func openReportFile() -> Bool {
        let url = currentReportURL() ?? lastReportPath
        guard let reportURL = url, FileManager.default.fileExists(atPath: reportURL.path) else { return false }
        if NSWorkspace.shared.open(reportURL) { return true }
        if let numbersURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Numbers") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([reportURL], withApplicationAt: numbersURL, configuration: config)
            return true
        }
        return false
    }

    /// Open the last successfully generated report (from menu or UI).
    @discardableResult
    func openLastReport() -> Bool {
        guard let url = lastReportPath, FileManager.default.fileExists(atPath: url.path) else { return false }
        if NSWorkspace.shared.open(url) { return true }
        if let numbersURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Numbers") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: numbersURL, configuration: config)
            return true
        }
        return false
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

    // MARK: - Insights: merged CSV, audit, month summary, custom mapping

    /// Report file modification date for a month folder, if the report exists.
    func reportDate(monthFolder: String) -> Date? {
        guard let url = currentReportURL(monthFolder: monthFolder) else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }

    private func currentReportURL(monthFolder: String) -> URL? {
        guard let base = accountsDirURL, !monthFolder.isEmpty else { return nil }
        let url = base.appendingPathComponent(monthFolder).appendingPathComponent("\(monthFolder)_Report.xlsx")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func mergedCSVURL() -> URL? {
        mergedCSVURL(monthFolder: selectedFolder)
    }

    func mergedCSVURL(monthFolder: String) -> URL? {
        guard let base = accountsDirURL, !monthFolder.isEmpty else { return nil }
        let url = base.appendingPathComponent(monthFolder).appendingPathComponent("merged.csv")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func auditJSONURL() -> URL? {
        guard let base = accountsDirURL, !selectedFolder.isEmpty else { return nil }
        let url = base.appendingPathComponent(selectedFolder).appendingPathComponent("audit.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func monthSummaryURL(monthFolder: String) -> URL? {
        guard let base = accountsDirURL else { return nil }
        let url = base.appendingPathComponent(monthFolder).appendingPathComponent("month_summary.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func customMappingURL() -> URL? {
        guard let base = accountsDirURL else { return nil }
        return base.appendingPathComponent("custom_mapping.json")
    }

    func transactionSplitsURL(monthFolder: String) -> URL? {
        guard let base = accountsDirURL, !monthFolder.isEmpty else { return nil }
        return base.appendingPathComponent(monthFolder).appendingPathComponent("transaction_splits.json")
    }

    func loadTransactionSplits(monthFolder: String) -> TransactionSplitsMap {
        guard let url = transactionSplitsURL(monthFolder: monthFolder),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TransactionSplitsMap.self, from: data) else { return [:] }
        return decoded
    }

    func saveTransactionSplits(monthFolder: String, splits: TransactionSplitsMap) {
        guard let url = transactionSplitsURL(monthFolder: monthFolder),
              let data = try? JSONEncoder().encode(splits) else { return }
        try? data.write(to: url)
    }

    /// Generate tax/export packet: selected categories, all months, output CSV or simple PDF path.
    func generateTaxReport(categories: Set<String>, outputURL: URL, asCSV: Bool) -> (success: Bool, message: String) {
        guard accountsDirURL != nil else { return (false, "Data folder not found.") }
        var rows: [(month: String, category: String, amount: Double)] = []
        for name in monthFolders {
            guard let summary = loadMonthSummary(monthFolder: name) else { continue }
            for (cat, amt) in summary.byCategory where categories.contains(cat) && amt > 0 {
                rows.append((name, cat, amt))
            }
        }
        if asCSV {
            var csv = "Month,Category,Amount\n"
            for r in rows { csv += "\(r.month),\(r.category),\(r.amount)\n" }
            guard let data = csv.data(using: .utf8) else { return (false, "Encoding failed.") }
            do {
                try data.write(to: outputURL)
                return (true, "Saved to \(outputURL.lastPathComponent)")
            } catch {
                return (false, error.localizedDescription)
            }
        }
        return (false, "PDF export not implemented; use CSV.")
    }

    /// Schedule a repeating notification for the 1st of each month at 9:00 (remind to run report).
    static func scheduleMonthlyReminder() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: [monthlyReminderID])
            let content = UNMutableNotificationContent()
            content.title = "Monthly Reports"
            content.body = "Reminder: run your monthly report for last month."
            content.sound = .default
            var date = DateComponents()
            date.day = 1
            date.hour = 9
            date.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            let request = UNNotificationRequest(identifier: monthlyReminderID, content: content, trigger: trigger)
            center.add(request)
        }
    }

    /// Remove the monthly reminder notification.
    static func cancelMonthlyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [monthlyReminderID])
    }

    func loadAuditInfo() -> AuditInfo? {
        guard let url = auditJSONURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AuditInfo.self, from: data)
    }

    func loadMonthSummary(monthFolder: String) -> MonthSummary? {
        guard let url = monthSummaryURL(monthFolder: monthFolder), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MonthSummary.self, from: data)
    }

    /// Add unspent budget (limit - spent) per category to rollover for next month. Call after reviewing a month.
    func applyRolloverFromMonth(monthFolder: String) -> (applied: Bool, message: String) {
        guard AppSettings.enableBudgetRollover else { return (false, "Enable Budget Rollover in Settings first.") }
        guard let summary = loadMonthSummary(monthFolder: monthFolder) else { return (false, "No summary for \(monthFolder).") }
        var roll = AppSettings.rolloverBalances
        var added = 0
        for (category, spent) in summary.byCategory {
            guard let limit = AppSettings.budgetLimits[category], limit > 0, spent < limit else { continue }
            let unspent = limit - spent
            roll[category, default: 0] += unspent
            added += 1
        }
        if added == 0 { return (true, "No unspent budget to roll over for \(monthFolder).") }
        AppSettings.rolloverBalances = roll
        return (true, "Rolled over unspent from \(monthFolder) for \(added) categor\(added == 1 ? "y" : "ies").")
    }

    func loadDeltaInsight() -> DeltaInsight? {
        guard !selectedFolder.isEmpty, let current = loadMonthSummary(monthFolder: selectedFolder) else { return nil }
        let prevIdx = monthFolders.firstIndex(of: selectedFolder).map { $0 - 1 }
        let prevMonth = prevIdx.map { $0 >= 0 ? monthFolders[$0] : nil } ?? nil
        let prevSummary = prevMonth.flatMap { loadMonthSummary(monthFolder: $0) }

        var spendingDeltaMessage: String?
        var spendingDeltaPercent: Double?
        if let prev = prevSummary, prev.totalSpent > 0 {
            let pct = ((current.totalSpent - prev.totalSpent) / prev.totalSpent) * 100
            spendingDeltaPercent = pct
            if pct > 0 { spendingDeltaMessage = "You spent \(Int(round(pct)))% more than last month." }
            else if pct < 0 { spendingDeltaMessage = "You spent \(Int(round(-pct)))% less than last month." }
            else { spendingDeltaMessage = "Spending even with last month." }
        } else if prevMonth == nil { spendingDeltaMessage = "First month — no comparison yet." }

        var categoryAlert: (category: String, delta: Double)?
        if let prev = prevSummary {
            for (cat, currAmt) in current.byCategory where currAmt > 0 {
                let prevAmt = prev.byCategory[cat] ?? 0
                if currAmt - prevAmt > 50 {
                    categoryAlert = (cat, currAmt - prevAmt)
                    break
                }
            }
        }

        return DeltaInsight(
            spendingDeltaPercent: spendingDeltaPercent,
            spendingDeltaMessage: spendingDeltaMessage,
            categoryAlert: categoryAlert,
            savingsTransfer: current.savingsTransfer > 0 ? current.savingsTransfer : nil
        )
    }

    /// Last N months’ spending per category (for sparklines). Returns category -> [amount for oldest month ... newest].
    func loadCategoryTrends(lastNMonths: Int = 6) -> [String: [Double]] {
        let folders = Array(monthFolders.suffix(lastNMonths))
        var out: [String: [Double]] = [:]
        for (idx, name) in folders.enumerated() {
            guard let s = loadMonthSummary(monthFolder: name) else { continue }
            for (cat, amt) in s.byCategory where amt > 0 {
                if out[cat] == nil { out[cat] = Array(repeating: 0, count: folders.count) }
                out[cat]?[idx] = amt
            }
        }
        return out
    }

    /// Spending by day in selected month (for calendar heatmap). Key = day of month (1-31).
    func loadDailySpending(monthFolder: String) -> [Int: Double] {
        let tx = loadMergedTransactions(monthFolder: monthFolder)
        let formatters: [DateFormatter] = [
            { let f = DateFormatter(); f.dateFormat = "MM/dd/yyyy"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }(),
            { let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f }(),
        ]
        var byDay: [Int: Double] = [:]
        for t in tx where t.amount < 0 {
            var dayNum: Int?
            for fmt in formatters {
                if let d = fmt.date(from: t.date) {
                    dayNum = Calendar.current.component(.day, from: d)
                    break
                }
            }
            if let d = dayNum, d >= 1, d <= 31 {
                byDay[d, default: 0] += abs(t.amount)
            }
        }
        return byDay
    }

    /// Recurring: same amount in 2+ months (subscription hunter). Returns (description_or_amount_key, amount, months).
    func loadRecurringSubscriptions() -> [(key: String, amount: Double, months: [String])] {
        var amountToDescs: [Double: [String: Set<String>]] = [:]
        for name in monthFolders {
            let tx = loadMergedTransactions(monthFolder: name)
            for t in tx where t.amount < 0 {
                let amt = abs(t.amount)
                let desc = t.description.isEmpty ? "?" : String(t.description.prefix(40))
                if amountToDescs[amt] == nil { amountToDescs[amt] = [:] }
                if amountToDescs[amt]![desc] == nil { amountToDescs[amt]![desc] = Set() }
                amountToDescs[amt]![desc]!.insert(name)
            }
        }
        var result: [(key: String, amount: Double, months: [String])] = []
        for (amt, descToMonths) in amountToDescs {
            for (desc, months) in descToMonths where months.count >= 2 {
                result.append((desc, amt, Array(months).sorted()))
            }
        }
        result.sort { $0.amount > $1.amount }
        return result
    }

    /// Estimated subscriptions due in the next 7 days (by typical day-of-month from history). Returns (total amount, list of (desc, amount)).
    func subscriptionsDueInNext7Days() -> (total: Double, items: [(desc: String, amount: Double)]) {
        let subs = loadRecurringSubscriptions()
        let cal = Calendar.current
        let today = Date()
        let next7Days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let daysSet = Set(next7Days.map { cal.component(.day, from: $0) })
        var estimatedDayByKey: [String: Int] = [:]
        for (key, amount, months) in subs {
            guard let lastMonth = months.last else { continue }
            let tx = loadMergedTransactions(monthFolder: lastMonth)
            guard let t = tx.first(where: { abs($0.amount) == amount && (key == "?" || String($0.description.prefix(40)) == key) }) else {
                estimatedDayByKey[key] = 15
                continue
            }
            let day = t.date.split(separator: "-").last.flatMap { Int(String($0)) } ?? 15
            estimatedDayByKey[key] = day
        }
        var items: [(desc: String, amount: Double)] = []
        for (key, amount, _) in subs {
            let day = estimatedDayByKey[key] ?? 15
            if daysSet.contains(day) {
                items.append((key, amount))
            }
        }
        let total = items.reduce(0) { $0 + $1.amount }
        return (total, items)
    }

    /// Merchant YoY: compare avg transaction amount for same merchant (description substring) across years.
    func loadMerchantYoY() -> [(merchant: String, year1: Int, year2: Int, avg1: Double, avg2: Double)] {
        var byMerchantYear: [String: [Int: [Double]]] = [:]
        for name in monthFolders {
            let parts = name.split(separator: " ")
            guard parts.count >= 2, let y = Int(parts.last ?? "0") else { continue }
            let tx = loadMergedTransactions(monthFolder: name)
            for t in tx where t.amount < 0 {
                let merchant = String(t.description.prefix(30)).trimmingCharacters(in: .whitespaces)
                if merchant.isEmpty { continue }
                if byMerchantYear[merchant] == nil { byMerchantYear[merchant] = [:] }
                if byMerchantYear[merchant]![y] == nil { byMerchantYear[merchant]![y] = [] }
                byMerchantYear[merchant]![y]!.append(abs(t.amount))
            }
        }
        let calendarYear = Calendar.current.component(.year, from: Date())
        let y1 = calendarYear - 2
        let y2 = calendarYear - 1
        var result: [(merchant: String, year1: Int, year2: Int, avg1: Double, avg2: Double)] = []
        for (merchant, yearAmounts) in byMerchantYear {
            guard let a1 = yearAmounts[y1], let a2 = yearAmounts[y2], !a1.isEmpty, !a2.isEmpty else { continue }
            let avg1 = a1.reduce(0, +) / Double(a1.count)
            let avg2 = a2.reduce(0, +) / Double(a2.count)
            result.append((merchant, y1, y2, avg1, avg2))
        }
        result.sort { ($0.avg2 - $0.avg1) > ($1.avg2 - $1.avg1) }
        return result
    }

    /// Projected end-of-month spend for current selected month (if we have partial data).
    func projectedMonthSpend() -> (current: Double, projected: Double, dayOfMonth: Int, daysInMonth: Int)? {
        guard !selectedFolder.isEmpty, let summary = loadMonthSummary(monthFolder: selectedFolder) else { return nil }
        let now = Date()
        let cal = Calendar.current
        let day = cal.component(.day, from: now)
        let range = cal.range(of: .day, in: .month, for: now)
        let daysTotal = range?.count ?? 30
        guard day > 0, daysTotal > 0 else { return nil }
        let current = summary.totalSpent
        let dailyAvg = day > 0 ? current / Double(day) : 0
        let projected = dailyAvg * Double(daysTotal)
        return (current, projected, day, daysTotal)
    }

    func loadMergedTransactions() -> [MergedTransaction] {
        loadMergedTransactions(monthFolder: selectedFolder)
    }

    func loadMergedTransactions(monthFolder: String) -> [MergedTransaction] {
        guard let url = mergedCSVURL(monthFolder: monthFolder) else { return [] }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return [] }
        let headerRow = lines[0]
        let headerParts = headerRow.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
        let dateIdx = headerParts.firstIndex(where: { $0.contains("date") }) ?? 0
        let descIdx = headerParts.firstIndex(where: { $0.contains("description") || $0.contains("desc") }) ?? 1
        let amtIdx = headerParts.firstIndex(where: { $0.contains("amount") }) ?? 2
        let catIdx = headerParts.firstIndex(where: { $0.contains("category") }) ?? 3

        var result: [MergedTransaction] = []
        for line in lines.dropFirst() {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count > max(amtIdx, catIdx) else { continue }
            let amount = Double(parts[amtIdx].replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) ?? 0
            result.append(MergedTransaction(
                date: parts.count > dateIdx ? parts[dateIdx] : "",
                description: parts.count > descIdx ? parts[descIdx] : "",
                amount: amount,
                category: parts.count > catIdx ? parts[catIdx] : CategoryTypes.defaultCategory
            ))
        }
        return result
    }

    /// Category spending for Quick Look. Prefers month_summary.json (matches Excel report); falls back to merged.csv.
    func loadCategoryAmounts() -> [CategoryAmount] {
        if !selectedFolder.isEmpty, let summary = loadMonthSummary(monthFolder: selectedFolder), !summary.byCategory.isEmpty {
            return summary.byCategory
                .map { CategoryAmount(category: $0.key, amount: $0.value) }
                .sorted { $0.amount > $1.amount }
        }
        let tx = loadMergedTransactions()
        var dict: [String: Double] = [:]
        for t in tx where t.amount < 0 {
            dict[t.category, default: 0] += abs(t.amount)
        }
        return dict.map { CategoryAmount(category: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    func loadCustomMapping() -> [String: String] {
        guard let url = customMappingURL(), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    /// Saves one description→category entry. Only writes to custom_mapping.json in Accounts (never touches report or merged.csv).
    /// Backs up existing file before overwriting. Does not add "Uncategorized" entries.
    func saveCustomMappingEntry(description: String, category: String) {
        guard let url = customMappingURL() else { return }
        let key = description.trimmingCharacters(in: .whitespaces)
        if key.isEmpty { return }
        let cat = category.trimmingCharacters(in: .whitespaces)
        if cat == CategoryTypes.defaultCategory { return }
        var mapping = loadCustomMapping()
        mapping[key] = cat
        guard let data = try? JSONSerialization.data(withJSONObject: mapping, options: .prettyPrinted) else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let backup = url.deletingPathExtension().appendingPathExtension("json.backup")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
        }
        try? data.write(to: url)
    }

    /// Export custom_mapping.json to a user-chosen file (backup or use on another machine).
    func exportCustomMapping(to url: URL) -> Bool {
        let mapping = loadCustomMapping()
        guard let data = try? JSONSerialization.data(withJSONObject: mapping, options: .prettyPrinted) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// Import a JSON file (description → category) and merge into custom_mapping.json. Backs up existing first.
    func importCustomMapping(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode([String: String].self, from: data),
              let dest = customMappingURL() else { return false }
        var current = loadCustomMapping()
        for (k, v) in imported where !v.isEmpty && v.lowercased() != "uncategorized" {
            current[k] = v
        }
        guard let out = try? JSONSerialization.data(withJSONObject: current, options: .prettyPrinted) else { return false }
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            let backup = dest.deletingPathExtension().appendingPathExtension("json.backup")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: dest, to: backup)
        }
        do {
            try out.write(to: dest)
            return true
        } catch {
            return false
        }
    }
}
