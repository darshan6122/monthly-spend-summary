//
//  TaxExporter.swift
//  ExpenseReports
//
//  Tax-ready CSV export for deductible / business categories.
//

import Foundation

struct TaxExporter {
    static let taxCategories = ["Business Expenses", "Education", "Health", "Giving", "Home & Utilities"]

    static func generateTaxCSV(transactions: [Transaction]) -> String {
        var csvString = "Date,Description,Category,Amount,Source\n"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let filtered = transactions.filter { taxCategories.contains($0.category) }
        for tx in filtered {
            let dateStr = formatter.string(from: tx.date)
            let desc = escapeCSV(tx.cleanDescription.isEmpty ? tx.originalDescription : tx.cleanDescription)
            let cat = escapeCSV(tx.category)
            let amountStr = "\(tx.amount)"
            let source = escapeCSV(tx.sourceFile)
            csvString.append("\(dateStr),\(desc),\(cat),\(amountStr),\(source)\n")
        }
        return csvString
    }

    private static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
