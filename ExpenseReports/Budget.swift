//
//  Budget.swift
//  ExpenseReports
//
//  Phase 5: Monthly spending limit per category.
//

import Foundation
import SwiftData

@Model
final class Budget {
    @Attribute(.unique) var category: String
    var limitAmount: Decimal

    init(category: String, limit: Decimal) {
        self.category = category
        self.limitAmount = limit
    }
}
