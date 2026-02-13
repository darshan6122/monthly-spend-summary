//
//  Categorizer.swift
//  ExpenseReports
//
//  Phase 2: Global Brain — applies CategoryRule(s) to transactions.
//

import Foundation
import SwiftData

final class Categorizer {
    private var rules: [CategoryRule]

    init(context: ModelContext) {
        let descriptor = FetchDescriptor<CategoryRule>(predicate: #Predicate { $0.isActive == true })
        self.rules = (try? context.fetch(descriptor)) ?? []
        // Longest match wins
        self.rules.sort { $0.keyword.count > $1.keyword.count }
    }

    func categorize(_ transaction: Transaction) {
        let raw = transaction.originalDescription
        let desc = raw.lowercased()

        for rule in rules {
            let kw = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if kw.isEmpty { continue }
            let needle = kw.lowercased()
            let matched: Bool
            switch rule.matchType.lowercased() {
            case "exact":
                matched = desc == needle
            case "startswith":
                matched = desc.hasPrefix(needle)
            default: // "contains"
                matched = desc.contains(needle)
            }
            if matched {
                transaction.category = rule.category
                // Simple vendor normalization for display: use keyword as clean name
                transaction.cleanDescription = kw
                return
            }
        }

        // Minimal built-in fallbacks (can be moved to DB later)
        if desc.contains("fee") { transaction.category = "Bank Fees" }
        else if desc.contains("transfer") { transaction.category = "Transfers" }
        else { transaction.category = "Uncategorized" }
        transaction.cleanDescription = raw
    }

    /// Re-apply rules to an in-memory set of transactions (call after rule changes).
    func reapplyRules(to transactions: [Transaction]) {
        for tx in transactions {
            categorize(tx)
        }
    }
}

