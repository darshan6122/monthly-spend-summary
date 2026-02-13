//
//  ExpenseReportsApp.swift
//  ExpenseReports
//
//  Created by Darshan Bodara on 2026-02-05.
//

import SwiftUI
import SwiftData
import Combine

@main
struct ExpenseReportsApp: App {
    let container: ModelContainer
    @StateObject private var helper = AccountsHelper()
    @State private var showUninstallAlert = false
    @State private var showAbout = false
    @StateObject private var navState = NavigationState()
    @State private var menuBarManager = MenuBarManager()

    init() {
        do {
            container = try ModelContainer(for: Transaction.self, CategoryRule.self, Budget.self, RecurringItem.self, CategoryItem.self, Account.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    private static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private static let releasesURL = URL(string: "https://github.com/darshan6122/monthly-spend-summary/releases")!

    var body: some Scene {
        WindowGroup("Finance OS") {
            ContentView(selection: $navState.selection, container: container)
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
                .onAppear {
                    menuBarManager.setupMenuBar()
                    menuBarManager.setPopoverContent(MenuBarView().modelContainer(container))
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 540, height: 480)
        .modelContainer(container)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("About Finance OS…") {
                    showAbout = true
                }
                Button("Settings…", systemImage: "gearshape") {
                    navState.selection = .settings
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
            CommandMenu("View") {
                Button("Dashboard") { navState.selection = .dashboard }
                    .keyboardShortcut(KeyboardShortcut("1", modifiers: .command))
                Button("History") { navState.selection = .transactions }
                    .keyboardShortcut(KeyboardShortcut("2", modifiers: .command))
                Button("Wealth") { navState.selection = .netWorth }
                    .keyboardShortcut(KeyboardShortcut("6", modifiers: .command))
                Button("Rules") { navState.selection = .rules }
                    .keyboardShortcut(KeyboardShortcut("3", modifiers: .command))
                Button("Recurring") { navState.selection = .subscriptions }
                    .keyboardShortcut(KeyboardShortcut("5", modifiers: .command))
                Button("Budgets") { navState.selection = .budgets }
                    .keyboardShortcut(KeyboardShortcut("4", modifiers: .command))
                Button("Categories") { navState.selection = .categories }
                    .keyboardShortcut(KeyboardShortcut("7", modifiers: .command))
                Button("Backup & Data") { navState.selection = .settings }
                    .keyboardShortcut(KeyboardShortcut("8", modifiers: .command))
                Divider()
                Button("Scan for recurring") { helper.requestSubscriptionScan = true }
                    .keyboardShortcut(KeyboardShortcut("r", modifiers: .command))
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
            Text("Finance OS")
                .font(.title.bold())
            Text("Expense Reports & Budgets")
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
