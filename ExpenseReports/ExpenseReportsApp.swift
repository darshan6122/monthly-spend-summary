//
//  ExpenseReportsApp.swift
//  ExpenseReports
//
//  Created by Darshan Bodara on 2026-02-05.
//

import SwiftUI

@main
struct ExpenseReportsApp: App {
    @StateObject private var helper = AccountsHelper()
    @State private var showUninstallAlert = false
    @State private var showAbout = false
    @State private var showSettings = false

    private static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private static let releasesURL = URL(string: "https://github.com/darshan6122/monthly-spend-summary/releases")!

    var body: some Scene {
        WindowGroup("Monthly Reports") {
            ContentView(showSettings: $showSettings)
                .environmentObject(helper)
                .alert("Uninstall ExpenseReports?", isPresented: $showUninstallAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Uninstall", role: .destructive) {
                        UninstallHelper.scheduleUninstallThenQuit()
                    }
                } message: {
                    Text("This will remove ExpenseReports and all its data. The app will quit.")
                }
                .onOpenURL { url in
                    handleURL(url)
                }
                .sheet(isPresented: $showAbout) {
                    AboutView(version: Self.appVersion)
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 540, height: 480)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("About Monthly Reports…") {
                    showAbout = true
                }
                Button("Open Data Folder", systemImage: "folder") {
                    helper.openAccountsFolderInFinder()
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("View report summary", systemImage: "chart.bar.doc.horizontal") {
                    helper.requestShowReportSummary = true
                }
                .disabled(helper.selectedFolder.isEmpty)
                .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Open last report (Numbers/Excel)", systemImage: "doc.fill") {
                    if !helper.openLastReport() {
                        helper.requestShowReportSummary = true
                    }
                }
                .disabled(helper.lastReportPath == nil)
                Button("Settings…", systemImage: "gearshape") {
                    showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
                Button("Check for Updates…") {
                    NSWorkspace.shared.open(Self.releasesURL)
                }
                Divider()
                Button("Uninstall ExpenseReports…") {
                    showUninstallAlert = true
                }
            }
            CommandMenu("Reports") {
                Button("Merge & create report") {
                    helper.mergeThenGenerate()
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(helper.isWorking || helper.selectedFolder.isEmpty)

                Button("Create report only") {
                    helper.generateReport()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(helper.isWorking || helper.selectedFolder.isEmpty)

                Button("Merge bank files only") {
                    helper.mergeCSVs()
                }
                .disabled(helper.isWorking || helper.selectedFolder.isEmpty)

                if helper.lastFailedAction != nil {
                    Divider()
                    Button("Try again") {
                        helper.retryLastAction()
                    }
                    .disabled(helper.isWorking)
                }
            }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "monthlyreports" else { return }
        if url.host == "run", let month = url.path.split(separator: "/").last.map(String.init), !month.isEmpty {
            if helper.monthFolders.contains(month) {
                helper.selectedFolder = month
                helper.mergeThenGenerate()
            }
        }
    }
}

// MARK: - About
struct AboutView: View {
    let version: String
    @Environment(\.dismiss) private var dismiss
    private let releasesURL = URL(string: "https://github.com/darshan6122/monthly-spend-summary/releases")!

    var body: some View {
        VStack(spacing: 20) {
            Text("Monthly Reports")
                .font(.title.bold())
            Text("CIBC Export Processor")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Link("View releases on GitHub", destination: releasesURL)
                .font(.caption)
            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(minWidth: 280)
    }
}
