//
//  AppSettings.swift
//  ExpenseReports
//

import SwiftUI

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
