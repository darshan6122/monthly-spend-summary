//
//  Transaction.swift
//  ExpenseReports
//
//  Phase 1: SwiftData model — single source of truth. No "month folder";
//  the app derives month from date when needed.
//

import Foundation
import SwiftData

@Model
final class Transaction {
    /// Unique ID (prevents duplicates when re-importing).
    @Attribute(.unique) var id: UUID

    var date: Date
    /// Raw bank text (e.g. "AMZN Mktp US*1234").
    var originalDescription: String
    /// User-friendly name after normalization (e.g. "Amazon"). Defaults to original.
    var cleanDescription: String
    /// Negative = expense, positive = income.
    var amount: Decimal
    /// e.g. "Groceries", "Uncategorized".
    var category: String
    /// Source file for audit (e.g. "cibc_jan2025.csv").
    var sourceFile: String
    /// Cached merchant logo (Clearbit); stored externally so the DB stays fast.
    @Attribute(.externalStorage) var logoData: Data?

    init(
        date: Date,
        originalDescription: String,
        amount: Decimal,
        sourceFile: String,
        cleanDescription: String? = nil,
        category: String = "Uncategorized"
    ) {
        self.id = UUID()
        self.date = date
        self.originalDescription = originalDescription
        self.cleanDescription = cleanDescription ?? originalDescription
        self.amount = amount
        self.category = category
        self.sourceFile = sourceFile
    }
}
