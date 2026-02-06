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

    var body: some Scene {
        WindowGroup("Monthly Reports") {
            ContentView()
                .environmentObject(helper)
                .alert("Uninstall ExpenseReports?", isPresented: $showUninstallAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Uninstall", role: .destructive) {
                        UninstallHelper.scheduleUninstallThenQuit()
                    }
                } message: {
                    Text("This will remove ExpenseReports and all its data. The app will quit.")
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 540, height: 480)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Uninstall ExpenseReports…") {
                    showUninstallAlert = true
                }
            }
            CommandMenu("Reports") {
                Button("Merge & create report") {
                    helper.mergeThenGenerate()
                }
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
}
