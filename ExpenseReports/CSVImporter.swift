//
//  CSVImporter.swift
//  ExpenseReports
//
//  Universal parser: Credit Card (5 cols) vs Bank Account (4 cols) detected per row.
//

import Foundation
import SwiftData

struct CSVImporter {
    /// Supported date formats (order matters: try ISO first, then locale).
    private static let dateFormatters: [DateFormatter] = {
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        iso.locale = Locale(identifier: "en_US_POSIX")
        let us = DateFormatter()
        us.dateFormat = "MM/dd/yyyy"
        us.locale = Locale(identifier: "en_US_POSIX")
        let dash = DateFormatter()
        dash.dateFormat = "dd-MM-yyyy"
        dash.locale = Locale(identifier: "en_US_POSIX")
        return [iso, us, dash]
    }()

    static func parse(url: URL) throws -> [Transaction] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var transactions: [Transaction] = []
        let rows = content.components(separatedBy: .newlines)
        let fileName = url.lastPathComponent

        for row in rows {
            if row.isEmpty { continue }

            let columns = row.components(separatedBy: ",")
            let count = columns.count
            guard count >= 4 else { continue }

            // A. Date (always column 0)
            let dateString = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if dateString.lowercased().contains("date") { continue }
            guard let date = parseDate(dateString) else { continue }

            // B. Detect format from last column
            // Credit Card: last column is masked card number (e.g. "4502********0853")
            // Bank Account: last column is Credit amount (numeric)
            let lastColumn = columns[count - 1].trimmingCharacters(in: .whitespacesAndNewlines)
            let isCreditCard = lastColumn.contains("*") || (lastColumn.count > 10 && Decimal(string: lastColumn.replacingOccurrences(of: "\"", with: "")) == nil)

            var creditString: String
            var debitString: String
            var descEndIndex: Int

            if isCreditCard && count >= 5 {
                // Credit Card: [Date, Description..., Debit, Credit, CardNum]
                creditString = columns[count - 2]
                debitString = columns[count - 3]
                descEndIndex = count - 4
            } else {
                // Bank Account: [Date, Description..., Debit, Credit]
                creditString = columns[count - 1]
                debitString = columns[count - 2]
                descEndIndex = count - 3
            }

            // C. Parse amounts
            let cleanCredit = creditString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            let cleanDebit = debitString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            let credit = Decimal(string: cleanCredit) ?? 0
            let debit = Decimal(string: cleanDebit) ?? 0

            // D. Net amount: income = positive, expense = negative
            var netAmount: Decimal = 0
            if credit > 0 {
                netAmount = credit
            } else if debit > 0 {
                netAmount = -debit
            }

            // E. Description = columns 1...descEndIndex rejoined (handles commas in desc)
            let description: String
            if descEndIndex >= 1 {
                description = columns[1...descEndIndex]
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: ",")
                    .replacingOccurrences(of: "\"", with: "")
            } else {
                description = columns[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            }

            let tx = Transaction(
                date: date,
                originalDescription: description,
                amount: netAmount,
                sourceFile: fileName
            )
            transactions.append(tx)
        }
        return transactions
    }

    private static func parseDate(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        for formatter in dateFormatters {
            if let d = formatter.date(from: trimmed) { return d }
        }
        return nil
    }
}
