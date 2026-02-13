//
//  CategoryPicker.swift
//  ExpenseReports
//
//  Reusable dropdown: select from master list or "Add New Category...".
//

import SwiftUI
import SwiftData

struct CategoryPicker: View {
    @Binding var selection: String
    @Query(sort: \CategoryItem.name) private var categories: [CategoryItem]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddSheet = false
    @State private var newCategoryName = ""

    var body: some View {
        HStack {
            Picker("Category", selection: $selection) {
                Text("Select Category").tag("")

                Divider()

                ForEach(categories) { item in
                    Text(item.name).tag(item.name)
                }

                Divider()

                Text("➕ Add New Category...").tag("ADD_NEW")
            }
            .onChange(of: selection) { oldValue, newValue in
                if newValue == "ADD_NEW" {
                    selection = oldValue
                    showAddSheet = true
                }
            }
        }
        .alert("New Category", isPresented: $showAddSheet) {
            TextField("Category Name", text: $newCategoryName)
            Button("Cancel", role: .cancel) { newCategoryName = "" }
            Button("Add") {
                addNewCategory()
            }
        } message: {
            Text("Enter the name for your new custom category.")
        }
    }

    private func addNewCategory() {
        let cleanName = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else { return }

        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
            selection = existing.name
        } else {
            let newItem = CategoryItem(name: cleanName, isSystemDefault: false)
            modelContext.insert(newItem)
            try? modelContext.save()
            selection = cleanName
        }
        newCategoryName = ""
    }
}
