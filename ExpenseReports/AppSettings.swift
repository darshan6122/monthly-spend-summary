//
//  AppSettings.swift
//  ExpenseReports
//

import SwiftUI

/// Canonical list of expense categories (training, reports, Quick Stats). Must match Scripts/make_monthly_report.py ALL_CATEGORIES.
enum CategoryTypes {
    static let all: [String] = [
        "Work Income",
        "Transfers & Payments",
        "Shopping & Groceries",
        "Food & Drink",
        "Restaurants",
        "Transport & Travel",
        "Subscriptions & Bills",
        "Utilities & Bills",
        "Entertainment",
        "Fees & Interest",
        "Health",
        "Pharmacy",
        "Personal Care",
        "Gas & Auto",
        "Uncategorized"
    ]

    static let defaultCategory = "Uncategorized"
}

/// User preferences (persisted in UserDefaults).
enum AppSettings {
    private static let openFolderAfterReportKey = "ExpenseReports.openFolderAfterReport"
    private static let showTipsKey = "ExpenseReports.showTips"
    private static let budgetLimitsKey = "ExpenseReports.budgetLimits"
    private static let remindEndOfMonthKey = "ExpenseReports.remindEndOfMonth"
    private static let mlConfidenceThresholdKey = "ExpenseReports.mlConfidenceThreshold"
    private static let watchDownloadsKey = "ExpenseReports.watchDownloadsFolder"
    private static let enableBudgetRolloverKey = "ExpenseReports.enableBudgetRollover"
    private static let rolloverBalancesKey = "ExpenseReports.rolloverBalances"

    static var openFolderAfterReport: Bool {
        get { UserDefaults.standard.object(forKey: openFolderAfterReportKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: openFolderAfterReportKey) }
    }

    static var showTips: Bool {
        get { UserDefaults.standard.object(forKey: showTipsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showTipsKey) }
    }

    /// Category name -> monthly budget limit (spending over this shows alert).
    static var budgetLimits: [String: Double] {
        get {
            guard let data = UserDefaults.standard.data(forKey: budgetLimitsKey),
                  let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: budgetLimitsKey)
        }
    }

    static func setBudgetLimit(category: String, value: Double?) {
        var limits = budgetLimits
        if let v = value, v > 0 {
            limits[category] = v
        } else {
            limits.removeValue(forKey: category)
        }
        budgetLimits = limits
    }

    /// When true, app schedules a monthly notification (1st of each month) to remind running the report.
    static var remindEndOfMonth: Bool {
        get { UserDefaults.standard.object(forKey: remindEndOfMonthKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: remindEndOfMonthKey) }
    }

    /// ML confidence threshold (0.0–1.0). Lower = more items categorized (more risk); higher = fewer ML guesses. Default 0.70.
    static var mlConfidenceThreshold: Double {
        get {
            let v = UserDefaults.standard.double(forKey: mlConfidenceThresholdKey)
            return v > 0 ? v : 0.70
        }
        set { UserDefaults.standard.set(max(0, min(1, newValue)), forKey: mlConfidenceThresholdKey) }
    }

    /// When true, watch ~/Downloads for new cibc*.csv and offer to move to current month.
    static var watchDownloadsFolder: Bool {
        get { UserDefaults.standard.object(forKey: watchDownloadsKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: watchDownloadsKey) }
    }

    /// When true, unspent budget per category rolls over to the next month (effective limit = limit + rollover).
    static var enableBudgetRollover: Bool {
        get { UserDefaults.standard.object(forKey: enableBudgetRolloverKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: enableBudgetRolloverKey) }
    }

    /// Per-category rollover amount (added to this month's limit). Keys = category name.
    static var rolloverBalances: [String: Double] {
        get {
            guard let data = UserDefaults.standard.data(forKey: rolloverBalancesKey),
                  let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: rolloverBalancesKey)
        }
    }

    /// Effective budget limit for a category (limit + rollover when rollover enabled).
    static func effectiveBudgetLimit(category: String) -> Double? {
        let limit = budgetLimits[category] ?? 0
        guard limit > 0 else { return nil }
        if !enableBudgetRollover { return limit }
        let roll = rolloverBalances[category] ?? 0
        return limit + roll
    }
}
