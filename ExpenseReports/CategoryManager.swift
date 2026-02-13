//
//  CategoryManager.swift
//  ExpenseReports
//
//  Seeds the master category list on first launch.
//

import SwiftData
import Foundation

class CategoryManager {
    static let defaults = [
        "Home & Utilities",
        "Transportation",
        "Groceries",
        "Personal & Family Care",
        "Health",
        "Insurance",
        "Restaurants & Dining",
        "Shopping & Entertainment",
        "Travel",
        "Cash, Cheque and Miscellaneous",
        "Giving",
        "Business Expenses",
        "Education",
        "Finance",
        "Uncategorised",
        "Income",
        "Transfer",
        "Credit Card Payment"
    ]

    static func ensureDefaults(context: ModelContext) {
        let descriptor = FetchDescriptor<CategoryItem>()
        let count = (try? context.fetchCount(descriptor)) ?? 0

        if count == 0 {
            print("🌱 Seeding Default Categories...")
            for name in defaults {
                let item = CategoryItem(name: name, isSystemDefault: true)
                context.insert(item)
            }
            try? context.save()
        }
    }
}
