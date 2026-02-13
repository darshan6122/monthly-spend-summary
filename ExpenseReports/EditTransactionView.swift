//
//  EditTransactionView.swift
//  ExpenseReports
//
//  Edit transaction details with the standardized Category Picker.
//

import SwiftUI
import SwiftData

struct EditTransactionView: View {
    @Bindable var transaction: Transaction
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Description", text: $transaction.cleanDescription)

                    DatePicker("Date", selection: $transaction.date, displayedComponents: .date)

                    CategoryPicker(selection: $transaction.category)
                }

                Section("Amount") {
                    HStack {
                        Text("$")
                        TextField("Amount", value: $transaction.amount, format: .number)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                Section("Metadata") {
                    LabeledContent("Original Desc", value: transaction.originalDescription)
                    LabeledContent("Source File", value: transaction.sourceFile)
                }
            }
            .navigationTitle("Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 400, height: 450)
    }
}
