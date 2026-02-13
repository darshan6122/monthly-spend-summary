//
//  Account.swift
//  ExpenseReports
//
//  Net Worth Tracker: balances by account (Bank, Investment, Debt).
//

import SwiftData
import Foundation

@Model
final class Account {
    @Attribute(.unique) var name: String
    var balance: Decimal
    var type: String
    var lastUpdated: Date

    init(name: String, balance: Decimal = 0, type: String = "Bank") {
        self.name = name
        self.balance = balance
        self.type = type
        self.lastUpdated = Date()
    }
}
