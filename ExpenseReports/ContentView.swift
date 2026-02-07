//
//  ContentView.swift
//  ExpenseReports
//
//  Created by Darshan Bodara on 2026-02-05.
//  System Utility–style UI (Disk Utility–like): breadcrumb, state-based content, traffic light, action hub.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - System utility styling
private let windowBg = Color(nsColor: .windowBackgroundColor)
private let controlBg = Color(nsColor: .controlBackgroundColor)

/// State identifier for spring animations when switching Setup / Empty / Active.
private enum ContentState: Equatable {
    case setup
    case empty
    case active
}

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var helper: AccountsHelper
    @Binding var showSettings: Bool
    @State private var showMore = false
    @State private var showTechnicalSetup = false
    @State private var showLastLog = false
    @State private var showTraining = false
    @State private var showDataHealth = false
    @State private var showReportSummary = false
    @State private var showQuickLook = true
    @AppStorage("ExpenseReports.hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("ExpenseReports.showTips") private var showTips = true
    @State private var showWelcome = false

    private var contentState: ContentState {
        if !helper.setupInstructions.isEmpty { return .setup }
        if helper.monthFolders.isEmpty { return .empty }
        return .active
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            mainContent
                .animation(.spring(), value: contentState)

            Spacer(minLength: 24)
            moreSection
            footerView
        }
        .padding(32)
        .frame(minWidth: 500, minHeight: 600)
        .background(windowBg)
        .sheet(isPresented: $showLastLog) {
            LogSheet(logText: helper.lastScriptOutput)
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet(dismiss: { showWelcome = false; hasSeenWelcome = true })
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(showTips: $showTips)
        }
        .sheet(isPresented: $showTraining) {
            TrainingSheet(helper: helper)
        }
        .sheet(isPresented: $showDataHealth) {
            DataHealthSheet(helper: helper)
        }
        .sheet(isPresented: $showReportSummary) {
            ReportSummarySheet(helper: helper)
        }
        .onChange(of: helper.requestShowReportSummary) { _, requested in
            if requested {
                showReportSummary = true
                helper.requestShowReportSummary = false
            }
        }
        .onAppear {
            helper.refreshFolders()
            if !hasSeenWelcome { showWelcome = true }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { obj, _ in
                guard let url = obj, url.isFileURL else { return }
                DispatchQueue.main.async { _ = helper.trySelectDroppedFolder(url) }
            }
            return true
        }
    }

    // MARK: - Header (breadcrumb)
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Monthly Reports")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption)
                Text("Accounts")
                    .font(.caption)
                Text(">")
                    .font(.caption)
                Text(helper.selectedFolder.isEmpty ? "..." : helper.selectedFolder)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var mainContent: some View {
        if !helper.setupInstructions.isEmpty {
            setupCard
        } else if helper.monthFolders.isEmpty {
            dropZone
        } else {
            activeStateContent
        }
    }

    // MARK: - Setup State
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Copy from Desktop", systemImage: "folder.badge.plus") {
                let r = helper.copySetupFromDesktop()
                helper.statusMessage = r.success ? "✓ \(r.message)" : "✗ \(r.message)"
            }
            .buttonStyle(.borderedProminent)
            DisclosureGroup("Terminal Instructions", isExpanded: $showTechnicalSetup) {
                Text(helper.setupInstructions)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .padding(.top, 4)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
        .padding(.bottom, 16)
    }

    // MARK: - Empty / Drop State
    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a month folder: drop here or open data folder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Open Data Folder", systemImage: "folder") { helper.openAccountsFolderInFinder() }
                    .buttonStyle(.bordered)
                Button("Copy from Desktop") {
                    let r = helper.copySetupFromDesktop()
                    helper.statusMessage = r.success ? "✓ \(r.message)" : "✗ \(r.message)"
                }
                .buttonStyle(.bordered)
                Button("Refresh", systemImage: "arrow.clockwise") { helper.refreshFolders() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.primary.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.secondary.opacity(0.5))
        )
        .cornerRadius(10)
        .padding(.bottom, 16)
    }

    // MARK: - Active State: Month strip + traffic light + Quick Look + Action Hub + Report Card + Quick Stats
    private var activeStateContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthStrip
            trafficLightIndicator
                .padding(.top, 12)
            if showQuickLook, helper.mergedCSVURL() != nil {
                QuickLookChart(helper: helper)
                    .padding(.top, 12)
            }
            ActionHub(helper: helper, showLastLog: $showLastLog, showTraining: $showTraining, showDataHealth: $showDataHealth)
                .padding(.top, 16)
            if helper.statusMessage.hasPrefix("✓") && !helper.selectedFolder.isEmpty {
                ReportCard(helper: helper, onViewSummary: { showReportSummary = true })
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                if let insight = helper.loadDeltaInsight() {
                    QuickStatsBar(insight: insight)
                        .padding(.top, 12)
                }
            }
        }
        .animation(.spring(), value: helper.statusMessage.hasPrefix("✓"))
        .animation(.spring(), value: helper.selectedFolder)
    }

    // MARK: - Month Strip (horizontal pills)
    private var monthStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(helper.monthFolders, id: \.self) { name in
                    MonthPill(
                        title: name,
                        isSelected: name == helper.selectedFolder,
                        action: { helper.selectedFolder = name }
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Traffic Light Status
    private var trafficLightIndicator: some View {
        Group {
            if let stats = helper.selectedMonthStats() {
                HStack(spacing: 8) {
                    Circle()
                        .fill(trafficLightColor(stats: stats))
                        .frame(width: 10, height: 10)
                    Text(trafficLightLabel(stats: stats))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func trafficLightColor(stats: (csvCount: Int, reportDate: Date?)) -> Color {
        if stats.csvCount == 0 { return .red }
        if stats.reportDate == nil { return .yellow }
        return .green
    }

    private func trafficLightLabel(stats: (csvCount: Int, reportDate: Date?)) -> String {
        if stats.csvCount == 0 { return "No CSVs found" }
        if let date = stats.reportDate {
            return "Report up to date (\(shortDate(date)))"
        }
        return "CSVs found, no report"
    }

    // MARK: - More drawer & Footer
    private var moreSection: some View {
        DisclosureGroup("More", isExpanded: $showMore) {
            VStack(alignment: .leading, spacing: 10) {
                if let date = helper.lastRunDate {
                    Text("Last run \(shortDate(date)) \(shortTime(date))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button("Export backup…", systemImage: "square.and.arrow.down") {
                    helper.exportBackupWithSavePanel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text(helper.accountsFolderPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 6)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var footerView: some View {
        HStack {
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }

    func shortTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    func shortDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }
}

// MARK: - Month Pill (active = accent filled, others bordered)
struct MonthPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Hub (grouped container, primary + secondary with Dividers)
struct ActionHub: View {
    @ObservedObject var helper: AccountsHelper
    @Binding var showLastLog: Bool
    @Binding var showTraining: Bool
    @Binding var showDataHealth: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if helper.isWorking {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(helper.stepMessage.isEmpty ? "Processing…" : helper.stepMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Merge & Create Report", systemImage: "arrow.merge") {
                helper.mergeThenGenerate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .keyboardShortcut(.return)
            .disabled(helper.isWorking || helper.selectedFolder.isEmpty)

            HStack(spacing: 0) {
                Button("Create report only (⌘R)", systemImage: "tablecells") {
                    helper.generateReport()
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(helper.isWorking || helper.selectedFolder.isEmpty)

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 8)

                Button("Merge CSVs only", systemImage: "arrow.triangle.merge") {
                    helper.mergeCSVs()
                }
                .buttonStyle(.plain)
                .disabled(helper.isWorking || helper.selectedFolder.isEmpty)

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 8)

                Button("Train categories", systemImage: "brain") {
                    showTraining = true
                }
                .buttonStyle(.plain)
                .help("Assign categories to transactions. Run Merge first to see data.")

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 8)

                Button("Data Health", systemImage: "checkmark.shield") {
                    showDataHealth = true
                }
                .buttonStyle(.plain)
                .help("Reconciliation and duplicate info. Run Merge first to see data.")

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 8)

                Button("Log", systemImage: "terminal") {
                    showLastLog = true
                }
                .buttonStyle(.plain)

                if helper.lastFailedAction != nil {
                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 8)
                    Button("Try again", systemImage: "arrow.clockwise") {
                        helper.retryLastAction()
                    }
                    .buttonStyle(.plain)
                    .disabled(helper.isWorking)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(controlBg)
        .cornerRadius(10)
    }
}

// MARK: - Report Card (success: View summary in app = no Excel needed; optional Open in spreadsheet)
struct ReportCard: View {
    @ObservedObject var helper: AccountsHelper
    var onViewSummary: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .offset(x: 4, y: 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(helper.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text("View your totals and spending by category below, or open the full spreadsheet if you have Numbers or Excel.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("View summary", systemImage: "chart.bar.doc.horizontal") { onViewSummary() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Open in Numbers/Excel", systemImage: "doc.fill") {
                        if !helper.openReportFile() {
                            helper.statusMessage = "✓ Report saved. Couldn’t open spreadsheet app — use View summary to see your numbers."
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Show in Finder", systemImage: "folder") { helper.openMonthFolderInFinder() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Report summary sheet (in-app view — no Excel or Numbers required)
struct ReportSummarySheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Report summary — \(helper.selectedFolder)")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            if let summary = helper.loadMonthSummary(monthFolder: helper.selectedFolder) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 24) {
                        summaryRow("Total spent", value: summary.totalSpent, format: .currency)
                        summaryRow("Total credits", value: summary.totalCredits, format: .currency)
                        summaryRow("Transactions", value: Double(summary.transactionCount), format: .decimal)
                    }
                    .font(.subheadline)
                    Divider()
                    Text("Spending by category")
                        .font(.subheadline.weight(.medium))
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(summary.byCategory.sorted(by: { $0.value > $1.value }), id: \.key) { category, amount in
                                HStack {
                                    Text(category)
                                        .font(.caption)
                                    Spacer()
                                    Text(formatCurrency(amount))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 300)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(10)
            } else {
                let amounts = helper.loadCategoryAmounts()
                if amounts.isEmpty {
                    Text("No summary data for this month. Run Merge & Create Report first.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Spending by category")
                            .font(.subheadline.weight(.medium))
                        ForEach(amounts) { item in
                            HStack {
                                Text(item.category)
                                    .font(.caption)
                                Spacer()
                                Text(formatCurrency(item.amount))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 400)
    }

    private func summaryRow(_ title: String, value: Double, format: NumberFormatter.Style = .currency) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if format == .currency {
                Text(formatCurrency(value))
                    .font(.title3.monospacedDigit())
            } else {
                Text(NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal))
                    .font(.title3.monospacedDigit())
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let n = NSNumber(value: value)
        return "$" + NumberFormatter.localizedString(from: n, number: .decimal)
    }
}

// MARK: - Quick Look (spending by category from merged.csv — list of bars so every category shows)
struct QuickLookChart: View {
    @ObservedObject var helper: AccountsHelper
    private let rowHeight: CGFloat = 22

    var body: some View {
        let amounts = helper.loadCategoryAmounts()
        let maxAmount = amounts.map(\.amount).max() ?? 1

        VStack(alignment: .leading, spacing: 6) {
            Text("Spending by category (\(amounts.count))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if amounts.isEmpty {
                Text("No spending data.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(amounts) { item in
                            HStack(alignment: .center, spacing: 8) {
                                Text(item.category)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(minWidth: 0, maxWidth: 140, alignment: .leading)
                                GeometryReader { geo in
                                    let width = maxAmount > 0 ? (item.amount / maxAmount) * geo.size.width : 0
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.accentColor.opacity(0.8))
                                        .frame(width: max(0, width), height: rowHeight - 4)
                                }
                                .frame(height: rowHeight - 4)
                                Text(formatCurrency(item.amount))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                            .frame(height: rowHeight)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private func formatCurrency(_ value: Double) -> String {
        let n = NSNumber(value: value)
        return "$" + NumberFormatter.localizedString(from: n, number: .decimal)
    }
}

// MARK: - Quick Stats (month-over-month deltas)
struct QuickStatsBar: View {
    let insight: DeltaInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let msg = insight.spendingDeltaMessage {
                HStack(spacing: 6) {
                    Image(systemName: insight.spendingDeltaPercent ?? 0 > 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle((insight.spendingDeltaPercent ?? 0) > 0 ? .orange : .green)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let alert = insight.categoryAlert {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                    Text("\(alert.category) is up $\(Int(alert.delta)) vs last month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let savings = insight.savingsTransfer, savings > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "banknote")
                        .foregroundStyle(.green)
                    Text("Transfer to Savings: $\(Int(savings))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Training sheet (manual category → custom_mapping.json)
struct TrainingSheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss
    @State private var transactions: [MergedTransaction] = []
    @State private var categoryOverrides: [String: String] = [:]
    @State private var initialMapping: [String: String] = [:]  // snapshot when sheet opened; only save when user actually changes
    @State private var exportImportMessage: String? = nil
    private var categories: [String] { CategoryTypes.all }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Train categories")
                .font(.headline)
            Text("Changes apply only to future merges. Your existing report and merged.csv are not modified. Pick a category and tap Save to write to custom mapping.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Export mapping…", systemImage: "square.and.arrow.up") { runExportMapping() }
                    .buttonStyle(.bordered)
                Button("Import mapping…", systemImage: "square.and.arrow.down") { runImportMapping() }
                    .buttonStyle(.bordered)
                if let msg = exportImportMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(msg.hasPrefix("✓") ? .green : .orange)
                }
            }
            let uncategorized = Array(Set(transactions.filter { $0.category == CategoryTypes.defaultCategory || $0.category.isEmpty }.map(\.description))).prefix(100)
            if transactions.isEmpty {
                Text("Run Merge first, or no transactions in this month.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if uncategorized.isEmpty {
                Text("All transactions are categorized.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(Array(uncategorized), id: \.self) { desc in
                    HStack {
                        Text(desc)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { categoryOverrides[desc] ?? CategoryTypes.defaultCategory },
                            set: { newVal in
                                categoryOverrides[desc] = newVal
                                // Only persist when user explicitly chose a different category (not on Picker init, and not "Uncategorized")
                                let previous = initialMapping[desc] ?? CategoryTypes.defaultCategory
                                if newVal != previous && newVal != CategoryTypes.defaultCategory {
                                    helper.saveCustomMappingEntry(description: desc, category: newVal)
                                }
                            }
                        )) {
                            ForEach(categories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 200)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            transactions = helper.loadMergedTransactions()
            let loaded = helper.loadCustomMapping()
            categoryOverrides = loaded
            initialMapping = loaded
        }
    }

    private func runExportMapping() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "custom_mapping.json"
        panel.title = "Export custom mapping"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportImportMessage = helper.exportCustomMapping(to: url) ? "✓ Exported." : "Export failed."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exportImportMessage = nil }
    }

    private func runImportMapping() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.title = "Import custom mapping"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ok = helper.importCustomMapping(from: url)
        exportImportMessage = ok ? "✓ Imported and merged." : "Import failed."
        if ok {
            let loaded = helper.loadCustomMapping()
            categoryOverrides = loaded
            initialMapping = loaded
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exportImportMessage = nil }
    }
}

// MARK: - Data Health sheet (audit reconciliation + duplicates + transaction search)
struct DataHealthSheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Health")
                .font(.headline)
            if let audit = helper.loadAuditInfo() {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reconciliation")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 16) {
                        Label("Total credits: $\(formatDecimal(audit.totalCredits))", systemImage: "arrow.down.circle")
                        Label("Total debits: $\(formatDecimal(audit.totalDebits))", systemImage: "arrow.up.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("Across \(audit.filesProcessed) file(s), \(audit.transactionCount) transactions.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let map = audit.categorizedViaMapping, let reg = audit.categorizedViaRegex, let ml = audit.categorizedViaMl, let unc = audit.uncategorized {
                        Text("Categorized: \(map) via Mapping, \(reg) via Regex, \(ml) via ML; \(unc) uncategorized.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if audit.duplicateCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("\(audit.duplicateCount) duplicate transaction(s) ignored.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            } else {
                Text("Run Merge first to see audit data.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            TransactionSearchSection(helper: helper, searchText: $searchText)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 420)
    }

    private func formatDecimal(_ d: Double) -> String {
        let n = NSNumber(value: d)
        return NumberFormatter.localizedString(from: n, number: .decimal)
    }
}

// MARK: - Transaction search (filter by description, category, or amount)
private struct TransactionSearchSection: View {
    @ObservedObject var helper: AccountsHelper
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search transactions")
                .font(.subheadline.weight(.medium))
            TextField("Description, category, or amount…", text: $searchText)
                .textFieldStyle(.roundedBorder)
            let transactions = helper.loadMergedTransactions()
            let filtered = searchText.isEmpty
                ? transactions
                : transactions.filter { t in
                    let q = searchText.lowercased()
                    return t.description.lowercased().contains(q)
                        || t.category.lowercased().contains(q)
                        || formatCurrency(t.amount).lowercased().contains(q)
                }
            if transactions.isEmpty {
                Text("Run Merge first to see transactions.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(filtered.count) of \(transactions.count) transactions")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filtered.prefix(200)) { t in
                            HStack(alignment: .top, spacing: 8) {
                                Text(t.date)
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(width: 72, alignment: .leading)
                                Text(t.description)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                Text(t.category)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 100, alignment: .trailing)
                                Text(formatCurrency(t.amount))
                                    .font(.caption2.monospacedDigit())
                                    .frame(width: 56, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
    }

    private func formatCurrency(_ value: Double) -> String {
        let n = NSNumber(value: value)
        return "$" + NumberFormatter.localizedString(from: n, number: .decimal)
    }
}

// MARK: - Welcome sheet (first launch)
struct WelcomeSheet: View {
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monthly Reports")
                .font(.title2.weight(.semibold))
            Text("Add your data folder (Copy from Desktop or Open Data Folder), then pick a month and run Merge & Create Report.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Get started") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(minWidth: 380)
    }
}

// MARK: - Settings sheet
struct SettingsSheet: View {
    @Binding var showTips: Bool
    @AppStorage("ExpenseReports.openFolderAfterReport") private var openFolderAfterReport = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
            Toggle("Open folder after report", isOn: $openFolderAfterReport)
            Toggle("Show tips", isOn: $showTips)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(minWidth: 300)
    }
}

// MARK: - Log sheet
struct LogSheet: View {
    let logText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Log")
                    .font(.headline)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText.isEmpty ? "(no output)" : logText, forType: .string)
                }
                .buttonStyle(.plain)
                .disabled(logText.isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            ScrollView {
                Text(logText.isEmpty ? "No output yet." : logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .frame(minHeight: 200)
        }
        .frame(minWidth: 380, minHeight: 280)
    }
}

// MARK: - Preview
#Preview {
    ContentView(showSettings: .constant(false))
        .environmentObject(AccountsHelper())
        .frame(width: 520, height: 640)
}
