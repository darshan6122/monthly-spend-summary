//
//  UpcomingBillsCard.swift
//  ExpenseReports
//
//  Phase 13: Total committed spend from active subscriptions (next month forecast).
//

import SwiftUI
import SwiftData
import AppKit

struct UpcomingBillsCard: View {
    @Query(filter: #Predicate<RecurringItem> { $0.isActive == true }) private var activeSubs: [RecurringItem]

    private var totalCommitted: Decimal {
        activeSubs.reduce(Decimal(0)) { $0 + abs($1.amount) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.purple)
                Text("Committed Spend")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(totalCommitted, format: .currency(code: "CAD"))
                .font(.title.bold())

            Text("Total for \(activeSubs.count) active subscription\(activeSubs.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
}
