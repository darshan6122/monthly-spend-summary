//
//  BackupManager.swift
//  ExpenseReports
//
//  Phase 7: Export entire database to a single JSON file.
//

import Foundation
import SwiftData

struct BackupData: Codable {
    var version: Int = 1
    var date: Date = Date()
    var categories: [String] = []
    var transactions: [TransactionCodable]
    var rules: [RuleCodable]
    var budgets: [BudgetCodable]
    var recurring: [RecurringCodable]

    struct TransactionCodable: Codable {
        var date: Date
        var desc: String
        var amount: Decimal
        var category: String
        var source: String
    }

    struct RuleCodable: Codable {
        var keyword: String
        var category: String
    }

    struct BudgetCodable: Codable {
        var category: String
        var limit: Decimal
    }

    struct RecurringCodable: Codable {
        var name: String
        var amount: Decimal
        var detectedDate: Date
        var isActive: Bool
    }
}

enum BackupManager {
    static func createBackup(context: ModelContext) -> URL? {
        do {
            let txs = try context.fetch(FetchDescriptor<Transaction>())
            let rules = try context.fetch(FetchDescriptor<CategoryRule>())
            let budgets = try context.fetch(FetchDescriptor<Budget>())
            let recurring = try context.fetch(FetchDescriptor<RecurringItem>())
            let categories = (try? context.fetch(FetchDescriptor<CategoryItem>()))?.map(\.name) ?? []

            let backup = BackupData(
                categories: categories,
                transactions: txs.map { .init(date: $0.date, desc: $0.originalDescription, amount: $0.amount, category: $0.category, source: $0.sourceFile) },
                rules: rules.map { .init(keyword: $0.keyword, category: $0.category) },
                budgets: budgets.map { .init(category: $0.category, limit: $0.limitAmount) },
                recurring: recurring.map { .init(name: $0.name, amount: $0.amount, detectedDate: $0.detectedDate, isActive: $0.isActive) }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(backup)

            let filename = "ExpenseReports_Backup_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Restore from a previously exported JSON backup. Adds to existing data (does not wipe first).
    static func restoreBackup(from url: URL, context: ModelContext) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        for catName in backup.categories {
            let descriptor = FetchDescriptor<CategoryItem>(predicate: #Predicate<CategoryItem> { $0.name == catName })
            let existing = (try? context.fetch(descriptor)) ?? []
            if existing.isEmpty {
                context.insert(CategoryItem(name: catName, isSystemDefault: false))
            }
        }

        for txData in backup.transactions {
            let tx = Transaction(
                date: txData.date,
                originalDescription: txData.desc,
                amount: txData.amount,
                sourceFile: txData.source,
                cleanDescription: txData.desc,
                category: txData.category
            )
            context.insert(tx)
        }

        let existingKeywords = Set((try? context.fetch(FetchDescriptor<CategoryRule>())) ?? []).map(\.keyword)
        for ruleData in backup.rules where !existingKeywords.contains(ruleData.keyword) {
            let rule = CategoryRule(keyword: ruleData.keyword, category: ruleData.category)
            context.insert(rule)
        }

        let existingBudgetCategories = Set((try? context.fetch(FetchDescriptor<Budget>())) ?? []).map(\.category)
        for budgetData in backup.budgets where !existingBudgetCategories.contains(budgetData.category) {
            let budget = Budget(category: budgetData.category, limit: budgetData.limit)
            context.insert(budget)
        }

        for r in backup.recurring {
            let item = RecurringItem(name: r.name, amount: r.amount, date: r.detectedDate)
            item.isActive = r.isActive
            context.insert(item)
        }

        try context.save()
    }
}
