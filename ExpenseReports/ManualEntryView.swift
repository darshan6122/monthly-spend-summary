//
//  ManualEntryView.swift
//  ExpenseReports
//
//  Manual entry for cash and pending expenses (no CSV).
//

import SwiftUI
import SwiftData

struct ManualEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var desc = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var category = "Uncategorised"
    @State private var showAmountError = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $desc)
                TextField("Amount", text: $amount)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                DatePicker("Date", selection: $date, displayedComponents: .date)
                CategoryPicker(selection: $category)
            }
            .navigationTitle("Add Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(desc.isEmpty || amount.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 400, height: 320)
        .alert("Invalid Amount", isPresented: $showAmountError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter a valid number (e.g. 25 or 25,50).")
        }
    }

    private func save() {
        let cleanAmount = amount
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let decimalAmount = Decimal(string: cleanAmount) else {
            showAmountError = true
            return
        }
        let tx = Transaction(
            date: date,
            originalDescription: desc.trimmingCharacters(in: .whitespaces),
            amount: -decimalAmount,
            sourceFile: "Manual Entry",
            cleanDescription: desc.trimmingCharacters(in: .whitespaces),
            category: category
        )
        modelContext.insert(tx)
        try? modelContext.save()
        dismiss()
    }
}

