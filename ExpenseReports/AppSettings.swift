//
//  AppSettings.swift
//  ExpenseReports
//

import SwiftUI

/// Canonical list of expense categories (training, reports, Quick Stats). Keep in sync with Scripts/merge_and_categorize.py.
enum CategoryTypes {
    static let all: [String] = [
        "Food & Dining",
        "Groceries",
        "Transport",
        "Shopping",
        "Bills & Utilities",
        "Transfer to Savings",
        "Bank Transfers",
        "Entertainment",
        "Health & Pharmacy",
        "Subscriptions",
        "Travel",
        "Gifts & Donations",
        "Other",
        "Uncategorized"
    ]

    static let defaultCategory = "Uncategorized"
}

/// User preferences (persisted in UserDefaults).
enum AppSettings {
    private static let openFolderAfterReportKey = "ExpenseReports.openFolderAfterReport"
    private static let showTipsKey = "ExpenseReports.showTips"

    static var openFolderAfterReport: Bool {
        get { UserDefaults.standard.object(forKey: openFolderAfterReportKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: openFolderAfterReportKey) }
    }

    static var showTips: Bool {
        get { UserDefaults.standard.object(forKey: showTipsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showTipsKey) }
    }
}
