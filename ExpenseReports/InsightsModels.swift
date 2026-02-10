//
//  InsightsModels.swift
//  ExpenseReports
//
//  Models for month summary, audit, merged CSV, and delta insights.
//

import Foundation

// MARK: - Month summary (from month_summary.json)
struct MonthSummary: Codable {
    let totalSpent: Double
    let totalCredits: Double
    let byCategory: [String: Double]
    let savingsTransfer: Double
    let transactionCount: Int

    enum CodingKeys: String, CodingKey {
        case totalSpent = "total_spent"
        case totalCredits = "total_credits"
        case byCategory = "by_category"
        case savingsTransfer = "savings_transfer"
        case transactionCount = "transaction_count"
    }
}

// MARK: - Audit (from audit.json)
struct AuditInfo: Codable {
    let totalCredits: Double
    let totalDebits: Double
    let duplicateCount: Int
    let filesProcessed: Int
    let transactionCount: Int
    /// Rows excluded by ignore_list.json.
    let ignoredCount: Int?
    /// Filled by merge script when using 3-step categorization (Mapping → Regex → ML).
    let categorizedViaMapping: Int?
    let categorizedViaRegex: Int?
    let categorizedViaMl: Int?
    let uncategorized: Int?

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalDebits = "total_debits"
        case duplicateCount = "duplicate_count"
        case filesProcessed = "files_processed"
        case transactionCount = "transaction_count"
        case ignoredCount = "ignored_count"
        case categorizedViaMapping = "categorized_via_mapping"
        case categorizedViaRegex = "categorized_via_regex"
        case categorizedViaMl = "categorized_via_ml"
        case uncategorized = "uncategorized"
    }
}

// MARK: - Single row from merged.csv
struct MergedTransaction: Identifiable {
    var id: String { "\(date)_\(description)_\(amount)" }
    let date: String
    let description: String
    let amount: Double
    let category: String
}

// MARK: - Category total for charts
struct CategoryAmount: Identifiable {
    var id: String { category }
    let category: String
    let amount: Double
}

// MARK: - Delta insight for Quick Stats
struct DeltaInsight {
    let spendingDeltaPercent: Double?  // vs last month
    let spendingDeltaMessage: String?
    let categoryAlert: (category: String, delta: Double)?  // e.g. "Dining Out" up $150
    let savingsTransfer: Double?
}

// MARK: - Transaction split (one portion of a split transaction)
struct TransactionSplitPart: Codable {
    let category: String
    let amount: Double
}

// MARK: - Transaction splits per month: key = "date|description|amount", value = array of parts (must sum to original amount)
typealias TransactionSplitsMap = [String: [TransactionSplitPart]]
