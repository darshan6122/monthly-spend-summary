//
//  BudgetSettingsView.swift
//  ExpenseReports
//
//  Phase 5: Set monthly limits per category.
//

import SwiftUI
import SwiftData

struct BudgetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Budget.category) private var budgets: [Budget]

    @State private var selectedCategory = ""
    @State private var amountString = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Set Monthly Limit") {
                    CategoryPicker(selection: $selectedCategory)
                    TextField("Amount ($)", text: $amountString)
                    Button("Save Budget") {
                        saveBudget()
                    }
                    .disabled(selectedCategory.isEmpty || amountString.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 160)

            Divider()

            List {
                ForEach(budgets) { budget in
                    HStack {
                        Text(budget.category)
                            .fontWeight(.medium)
                        Spacer()
                        Text(budget.limitAmount, format: .currency(code: "CAD"))
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteBudgets)
            }
        }
        .navigationTitle("Budget Settings")
    }

    private func saveBudget() {
        let trimmed = amountString.trimmingCharacters(in: .whitespaces)
        guard let amount = Decimal(string: trimmed.filter { $0.isNumber || $0 == "." }),
              amount > 0 else { return }

        if let existing = budgets.first(where: { $0.category == selectedCategory }) {
            existing.limitAmount = amount
        } else {
            let newBudget = Budget(category: selectedCategory, limit: amount)
            modelContext.insert(newBudget)
        }
        amountString = ""
        try? modelContext.save()
    }

    private func deleteBudgets(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(budgets[index])
        }
        try? modelContext.save()
    }
}
