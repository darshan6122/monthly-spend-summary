//
//  RulesView.swift
//  ExpenseReports
//
//  Phase 3: Rule Manager — add, edit, delete categorization rules (no code).
//

import SwiftUI
import SwiftData

struct RulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryRule.keyword) private var rules: [CategoryRule]

    @State private var newKeyword = ""
    @State private var newCategory = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Add New Rule") {
                    TextField("Keyword (e.g. Netflix)", text: $newKeyword)
                    CategoryPicker(selection: $newCategory)
                    Button("Save Rule") {
                        addRule()
                    }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty || newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Divider()

            List {
                ForEach(rules) { rule in
                    HStack {
                        Text(rule.keyword)
                            .fontWeight(.medium)
                        Spacer()
                        Text(rule.category)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
                .onDelete(perform: deleteRules)
            }
        }
        .navigationTitle("Categorization Rules")
    }

    private func addRule() {
        let kw = newKeyword.trimmingCharacters(in: .whitespaces)
        let cat = newCategory.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !cat.isEmpty else { return }
        let rule = CategoryRule(keyword: kw, category: cat)
        modelContext.insert(rule)
        newKeyword = ""
        newCategory = ""
        try? modelContext.save()
    }

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rules[index])
        }
        try? modelContext.save()
    }
}
