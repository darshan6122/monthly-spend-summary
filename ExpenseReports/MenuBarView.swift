//
//  MenuBarView.swift
//  ExpenseReports
//
//  Mini-dashboard shown in the menu bar popover.
//

import SwiftUI
import SwiftData

// 1. EXTRACTED SUBVIEW
struct MenuBarRow: View {
    let tx: Transaction
    
    var body: some View {
        HStack {
            // Description
            Text(tx.cleanDescription.isEmpty ? tx.originalDescription : tx.cleanDescription)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            // Amount
            Text(tx.amount, format: .currency(code: "CAD"))
                .font(.system(size: 12))
                // THE FIX IS HERE: Use 'Color.primary' instead of '.primary'
                .foregroundStyle(tx.amount < 0 ? Color.primary : Color.green)
        }
    }
}

// 2. MAIN VIEW
struct MenuBarView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    // Calculate Spend
    private var todaysSpend: Decimal {
        let today = Calendar.current.startOfDay(for: Date())
        return transactions
            .filter { $0.date >= today && $0.amount < 0 }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }
    }
    
    // Prepare Data
    private var recentTransactions: [Transaction] {
        return Array(transactions.prefix(3))
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Today's Spend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(todaysSpend, format: .currency(code: "CAD"))
                    .font(.title2)
                    .bold()
            }
            .padding(.top)

            Divider()

            // Recent List
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(recentTransactions, id: \.id) { tx in
                    MenuBarRow(tx: tx)
                }
            }
            
            Divider()
            
            // Footer
            Button("Open Finance OS") {
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 300)
    }
}
