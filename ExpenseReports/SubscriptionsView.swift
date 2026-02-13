//
//  SubscriptionsView.swift
//  ExpenseReports
//
//  Phase 6: Monthly burn rate + detected subscriptions.
//

import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringItem.amount, order: .reverse) private var allRecurring: [RecurringItem]
    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]

    private var subscriptions: [RecurringItem] {
        allRecurring.filter(\.isActive)
    }

    private var monthlyBurnRate: Decimal {
        subscriptions.reduce(Decimal(0)) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                Text("Monthly Fixed Costs")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(monthlyBurnRate, format: .currency(code: "CAD"))
                    .font(.system(size: 40, weight: .bold))
                Text("\(subscriptions.count) active subscription\(subscriptions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(12)
            .padding()

            List {
                Section("Detected Subscriptions") {
                    if subscriptions.isEmpty {
                        ContentUnavailableView(
                            "No Subscriptions",
                            systemImage: "magnifyingglass",
                            description: Text("Import more data, then use the Scan button in the toolbar (⌘R) to detect recurring payments.")
                        )
                    } else {
                        ForEach(subscriptions) { sub in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sub.name)
                                        .font(.headline)
                                    Text("Last paid: \(sub.detectedDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(sub.amount, format: .currency(code: "CAD"))
                                    .fontWeight(.semibold)
                            }
                        }
                        .onDelete(perform: deactivateAtOffsets)
                    }
                }
            }
        }
        .navigationTitle("Subscriptions")
    }

    private func deactivateAtOffsets(_ offsets: IndexSet) {
        for index in offsets {
            let sub = subscriptions[index]
            sub.isActive = false
        }
        try? modelContext.save()
    }
}
