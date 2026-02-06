//
//  ContentView.swift
//  ExpenseReports
//
//  Created by Darshan Bodara on 2026-02-05.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Visual effect background (macOS)
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var helper: AccountsHelper
    @State private var showAdvancedOptions = false
    @State private var showTechnicalSetup = false
    @State private var showLastLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            if !helper.setupInstructions.isEmpty {
                SetupView(helper: helper, showTechnicalSetup: $showTechnicalSetup)
            } else if helper.monthFolders.isEmpty {
                dropZoneOrWelcome
            } else {
                monthSelectorSection
                fileStatusBadge
                ActionCardView(helper: helper)
                if !helper.statusMessage.isEmpty {
                    StatusView(helper: helper)
                }
            }

            Spacer(minLength: 24)
            advancedOptionsSection
        }
        .padding(32)
        .frame(minWidth: 500, minHeight: 600)
        .background(VisualEffectBlur(material: .hudWindow))
        .sheet(isPresented: $showLastLog) {
            LogSheet(logText: helper.lastScriptOutput)
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

    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Monthly Reports")
                .font(.system(size: 28, weight: .bold))
            Text("CIBC Export Processor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 28)
    }

    // MARK: - Month selector or drop zone
    private var monthSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected month")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Picker("", selection: $helper.selectedFolder) {
                ForEach(helper.monthFolders, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)
            .labelsHidden()
            Text(helper.selectedFolder.isEmpty ? "" : helper.selectedFolder)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Drop zone when no months
    private var dropZoneOrWelcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add your first month", systemImage: "folder.badge.plus")
                .font(.subheadline.weight(.semibold))
            Text("Drop a month folder here, or open your data folder and add folders—then tap Refresh.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { helper.openAccountsFolderInFinder() } label: {
                    Label("Open Data Folder", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
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
        .padding(24)
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.secondary.opacity(0.5))
        )
        .cornerRadius(12)
        .padding(.bottom, 20)
    }

    // MARK: - File status badge
    private var fileStatusBadge: some View {
        Group {
            if !helper.selectedFolder.isEmpty, let stats = helper.selectedMonthStats() {
                HStack(spacing: 6) {
                    Image(systemName: "tablecells")
                        .font(.caption)
                    Text("\(stats.csvCount) bank file\(stats.csvCount == 1 ? "" : "s") detected")
                        .font(.caption)
                    if let date = stats.reportDate {
                        Text("•")
                        Text("Report: \(shortDate(date))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(8)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Advanced options
    private var advancedOptionsSection: some View {
        DisclosureGroup("Advanced Options", isExpanded: $showAdvancedOptions) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button("Open Data Folder", systemImage: "folder") {
                        helper.openAccountsFolderInFinder()
                    }
                    .buttonStyle(.bordered)
                    Button("Copy from Desktop", systemImage: "folder.badge.plus") {
                        let r = helper.copySetupFromDesktop()
                        helper.statusMessage = r.success ? "✓ \(r.message)" : "✗ \(r.message)"
                    }
                    .buttonStyle(.bordered)
                }
                Text(helper.accountsFolderPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Button("View Last Log", systemImage: "doc.text") {
                    showLastLog = true
                }
                .buttonStyle(.borderless)
            }
            .padding(.top, 8)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func shortDate(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }
}

// MARK: - Setup View (one-time)
struct SetupView: View {
    @ObservedObject var helper: AccountsHelper
    @Binding var showTechnicalSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("One-time Setup", systemImage: "wrench.and.screwdriver.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Copy the environment from your Desktop ACCOUNTS folder, then open the data folder to finish if needed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Copy environment from Desktop", systemImage: "folder.badge.plus") {
                    let r = helper.copySetupFromDesktop()
                    helper.statusMessage = r.success ? "✓ \(r.message)" : "✗ \(r.message)"
                }
                .buttonStyle(.borderedProminent)
                Button("Open Data Folder", systemImage: "folder") {
                    helper.openAccountsFolderInFinder()
                }
                .buttonStyle(.bordered)
            }
            DisclosureGroup("Technical details (Terminal)", isExpanded: $showTechnicalSetup) {
                Text(helper.setupInstructions)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                    .padding(.top, 6)
            }
            .font(.caption)
        }
        .padding(20)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .padding(.bottom, 20)
    }
}

// MARK: - Action Card (primary + secondary buttons)
struct ActionCardView: View {
    @ObservedObject var helper: AccountsHelper

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if helper.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text(helper.stepMessage.isEmpty ? "Processing…" : helper.stepMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Button {
                helper.mergeThenGenerate()
            } label: {
                Label("Merge & Create Report", systemImage: "arrow.merge")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return)
            .disabled(helper.isWorking || helper.selectedFolder.isEmpty)

            HStack(spacing: 12) {
                Button("Create Report Only", systemImage: "tablecells") {
                    helper.generateReport()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(helper.isWorking || helper.selectedFolder.isEmpty)

                Button("Merge CSVs Only", systemImage: "arrow.triangle.merge") {
                    helper.mergeCSVs()
                }
                .disabled(helper.isWorking || helper.selectedFolder.isEmpty)

                if helper.lastFailedAction != nil {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        helper.retryLastAction()
                    }
                    .disabled(helper.isWorking)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Status / Success area
struct StatusView: View {
    @ObservedObject var helper: AccountsHelper

    private var reportFileName: String {
        guard !helper.selectedFolder.isEmpty else { return "" }
        return "\(helper.selectedFolder)_Report.xlsx"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: helper.statusMessage.hasPrefix("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(helper.statusMessage.hasPrefix("✓") ? .green : .orange)
                Text(helper.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(helper.statusMessage.hasPrefix("✓") ? .primary : .secondary)
            }
            if helper.statusMessage.hasPrefix("✓") && !helper.selectedFolder.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reportFileName)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Open in Excel", systemImage: "doc.fill") {
                            helper.openReportFile()
                        }
                        .buttonStyle(.bordered)
                        Button("Show in Finder", systemImage: "folder") {
                            helper.openMonthFolderInFinder()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(helper.statusMessage.hasPrefix("✓") ? Color.green.opacity(0.08) : Color.orange.opacity(0.06))
        .cornerRadius(12)
        .padding(.bottom, 20)
    }
}

// MARK: - Log sheet
struct LogSheet: View {
    let logText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Last run log")
                    .font(.headline)
                Spacer()
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
        .frame(minWidth: 400, minHeight: 300)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(AccountsHelper())
        .frame(width: 520, height: 640)
}
