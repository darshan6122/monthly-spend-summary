//
//  RulesListView.swift
//  ExpenseReports
//
//  Dedicated Rules Management: list, add, edit, swipe-to-delete.
//

import SwiftUI
import SwiftData

struct RulesListView: View {
    @Query(sort: \CategoryRule.keyword) private var rules: [CategoryRule]
    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]
    @Environment(\.modelContext) private var modelContext

    @State private var ruleToEdit: CategoryRule?
    @State private var showingAddRule = false
    @State private var suggestedKeyword: String?

    private var suggestions: [String] {
        let uncategorized = allTransactions.filter { $0.category == "Uncategorised" || $0.category.isEmpty }
        let grouped = Dictionary(grouping: uncategorized, by: { $0.cleanDescription.isEmpty ? $0.originalDescription : $0.cleanDescription })
        return grouped.filter { $0.value.count >= 3 }.map(\.key).sorted()
            .filter { merchant in
                !rules.contains { $0.keyword.caseInsensitiveCompare(merchant) == .orderedSame }
            }
    }

    var body: some View {
        List {
            if !suggestions.isEmpty {
                Section("Smart Suggestions") {
                    ForEach(suggestions, id: \.self) { merchant in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(merchant)
                                    .font(.headline)
                                Text("Found \(allTransactions.filter { ($0.cleanDescription.isEmpty ? $0.originalDescription : $0.cleanDescription) == merchant }.count) times")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Create Rule") {
                                suggestedKeyword = merchant
                                showingAddRule = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            Section("Your Rules") {
                ForEach(rules, id: \.keyword) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.keyword)
                            .font(.headline)
                        Text("Categorizes as: \(rule.category)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") {
                        ruleToEdit = rule
                    }
                    .buttonStyle(.link)
                }
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(rule)
                        try? modelContext.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            }
        }
        .navigationTitle("Auto-Categorize Rules")
        .toolbar {
            Button { suggestedKeyword = nil; showingAddRule = true } label: {
                Label("Add Rule", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingAddRule) {
            AddRuleSheet(initialKeyword: suggestedKeyword)
        }
        .onChange(of: showingAddRule) { _, isShowing in
            if !isShowing { suggestedKeyword = nil }
        }
        .sheet(item: $ruleToEdit) { rule in
            EditRuleSheet(rule: rule) {
                ruleToEdit = nil
            }
        }
    }
}

// MARK: - Add Rule Sheet
struct AddRuleSheet: View {
    var initialKeyword: String? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]
    @State private var keyword = ""
    @State private var category = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 15) {
                    GridRow {
                        Text("Keyword:")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField("e.g. STARBUCKS", text: $keyword)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Category:")
                            .foregroundStyle(.secondary)
                        CategoryPicker(selection: $category)
                            .labelsHidden()
                    }
                }
                .padding()
                Spacer()
            }
            .navigationTitle("Add Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndApply()
                    }
                    .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty || category.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 400, height: 220)
        .onAppear {
            if let kw = initialKeyword { keyword = kw }
        }
    }

    private func saveAndApply() {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        let cat = category.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !cat.isEmpty else { return }
        let newRule = CategoryRule(keyword: kw, category: cat)
        modelContext.insert(newRule)
        var updateCount = 0
        for tx in allTransactions {
            if tx.originalDescription.localizedCaseInsensitiveContains(kw) ||
               tx.cleanDescription.localizedCaseInsensitiveContains(kw) {
                tx.category = cat
                updateCount += 1
            }
        }
        try? modelContext.save()
        print("Rule saved and applied to \(updateCount) historical transactions.")
        dismiss()
    }
}

// MARK: - Edit Rule Sheet
struct EditRuleSheet: View {
    @Bindable var rule: CategoryRule
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Rule")
                .font(.headline)
                .padding(.top)

            Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 15) {
                GridRow {
                    Text("Keyword:")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    TextField("e.g. STARBUCKS", text: $rule.keyword)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Category:")
                        .foregroundStyle(.secondary)
                    CategoryPicker(selection: $rule.category)
                        .labelsHidden()
                }
            }
            .padding()

            Spacer()

            HStack {
                Button("Delete Rule", role: .destructive) {
                    modelContext.delete(rule)
                    try? modelContext.save()
                    onDelete?()
                    dismiss()
                }
                Spacer()
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 250)
    }
}
