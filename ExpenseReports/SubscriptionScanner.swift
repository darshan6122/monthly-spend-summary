//
//  SubscriptionScanner.swift
//  ExpenseReports
//
//  Phase 6: Finds repeating payments (same description + same amount, 3+ times).
//

import Foundation
import SwiftData

enum SubscriptionScanner {
    private static let minOccurrences = 3
    private static let amountTolerance = Decimal(0.01)

    /// Groups transactions by cleaned description, finds same-amount repeats (3+). Updates existing or inserts new (Audit #16).
    static func scan(transactions: [Transaction], context: ModelContext) {
        let grouped = Dictionary(grouping: transactions, by: { $0.cleanDescription.isEmpty ? $0.originalDescription : $0.cleanDescription })

        for (name, txs) in grouped where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            guard txs.count >= minOccurrences else { continue }

            let sortedTxs = txs.sorted { $0.date > $1.date }
            guard let latest = sortedTxs.first else { continue }

            let amounts = sortedTxs.map { abs($0.amount) }
            let first = amounts[0]
            let sameAmount = amounts.allSatisfy { abs($0 - first) < amountTolerance }
            guard sameAmount else { continue }

            let descriptor = FetchDescriptor<RecurringItem>(predicate: #Predicate<RecurringItem> { $0.name == name })
            if let existing = try? context.fetch(descriptor).first {
                if latest.date > existing.detectedDate {
                    existing.detectedDate = latest.date
                    existing.amount = abs(latest.amount)
                }
            } else {
                let newItem = RecurringItem(name: name, amount: abs(latest.amount), date: latest.date)
                context.insert(newItem)
            }
        }
    }
}
