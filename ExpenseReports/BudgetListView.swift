//
//  BudgetListView.swift
//  ExpenseReports
//
//  Dedicated Budget Management: list, inline edit amounts, add from master categories.
//

import SwiftUI
import SwiftData

struct BudgetListView: View {
    @Query(sort: \Budget.category) private var budgets: [Budget]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddBudget = false

    var body: some View {
        List {
            Section("Active Monthly Budgets") {
                if budgets.isEmpty {
                    Text("No budgets yet. Tap Add Budget to create one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(budgets) { budget in
                        BudgetRowView(budget: budget)
                    }
                }
            }
        }
        .navigationTitle("Manage Budgets")
        .toolbar {
            Button { showingAddBudget = true } label: {
                Label("Add Budget", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingAddBudget) {
            AddBudgetSheet()
        }
    }
}

// MARK: - Budget row with inline editable amount
private struct BudgetRowView: View {
    @Bindable var budget: Budget
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 20) {
            Text(budget.category)
                .font(.headline)
                .frame(width: 180, alignment: .leading)

            Spacer()

            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("Limit", value: $budget.limitAmount, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: budget.limitAmount) { _, _ in
                        try? modelContext.save()
                    }
            }

            Button(role: .destructive) {
                modelContext.delete(budget)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Budget Sheet
struct AddBudgetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Budget.category) private var existingBudgets: [Budget]

    @State private var selectedCategory = ""
    @State private var amountString = ""
    @State private var showAmountError = false

    private var parsedAmount: Decimal? {
        let trimmed = amountString.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: trimmed)
    }

    private var canCreate: Bool {
        !selectedCategory.isEmpty && (parsedAmount ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Set New Monthly Budget")
                .font(.headline)
                .padding(.top)

            Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 15) {
                GridRow {
                    Text("Category:")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    CategoryPicker(selection: $selectedCategory)
                        .labelsHidden()
                }
                GridRow {
                    Text("Monthly Limit:")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $amountString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }
            .padding()

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Budget") {
                    createBudget()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
            .padding()
        }
        .frame(width: 400, height: 250)
        .alert("Invalid Amount", isPresented: $showAmountError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter a valid number (e.g. 500 or 500.00).")
        }
    }

    private func createBudget() {
        guard let amount = parsedAmount, amount > 0 else {
            showAmountError = true
            return
        }
        if let existing = existingBudgets.first(where: { $0.category == selectedCategory }) {
            existing.limitAmount = amount
        } else {
            let newBudget = Budget(category: selectedCategory, limit: amount)
            modelContext.insert(newBudget)
        }
        try? modelContext.save()
        dismiss()
    }
}
