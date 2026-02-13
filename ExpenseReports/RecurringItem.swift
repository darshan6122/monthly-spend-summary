//
//  RecurringItem.swift
//  ExpenseReports
//
//  Phase 6: Detected recurring payments (subscriptions, rent, etc.).
//

import Foundation
import SwiftData

@Model
final class RecurringItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var amount: Decimal
    var detectedDate: Date
    var frequency: String
    var isActive: Bool

    init(name: String, amount: Decimal, date: Date) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.detectedDate = date
        self.frequency = "Monthly"
        self.isActive = true
    }
}
