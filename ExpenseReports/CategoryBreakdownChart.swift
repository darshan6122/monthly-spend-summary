//
//  CategoryBreakdownChart.swift
//  ExpenseReports
//
//  Phase 9/11: Interactive donut — tap a slice to see that category's transactions.
//

import SwiftUI
import Charts
import SwiftData
import AppKit

struct CategoryBreakdownChart: View {
    var transactions: [Transaction]
    @Binding var selectedCategory: String?

    struct CategoryData: Identifiable {
        var id: String { category }
        let category: String
        let amount: Double
    }

    private var data: [CategoryData] {
        let grouped = Dictionary(grouping: transactions, by: { $0.category })
        return grouped.map { key, txs in
            let total = txs.reduce(Decimal(0)) { $0 + abs($1.amount) }
            let amount = NSDecimalNumber(decimal: total).doubleValue
            return CategoryData(category: key, amount: amount)
        }
        .sorted { $0.amount > $1.amount }
    }

    @State private var rawSelection: Double?

    var body: some View {
        VStack(alignment: .leading) {
            Text(selectedCategory == nil ? "Spending Breakdown" : "\(selectedCategory!) Spending")
                .font(.headline)

            if data.isEmpty {
                ContentUnavailableView("No Data", systemImage: "chart.pie")
            } else {
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Category", item.category))
                    .cornerRadius(5)
                    .opacity(selectedCategory == nil || selectedCategory == item.category ? 1.0 : 0.3)
                }
                .frame(height: 300)
                .chartLegend(position: .trailing, alignment: .center)
                .chartAngleSelection(value: $rawSelection)
                .onChange(of: rawSelection) { _, newValue in
                    if let amount = newValue, let item = data.first(where: { abs($0.amount - amount) < 0.01 }) {
                        selectedCategory = item.category
                    } else {
                        selectedCategory = nil
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}
