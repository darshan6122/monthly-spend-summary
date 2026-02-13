//
//  SettingsView.swift
//  ExpenseReports
//
//  Single Settings screen: preferences, data management, backup/restore.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var helper: AccountsHelper
    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]
    @AppStorage("ExpenseReports.showTips") private var showTips = true
    @AppStorage("ExpenseReports.openFolderAfterReport") private var openFolderAfterReport = true
    @AppStorage("ExpenseReports.remindEndOfMonth") private var remindEndOfMonth = false

    @State private var showResetAlert = false
    @State private var showRestorePicker = false
    @State private var restoreMessage: String?
    @State private var showRestoreAlert = false

    var body: some View {
        Form {
            Section("Preferences") {
                Toggle("Open folder after report", isOn: $openFolderAfterReport)
                Toggle("Show tips", isOn: $showTips)
                Toggle("Remind me at start of month to run report", isOn: $remindEndOfMonth)
                    .onChange(of: remindEndOfMonth) { _, newValue in
                        if newValue { AccountsHelper.scheduleMonthlyReminder() }
                        else { AccountsHelper.cancelMonthlyReminder() }
                    }
                Toggle("Watch Downloads for new bank CSV", isOn: Binding(
                    get: { AppSettings.watchDownloadsFolder },
                    set: { AppSettings.watchDownloadsFolder = $0; helper.updateDownloadsWatcher() }
                ))
                .onAppear { helper.updateDownloadsWatcher() }
            }

            Section("Data Management") {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Backup (JSON)", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)

                Button {
                    showRestorePicker = true
                } label: {
                    Label("Restore from Backup", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            try BackupManager.restoreBackup(from: url, context: modelContext)
                            restoreMessage = "Restore complete."
                            showRestoreAlert = true
                        } catch {
                            restoreMessage = "Restore failed: \(error.localizedDescription)"
                            showRestoreAlert = true
                        }
                    case .failure(let error):
                        restoreMessage = "Could not open file: \(error.localizedDescription)"
                        showRestoreAlert = true
                    }
                }

                Button(role: .destructive) { showResetAlert = true } label: {
                    Label("Reset All Data", systemImage: "trash")
                }
                .buttonStyle(.plain)
            }

            Section("Tax Season") {
                Button {
                    let csvData = TaxExporter.generateTaxCSV(transactions: allTransactions)
                    saveCSVFile(csvData: csvData)
                } label: {
                    Label("Export Tax-Deductible CSV", systemImage: "arrow.up.doc.fill")
                }
                .buttonStyle(.plain)
            }

            Section("About") {
                Text("ExpenseReports (Finance OS)")
                Text("SwiftData & SwiftUI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .alert("Reset All Data?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { deleteAllData() }
        } message: {
            Text("This will permanently delete all transactions, rules, budgets, and subscriptions. This cannot be undone.")
        }
        .alert("Restore", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) { restoreMessage = nil }
        } message: {
            if let msg = restoreMessage { Text(msg) }
        }
    }

    private func exportBackup() {
        guard let tempURL = BackupManager.createBackup(context: modelContext) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = tempURL.lastPathComponent
        panel.message = "Save your backup (transactions, rules, budgets, subscriptions) as JSON."
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: tempURL, to: dest)
        }
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func deleteAllData() {
        func deleteAll<T: PersistentModel>(_ type: T.Type) {
            let descriptor = FetchDescriptor<T>()
            let items = (try? modelContext.fetch(descriptor)) ?? []
            for item in items { modelContext.delete(item) }
        }
        deleteAll(Transaction.self)
        deleteAll(CategoryRule.self)
        deleteAll(Budget.self)
        deleteAll(RecurringItem.self)
        deleteAll(CategoryItem.self)
        deleteAll(Account.self)
        try? modelContext.save()
    }

    private func saveCSVFile(csvData: String) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "Tax_Report_\(Calendar.current.component(.year, from: Date())).csv"
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                try? csvData.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
