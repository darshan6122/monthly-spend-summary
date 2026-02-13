//
//  CategoryRule.swift
//  ExpenseReports
//
//  Phase 2: Global Brain — user-defined categorization rules stored in SwiftData.
//

import Foundation
import SwiftData

@Model
final class CategoryRule {
    /// Unique keyword/phrase the rule matches on (e.g. "Tim Hortons").
    @Attribute(.unique) var keyword: String
    /// Category to apply when matched (e.g. "Food & Drink").
    var category: String
    /// "contains", "exact", or "startsWith"
    var matchType: String
    var isActive: Bool

    init(keyword: String, category: String, matchType: String = "contains", isActive: Bool = true) {
        self.keyword = keyword
        self.category = category
        self.matchType = matchType
        self.isActive = isActive
    }
}

