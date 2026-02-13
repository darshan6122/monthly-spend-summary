//
//  CategoryItem.swift
//  ExpenseReports
//
//  Strict Category System: master list of approved categories (replaces free-form strings).
//

import SwiftData
import Foundation

@Model
class CategoryItem {
    @Attribute(.unique) var name: String
    var isSystemDefault: Bool

    init(name: String, isSystemDefault: Bool = false) {
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}
