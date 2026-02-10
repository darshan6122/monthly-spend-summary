//
//  ContentView.swift
//  ExpenseReports
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

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
    @State private var showCompareMonths = false
    @State private var showRecurring = false
    @State private var showYearInReview = false
    @State private var showSplits = false
    @State private var showTaxReport = false
    @State private var showHeatmap = false
    @State private var showInflation = false
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
        .sheet(isPresented: $showLastLog) {
            LogSheet(logText: helper.lastScriptOutput, scriptFailed: helper.lastScriptFailed)
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet(dismiss: { showWelcome = false; hasSeenWelcome = true })
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(showTips: $showTips)
                .environmentObject(helper)
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
        .sheet(isPresented: $showCompareMonths) {
            CompareMonthsSheet(helper: helper)
        }
        .sheet(isPresented: $showRecurring) {
            RecurringTransactionsSheet(helper: helper)
        }
        .sheet(isPresented: $showYearInReview) {
            YearInReviewSheet(helper: helper)
        }
        .sheet(isPresented: $showSplits) {
            SplitsSheet(helper: helper)
        }
        .sheet(isPresented: $showTaxReport) {
            TaxReportSheet(helper: helper)
        }
        .sheet(isPresented: $showHeatmap) {
            CalendarHeatmapSheet(helper: helper)
        }
        .sheet(isPresented: $showInflation) {
            InflationTrackerSheet(helper: helper)
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
                DispatchQueue.main.async {
                    let path = url.path
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                        _ = helper.trySelectDroppedFolder(url)
                    } else if path.lowercased().hasSuffix(".csv") {
                        let result = helper.importDroppedCSV(url)
                        if !result.success { helper.statusMessage = "✗ \(result.message)" }
                    } else if path.lowercased().hasSuffix(".pdf") {
                        let result = helper.importDroppedPDF(url)
                        if !result.success { helper.statusMessage = "✗ \(result.message)" }
                    }
                }
            }
            return true
        }
        .alert("New bank export detected", isPresented: Binding(
            get: { helper.detectedDownloadedCSV != nil },
            set: { if !$0 { helper.clearDetectedDownloadedCSV() } }
        )) {
            Button("Move to month folder") {
                if let url = helper.detectedDownloadedCSV {
                    _ = helper.importDroppedCSV(url)
                }
                helper.clearDetectedDownloadedCSV()
            }
            Button("Cancel", role: .cancel) { helper.clearDetectedDownloadedCSV() }
        } message: {
            Text("A CIBC CSV was found in Downloads. Move it to your data folder? (Month is detected from the file.)")
        }
    }

    // MARK: - Header (breadcrumb)
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Monthly Reports")
                    .font(.title2.weight(.semibold))
            }
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                Text("Accounts")
                Text("›")
                Text(helper.selectedFolder.isEmpty ? "Pick a month" : helper.selectedFolder)
                    .fontWeight(helper.selectedFolder.isEmpty ? .regular : .medium)
            }
            .font(.caption)
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
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
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
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(.secondary.opacity(0.4))
        )
        .cornerRadius(8)
        .padding(.bottom, 16)
    }

    // MARK: - Active State: Month strip + traffic light + Quick Look + Action Hub + Report Card + Quick Stats
    private var activeStateContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthStrip
            trafficLightIndicator
                .padding(.top, 12)
            reportAvailableBar
            if showQuickLook, helper.mergedCSVURL() != nil {
                QuickLookChart(helper: helper, onViewSummary: { showReportSummary = true })
                    .padding(.top, 12)
            }
            ActionHub(helper: helper, showLastLog: $showLastLog, showTraining: $showTraining, showDataHealth: $showDataHealth, onViewSummary: { showReportSummary = true })
                .padding(.top, 16)
            if helper.statusMessage.hasPrefix("✓") && !helper.selectedFolder.isEmpty {
                ReportCard(helper: helper, onViewSummary: { showReportSummary = true })
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                if let insight = helper.loadDeltaInsight() {
                    QuickStatsBar(insight: insight, helper: helper)
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
                        subtitle: helper.reportDate(monthFolder: name).map { shortDate($0) },
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

    /// Bar shown when selected month has report data; offers View summary.
    private var reportAvailableBar: some View {
        Group {
            if !helper.selectedFolder.isEmpty,
               helper.loadMonthSummary(monthFolder: helper.selectedFolder) != nil || helper.mergedCSVURL() != nil {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Report available for this month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("View summary") { showReportSummary = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 10)
            }
        }
    }

    // MARK: - More drawer & Footer
    private var moreSection: some View {
        DisclosureGroup("More", isExpanded: $showMore) {
            VStack(alignment: .leading, spacing: 10) {
                Button("Compare two months", systemImage: "rectangle.on.rectangle.angled") { showCompareMonths = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Recurring transactions", systemImage: "repeat") { showRecurring = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Year in review", systemImage: "calendar.badge.clock") { showYearInReview = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Split transactions", systemImage: "rectangle.split.2x2") { showSplits = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Tax report…", systemImage: "doc.text.magnifyingglass") { showTaxReport = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Calendar heatmap", systemImage: "calendar") { showHeatmap = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Inflation tracker", systemImage: "chart.line.uptrend.xyaxis") { showInflation = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

// MARK: - Month Pill (active = accent filled, others bordered; optional report date)
struct MonthPill: View {
    let title: String
    let isSelected: Bool
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                if let sub = subtitle, !sub.isEmpty {
                    Text("Report: \(sub)")
                        .font(.system(size: 9))
                        .opacity(isSelected ? 0.9 : 0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1)
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
    var onViewSummary: () -> Void = {}

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

            Button("View report summary", systemImage: "chart.bar.doc.horizontal.fill") {
                onViewSummary()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
            .disabled(helper.selectedFolder.isEmpty)
            .help("See totals and spending by category for this month (no Excel needed)")

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
        .padding(14)
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
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(category)
                                            .font(.caption)
                                        Spacer()
                                        Text(formatCurrency(amount))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    if let limit = AppSettings.effectiveBudgetLimit(category: category), amount > limit {
                                        Text("Over budget by \(formatCurrency(amount - limit))")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
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
    var onViewSummary: () -> Void = {}
    private let rowHeight: CGFloat = 22

    var body: some View {
        let amounts = helper.loadCategoryAmounts()
        let maxAmount = amounts.map(\.amount).max() ?? 1

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spending by category (\(amounts.count))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("View full summary", systemImage: "doc.text.magnifyingglass") {
                    onViewSummary()
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
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
                                    let w = maxAmount > 0 ? (item.amount / maxAmount) * geo.size.width : 0
                                    QuickLookBarFill(width: w, height: rowHeight - 4)
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
        .padding(14)
    }

    private func formatCurrency(_ value: Double) -> String {
        let n = NSNumber(value: value)
        return "$" + NumberFormatter.localizedString(from: n, number: .decimal)
    }
}

// MARK: - Quick Look bar fill
private struct QuickLookBarFill: View {
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor)
            .frame(width: max(0, width), height: height)
    }
}

// MARK: - Quick Stats (month-over-month deltas, forecasting, sparklines)
struct QuickStatsBar: View {
    let insight: DeltaInsight
    @ObservedObject var helper: AccountsHelper

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let proj = helper.projectedMonthSpend(), proj.dayOfMonth > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.blue)
                    Text("On track to spend $\(Int(proj.projected)) this month (day \(proj.dayOfMonth)/\(proj.daysInMonth)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let totalBudget = CategoryTypes.all.compactMap { AppSettings.effectiveBudgetLimit(category: $0) }.reduce(0, +)
                if totalBudget > 0 && proj.projected > totalBudget {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Projected spend may exceed budget ($\(Int(totalBudget))).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
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
            SparklineRow(helper: helper)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sparkline (6-month trend for top categories)
private struct SparklineRow: View {
    @ObservedObject var helper: AccountsHelper
    private let months = 6
    var body: some View {
        let trends = helper.loadCategoryTrends(lastNMonths: months)
        let topCats = Array(trends.keys).sorted { (trends[$0]?.reduce(0, +) ?? 0) > (trends[$1]?.reduce(0, +) ?? 0) }.prefix(3)
        if topCats.isEmpty { return AnyView(EmptyView()) }
        let maxVal = trends.values.flatMap { $0 }.max() ?? 1
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text("6-month trend")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(Array(topCats), id: \.self) { cat in
                    HStack(spacing: 6) {
                        Text(cat)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(width: 100, alignment: .leading)
                        if let vals = trends[cat], !vals.isEmpty {
                            GeometryReader { g in
                                HStack(spacing: 2) {
                                    ForEach(Array(vals.enumerated()), id: \.offset) { _, v in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.accentColor.opacity(maxVal > 0 ? (v / maxVal) * 0.5 + 0.3 : 0.3))
                                            .frame(width: max(2, (g.size.width - CGFloat(vals.count) * 2) / CGFloat(vals.count)))
                                    }
                                }
                            }
                            .frame(height: 14)
                        }
                    }
                }
            }
        )
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
                    Text("Categorized: \(audit.categorizedViaMapping ?? 0) via Mapping, \(audit.categorizedViaRegex ?? 0) via Regex, \(audit.categorizedViaMl ?? 0) via ML; \(audit.uncategorized ?? 0) uncategorized.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
                    if let ign = audit.ignoredCount, ign > 0 {
                        Text("\(ign) transaction(s) excluded by ignore list (ignore_list.json).")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
    @State private var uncategorizedOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search transactions")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                TextField("Description, category, or amount…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Uncategorized only", isOn: $uncategorizedOnly)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            let transactions = helper.loadMergedTransactions()
            let bySearch = searchText.isEmpty
                ? transactions
                : transactions.filter { t in
                    let q = searchText.lowercased()
                    return t.description.lowercased().contains(q)
                        || t.category.lowercased().contains(q)
                        || formatCurrency(t.amount).lowercased().contains(q)
                }
            let filtered = uncategorizedOnly ? bySearch.filter { $0.category == CategoryTypes.defaultCategory || $0.category.isEmpty } : bySearch
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

// MARK: - Compare two months sheet
struct CompareMonthsSheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss
    @State private var monthA: String = ""
    @State private var monthB: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Compare two months")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Month A")
                        .font(.caption.weight(.medium))
                    Picker("", selection: $monthA) {
                        Text("—").tag("")
                        ForEach(helper.monthFolders, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(minWidth: 140)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Month B")
                        .font(.caption.weight(.medium))
                    Picker("", selection: $monthB) {
                        Text("—").tag("")
                        ForEach(helper.monthFolders, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(minWidth: 140)
                }
            }
            if !monthA.isEmpty, !monthB.isEmpty, let sumA = helper.loadMonthSummary(monthFolder: monthA), let sumB = helper.loadMonthSummary(monthFolder: monthB) {
                let allCats = Set(sumA.byCategory.keys).union(sumB.byCategory.keys).sorted()
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Category").frame(width: 140, alignment: .leading)
                            Text(monthA).frame(width: 72, alignment: .trailing).font(.caption2)
                            Text(monthB).frame(width: 72, alignment: .trailing).font(.caption2)
                            Text("Delta").frame(width: 64, alignment: .trailing).font(.caption2)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        ForEach(allCats, id: \.self) { cat in
                            let a = sumA.byCategory[cat] ?? 0
                            let b = sumB.byCategory[cat] ?? 0
                            let delta = b - a
                            HStack {
                                Text(cat).font(.caption).lineLimit(1).frame(width: 140, alignment: .leading)
                                Text("$\(Int(a))").font(.caption2.monospacedDigit()).frame(width: 72, alignment: .trailing)
                                Text("$\(Int(b))").font(.caption2.monospacedDigit()).frame(width: 72, alignment: .trailing)
                                Text("\(delta >= 0 ? "+" : "")$\(Int(delta))").font(.caption2.monospacedDigit()).foregroundStyle(delta > 0 ? .orange : (delta < 0 ? .green : .secondary)).frame(width: 64, alignment: .trailing)
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 320)
            } else {
                Text("Pick two months that have report data (run Merge & Create Report for each).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 340)
        .onAppear {
            if monthA.isEmpty, let first = helper.monthFolders.first { monthA = first }
            if monthB.isEmpty, helper.monthFolders.count > 1 { monthB = helper.monthFolders[1] }
            else if monthB.isEmpty { monthB = monthA }
        }
    }
}

// MARK: - Sankey HTML generator (Income → Categories)
private func generateSankeyHTML(helper: AccountsHelper) -> URL? {
    let monthSummaries = helper.monthFolders.compactMap { name -> (String, MonthSummary)? in
        guard let s = helper.loadMonthSummary(monthFolder: name) else { return nil }
        return (name, s)
    }
    var combined: [String: Double] = [:]
    var totalIncome: Double = 0
    for (_, s) in monthSummaries {
        totalIncome += s.totalCredits
        for (cat, amt) in s.byCategory { combined[cat, default: 0] += amt }
    }
    let categories = combined.sorted { $0.value > $1.value }.map(\.key)
    if categories.isEmpty { return nil }
    var nodeLabels = ["Income"]
    nodeLabels.append(contentsOf: categories)
    var sourceIdx: [Int] = []
    var targetIdx: [Int] = []
    var values: [Double] = []
    for (i, cat) in categories.enumerated() {
        let amt = combined[cat] ?? 0
        if amt > 0 {
            sourceIdx.append(0)
            targetIdx.append(1 + i)
            values.append(amt)
        }
    }
    let sources = sourceIdx.map { String($0) }.joined(separator: ",")
    let targets = targetIdx.map { String($0) }.joined(separator: ",")
    let vals = values.map { String(Int($0)) }.joined(separator: ",")
    let labels = nodeLabels.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",")
    let html = """
    <!DOCTYPE html><html><head><script src="https://cdn.plot.ly/plotly-latest.min.js"></script></head><body>
    <div id="plot"></div>
    <script>
    Plotly.newPlot('plot', [{
      type: 'sankey',
      node: { label: [\(labels)] },
      link: { source: [\(sources)], target: [\(targets)], value: [\(vals)] }
    }], { margin: { t: 20, r: 20, b: 20, l: 20 }, height: 500 });
    </script></body></html>
    """
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sankey_\(UUID().uuidString).html")
    guard let data = html.data(using: .utf8), (try? data.write(to: tmp)) != nil else { return nil }
    return tmp
}

// MARK: - Year in review (aggregate spending by month and by category across all months with data)
struct YearInReviewSheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss

    private var monthSummaries: [(name: String, summary: MonthSummary)] {
        helper.monthFolders.compactMap { name in
            guard let s = helper.loadMonthSummary(monthFolder: name) else { return nil }
            return (name, s)
        }
    }

    private var categoryTotals: [(category: String, amount: Double)] {
        var combined: [String: Double] = [:]
        for (_, s) in monthSummaries {
            for (cat, amt) in s.byCategory { combined[cat, default: 0] += amt }
        }
        return combined.sorted { $0.value > $1.value }.map { (category: $0.key, amount: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Year in review")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            if monthSummaries.isEmpty {
                Text("Run Merge & Create Report for at least one month to see data here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Button("View Sankey diagram", systemImage: "arrow.triangle.branch") {
                    guard let url = generateSankeyHTML(helper: helper) else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 8)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("By month")
                            .font(.subheadline.weight(.medium))
                        LazyVStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Month").frame(width: 140, alignment: .leading)
                                Text("Spent").frame(width: 80, alignment: .trailing)
                                Text("Credits").frame(width: 80, alignment: .trailing)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            ForEach(monthSummaries, id: \.name) { item in
                                HStack {
                                    Text(item.name).font(.caption).frame(width: 140, alignment: .leading)
                                    Text("$\(Int(item.summary.totalSpent))").font(.caption2.monospacedDigit()).frame(width: 80, alignment: .trailing)
                                    Text("$\(Int(item.summary.totalCredits))").font(.caption2.monospacedDigit()).frame(width: 80, alignment: .trailing)
                                }
                            }
                        }
                        Divider()
                        Text("Spending by category (all months)")
                            .font(.subheadline.weight(.medium))
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(categoryTotals, id: \.category) { item in
                                HStack {
                                    Text(item.category).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("$\(Int(item.amount))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 400)
            }
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 360)
    }
}

// MARK: - Recurring transactions sheet (same description+amount across months)
struct RecurringTransactionsSheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Subscription Hunter & Recurring")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            let due7 = helper.subscriptionsDueInNext7Days()
            if due7.total > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Due in next 7 days: \(formatCurrency(due7.total))")
                        .font(.subheadline.weight(.medium))
                    ForEach(Array(due7.items.prefix(8).enumerated()), id: \.offset) { _, i in
                        HStack {
                            Text(i.desc).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(formatCurrency(i.amount)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
                Divider()
            }
            let subs = helper.loadRecurringSubscriptions()
            if !subs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active subscriptions (same amount in 2+ months)")
                        .font(.subheadline.weight(.medium))
                    ForEach(Array(subs.prefix(15).enumerated()), id: \.offset) { _, s in
                        HStack {
                            Text(s.key).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text("$\(Int(s.amount))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text("· \(s.months.count) mo").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    let total = subs.prefix(15).reduce(0) { $0 + $1.amount }
                    Text("Total (shown): $\(Int(total))/month").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                Divider()
            }
            Text("All recurring: same description+amount across months.")
                .font(.caption)
                .foregroundStyle(.secondary)
            let items = recurringItems()
            if items.isEmpty {
                Text("Need merged data for at least 2 months. Run Merge for 2+ month folders.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.description) { item in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.description)
                                        .font(.caption)
                                        .lineLimit(2)
                                    Text("\(item.monthsCount) month(s) · \(formatCurrency(item.amount))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 320)
    }

    private struct RecurItem { let description: String; let amount: Double; let monthsCount: Int }

    private static let recurringKeySep: Character = "\u{1E}"

    private func recurringItems() -> [RecurItem] {
        let folders = Array(helper.monthFolders.prefix(6))
        var keyToMonths: [String: Set<String>] = [:]
        for folder in folders {
            let tx = helper.loadMergedTransactions(monthFolder: folder)
            for t in tx {
                let key = "\(t.description)\(Self.recurringKeySep)\(t.amount)"
                keyToMonths[key, default: []].insert(folder)
            }
        }
        var out: [RecurItem] = []
        for (key, months) in keyToMonths where months.count >= 2 {
            let parts = key.split(separator: Self.recurringKeySep, maxSplits: 1)
            let desc = parts.first.map(String.init) ?? ""
            let amt = Double(parts.count > 1 ? String(parts[1]) : "0") ?? 0
            out.append(RecurItem(description: desc, amount: amt, monthsCount: months.count))
        }
        return out.sorted { $0.monthsCount > $1.monthsCount }
    }

    private func formatCurrency(_ value: Double) -> String {
        let n = NSNumber(value: value)
        return "$" + NumberFormatter.localizedString(from: n, number: .decimal)
    }
}

// MARK: - Splits sheet (assign split portions to a transaction)
struct SplitsSheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss
    @State private var transactions: [MergedTransaction] = []
    @State private var splits: TransactionSplitsMap = [:]
    @State private var selectedKey: String?
    @State private var newPartCategory: String = CategoryTypes.defaultCategory
    @State private var newPartAmount: String = ""
    private var categories: [String] { CategoryTypes.all.filter { $0 != CategoryTypes.defaultCategory } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Split transactions")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Text("Split a transaction into multiple categories (e.g. Costco: $60 Groceries, $40 Pharmacy). Re-run report to apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if helper.selectedFolder.isEmpty {
                Text("Select a month first.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                List(transactions.filter { $0.amount < 0 }, id: \.id) { t in
                    let key = "\(t.date)|\(t.description)|\(t.amount)"
                    let isSelected = selectedKey == key
                    let parts = splits[key] ?? []
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.description).font(.caption).lineLimit(1)
                            Text("\(t.date) · $\(Int(abs(t.amount)))").font(.caption2).foregroundStyle(.secondary)
                            if !parts.isEmpty {
                                Text(parts.map { "\($0.category): $\(Int($0.amount))" }.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        Button(parts.isEmpty ? "Split" : "Edit") {
                            selectedKey = key
                            newPartCategory = categories.first ?? ""
                            newPartAmount = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
                .frame(minHeight: 200)
                if let key = selectedKey, let t = transactions.first(where: { "\($0.date)|\($0.description)|\($0.amount)" == key }) {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add portion").font(.subheadline.weight(.medium))
                        HStack {
                            Picker("Category", selection: $newPartCategory) {
                                ForEach(categories, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                            TextField("Amount", text: $newPartAmount)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Button("Add") {
                                guard let amt = Double(newPartAmount.filter { $0.isNumber || $0 == "." }), amt > 0 else { return }
                                var parts = splits[key] ?? []
                                parts.append(TransactionSplitPart(category: newPartCategory, amount: amt))
                                splits[key] = parts
                                helper.saveTransactionSplits(monthFolder: helper.selectedFolder, splits: splits)
                                newPartAmount = ""
                            }
                            .buttonStyle(.bordered)
                        }
                        Button("Clear splits for this", role: .destructive) {
                            splits.removeValue(forKey: key)
                            helper.saveTransactionSplits(monthFolder: helper.selectedFolder, splits: splits)
                            selectedKey = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 380)
        .onAppear {
            transactions = helper.loadMergedTransactions()
            splits = helper.loadTransactionSplits(monthFolder: helper.selectedFolder)
        }
    }
}

// MARK: - Tax report sheet (select categories, export CSV)
struct TaxReportSheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategories: Set<String> = []
    @State private var exportMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tax / Export packet")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Text("Select categories to include (e.g. Health, Donations). Exports totals across all months as CSV.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List(CategoryTypes.all.filter { $0 != CategoryTypes.defaultCategory }, id: \.self) { cat in
                Toggle(cat, isOn: Binding(
                    get: { selectedCategories.contains(cat) },
                    set: { if $0 { selectedCategories.insert(cat) } else { selectedCategories.remove(cat) } }
                ))
                .toggleStyle(.checkbox)
            }
            .listStyle(.plain)
            .frame(maxHeight: 200)
            if let msg = exportMessage {
                Text(msg).font(.caption).foregroundStyle(msg.hasPrefix("✓") ? .green : .orange)
            }
            HStack {
                Button("Export CSV…") {
                    guard !selectedCategories.isEmpty else { exportMessage = "Select at least one category."; return }
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.commaSeparatedText]
                    panel.nameFieldStringValue = "TaxReport-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).csv"
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else { return }
                        let result = helper.generateTaxReport(categories: selectedCategories, outputURL: url, asCSV: true)
                        exportMessage = result.success ? result.message : result.message
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCategories.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 340)
    }
}

// MARK: - Calendar heatmap (spending by day)
struct CalendarHeatmapSheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Calendar heatmap")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Text("Spending by day for \(helper.selectedFolder). Darker = more spent.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if helper.selectedFolder.isEmpty {
                Text("Select a month first.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                let byDay = helper.loadDailySpending(monthFolder: helper.selectedFolder)
                let maxAmt = byDay.values.max() ?? 1
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(1...31, id: \.self) { d in
                        let amt = byDay[d] ?? 0
                        let intensity = maxAmt > 0 ? amt / maxAmt : 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.2 + 0.6 * intensity))
                            .frame(height: 28)
                            .overlay(Text("\(d)").font(.system(size: 9)).foregroundStyle(intensity > 0.5 ? .white : .primary))
                    }
                }
                .padding(4)
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 320)
        .onAppear { _ = helper.selectedFolder }
    }
}

// MARK: - Inflation tracker (merchant YoY)
struct InflationTrackerSheet: View {
    @ObservedObject var helper: AccountsHelper
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Inflation tracker")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Text("Compare average transaction at same merchant year-over-year.")
                .font(.caption)
                .foregroundStyle(.secondary)
            let items = helper.loadMerchantYoY()
            if items.isEmpty {
                Text("Need data for at least two years (e.g. 2024 and 2025).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.prefix(20).enumerated()), id: \.offset) { _, item in
                            let pct = item.avg1 > 0 ? ((item.avg2 - item.avg1) / item.avg1) * 100 : 0
                            HStack {
                                Text(item.merchant).font(.caption).lineLimit(1).frame(width: 140, alignment: .leading)
                                Text("\(item.year1): $\(Int(item.avg1))").font(.caption2).foregroundStyle(.secondary)
                                Text("→").font(.caption2)
                                Text("\(item.year2): $\(Int(item.avg2))").font(.caption2).foregroundStyle(.secondary)
                                Text("\(pct >= 0 ? "+" : "")\(Int(pct))%").font(.caption2).foregroundStyle(pct > 0 ? .orange : .green)
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 360)
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
    @EnvironmentObject var helper: AccountsHelper
    @Binding var showTips: Bool
    @AppStorage("ExpenseReports.openFolderAfterReport") private var openFolderAfterReport = true
    @AppStorage("ExpenseReports.remindEndOfMonth") private var remindEndOfMonth = false
    @Environment(\.dismiss) private var dismiss
    @State private var showBudgets = false
    @State private var showBatchRegenerateAlert = false
    @State private var mlThreshold = AppSettings.mlConfidenceThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
            Toggle("Open folder after report", isOn: $openFolderAfterReport)
            Toggle("Show tips", isOn: $showTips)
            Toggle("Remind me at start of month to run report", isOn: $remindEndOfMonth)
                .onChange(of: remindEndOfMonth) { _, newValue in
                    if newValue {
                        AccountsHelper.scheduleMonthlyReminder()
                    } else {
                        AccountsHelper.cancelMonthlyReminder()
                    }
                }
            Toggle("Watch Downloads for new bank CSV", isOn: Binding(
                get: { AppSettings.watchDownloadsFolder },
                set: { AppSettings.watchDownloadsFolder = $0; helper.updateDownloadsWatcher() }
            ))
            .onAppear { helper.updateDownloadsWatcher() }

            VStack(alignment: .leading, spacing: 4) {
                Text("ML confidence threshold")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Strict")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $mlThreshold, in: 0.3...0.95, step: 0.05)
                        .onChange(of: mlThreshold) { _, v in AppSettings.mlConfidenceThreshold = v }
                    Text("Loose")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Higher = fewer auto-categories (more accurate). Lower = more ML guesses.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button("Regenerate all reports", systemImage: "arrow.clockwise.circle") {
                showBatchRegenerateAlert = true
            }
            .buttonStyle(.bordered)
            .disabled(helper.isWorking || helper.monthFolders.isEmpty)
            .help("Re-run merge + report for every month folder (e.g. after updating custom_mapping)")

            Toggle("Enable budget rollover", isOn: Binding(
                get: { AppSettings.enableBudgetRollover },
                set: { AppSettings.enableBudgetRollover = $0 }
            ))
            .help("Unspent budget per category rolls over; use “Apply rollover” after reviewing a month.")

            Button("Budget limits…", systemImage: "dollarsign.circle") { showBudgets = true }
                .buttonStyle(.bordered)
            Button("Apply rollover from selected month", systemImage: "arrow.right.circle") {
                let result = helper.applyRolloverFromMonth(monthFolder: helper.selectedFolder)
                helper.statusMessage = result.message
            }
            .buttonStyle(.bordered)
            .disabled(!AppSettings.enableBudgetRollover || helper.selectedFolder.isEmpty)
            .help("Add unspent budget from the selected month to rollover for future months.")

            Button("Export for Debugging", systemImage: "lock.shield") {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.zip]
                panel.nameFieldStringValue = "ExpenseReports_anonymized_\(ISO8601DateFormatter().string(from: Date()).prefix(10)).zip"
                panel.message = "Exports a zip with descriptions replaced by Vendor 1, Vendor 2, … (amounts and categories unchanged)."
                if panel.runModal() == .OK, let url = panel.url {
                    let result = helper.exportAnonymizedForDebugging(destinationURL: url)
                    helper.statusMessage = result.success ? "✓ \(result.message)" : "✗ \(result.message)"
                }
            }
            .buttonStyle(.bordered)
            .disabled(helper.monthFolders.isEmpty)
            .help("Create an anonymized zip for sharing or debugging without exposing vendor names.")

            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(minWidth: 320)
        .sheet(isPresented: $showBudgets) { BudgetsSheet() }
        .onAppear { mlThreshold = AppSettings.mlConfidenceThreshold }
        .alert("Regenerate all reports?", isPresented: $showBatchRegenerateAlert) {
            Button("Regenerate all", role: .destructive) {
                helper.batchRegenerateAllReports()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will run Merge + Report for every month folder. It may take a while.")
        }
    }
}

// MARK: - Budget limits sheet (set monthly limit per category; over = alert in summary)
struct BudgetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var limits: [String: String] = [:]

    private var categories: [String] { CategoryTypes.all.filter { $0 != CategoryTypes.defaultCategory } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Budget limits")
                .font(.headline)
            Text("Set a monthly spending limit per category. You’ll see an “Over budget” warning in the report summary.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(categories, id: \.self) { cat in
                    HStack {
                        Text(cat)
                            .font(.caption)
                        Spacer()
                        TextField("No limit", text: Binding(
                            get: { limits[cat] ?? (AppSettings.budgetLimits[cat].map { String(Int($0)) } ?? "") },
                            set: { limits[cat] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    }
                }
            }
            .listStyle(.plain)
            HStack {
                Spacer()
                Button("Done") {
                    for cat in categories {
                        let s = limits[cat] ?? ""
                        let num = Double(s.filter { $0.isNumber || $0 == "." })
                        AppSettings.setBudgetLimit(category: cat, value: (num != nil && num! > 0) ? num : nil)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 400)
        .onAppear {
            var d: [String: String] = [:]
            for cat in categories {
                if let v = AppSettings.budgetLimits[cat], v > 0 { d[cat] = String(Int(v)) }
            }
            limits = d
        }
    }
}

// MARK: - Log sheet
struct LogSheet: View {
    let logText: String
    var scriptFailed: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Log")
                    .font(.headline)
                if scriptFailed {
                    Text("Script failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
