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

    // MARK: - Active State: Month strip + traffic light + Action Hub + Report Card
    private var activeStateContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthStrip
            trafficLightIndicator
                .padding(.top, 12)
            ActionHub(helper: helper, showLastLog: $showLastLog)
                .padding(.top, 16)
            if helper.statusMessage.hasPrefix("✓") && !helper.selectedFolder.isEmpty {
                ReportCard(helper: helper)
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(), value: helper.statusMessage.hasPrefix("✓"))
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

// MARK: - Report Card (success: document icon + check badge, Open / Show in Finder / Copy Path)
struct ReportCard: View {
    @ObservedObject var helper: AccountsHelper

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
                HStack(spacing: 8) {
                    Button("Open", systemImage: "doc.fill") { helper.openReportFile() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Show in Finder", systemImage: "folder") { helper.openMonthFolderInFinder() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Copy Path", systemImage: "doc.on.clipboard") {
                        if helper.copyReportPathToClipboard() {
                            helper.statusMessage = "✓ Report path copied to clipboard."
                        }
                    }
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
