//
//  DashboardView.swift
//  ExpenseReports
//
//  Phase 3/4/5: Charts + Time Travel + Budget Health.
//  Phase 8: Insight cards (Income, Expenses, Net Savings).
//

import SwiftUI
import SwiftData
import Charts
import AppKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date) private var allTransactions: [Transaction]
    @Query(sort: \Budget.category) private var budgets: [Budget]
    @Query(filter: #Predicate<RecurringItem> { $0.isActive == true }) private var activeSubs: [RecurringItem]

    @State private var selectedDate = Date()

    private var committedSpend: Decimal {
        activeSubs.reduce(Decimal(0)) { $0 + abs($1.amount) }
    }
    @State private var selectedCategory: String?

    /// Transactions in the selected month only.
    private var filteredTransactions: [Transaction] {
        let calendar = Calendar.current
        return allTransactions.filter { tx in
            calendar.isDate(tx.date, equalTo: selectedDate, toGranularity: .month)
        }
    }

    /// Spending by category for the selected month (expenses only; positive amounts for display).
    private var spendingByCategory: [(category: String, amount: Double)] {
        let expenses = filteredTransactions.filter { $0.amount < 0 }
        let grouped = Dictionary(grouping: expenses, by: { $0.category })
        return grouped.map { key, value in
            let total = value.reduce(Decimal(0)) { $0 + $1.amount }
            let absDouble = abs(NSDecimalNumber(decimal: total).doubleValue)
            return (category: key, amount: absDouble)
        }.sorted { $0.amount > $1.amount }
    }

    /// Spent in selected month for a category (expenses only), as positive Decimal.
    private func spent(for category: String) -> Decimal {
        let total = filteredTransactions
            .filter { $0.category == category && $0.amount < 0 }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return abs(total)
    }

    private var monthIncome: Decimal {
        filteredTransactions.filter { $0.amount > 0 }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var monthExpense: Decimal {
        filteredTransactions.filter { $0.amount < 0 }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var monthExpenses: [Transaction] {
        filteredTransactions.filter { $0.amount < 0 }
    }

    /// Percent change: this month's spending vs average of previous 3 months (positive = spending up).
    private var spendingTrend: Double {
        let calendar = Calendar.current
        guard let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) else { return 0 }
        guard let startOfThreeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: startOfCurrentMonth),
              let endOfPreviousMonth = calendar.date(byAdding: .day, value: -1, to: startOfCurrentMonth) else { return 0 }
        let historicalTxs = allTransactions.filter { $0.date >= startOfThreeMonthsAgo && $0.date <= endOfPreviousMonth && $0.amount < 0 }
        let totalSpent = historicalTxs.reduce(Decimal(0)) { $0 + $1.amount }
        let average = NSDecimalNumber(decimal: abs(totalSpent) / 3).doubleValue
        guard average > 0 else { return 0 }
        let current = NSDecimalNumber(decimal: abs(monthExpense)).doubleValue
        return ((current - average) / average) * 100
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dashboardHeader
                if filteredTransactions.isEmpty {
                    dashboardEmptyState
                } else {
                    dashboardContent
                }
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Dashboard")
    }

    private var dashboardHeader: some View {
        HStack {
            Text("Spending Overview")
                .font(.title2.bold())
            Spacer()
            Button(action: { moveMonth(by: -1) }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Text(selectedDate, format: .dateTime.month(.wide).year())
                .font(.headline)
                .frame(minWidth: 150)
            Button(action: { moveMonth(by: 1) }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color.primary.opacity(0.04))
    }

    private var dashboardEmptyState: some View {
        ContentUnavailableView(
            "No Data",
            systemImage: "calendar.badge.exclamationmark",
            description: Text("No transactions found for this month.")
        )
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    @ViewBuilder
    private var dashboardContent: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            InsightCard(title: "Income", amount: monthIncome, color: .green, icon: "arrow.down.left")
            InsightCard(title: "Expenses", amount: abs(monthExpense), color: .red, icon: "arrow.up.right")
            InsightCard(title: "Net Savings", amount: monthIncome + monthExpense, color: (monthIncome + monthExpense) >= 0 ? .blue : .orange, icon: "banknote")
            InsightCard(title: "Committed", amount: committedSpend, color: .purple, icon: "calendar.badge.clock")
            TrendInsightCard(trendPercent: spendingTrend)
        }
        .padding(.horizontal)

        UpcomingBillsCard()
            .padding(.horizontal)

        if !monthExpenses.isEmpty {
            CategoryBreakdownChart(transactions: monthExpenses, selectedCategory: $selectedCategory)
                .padding(.horizontal)
        }

        selectedCategoryTransactionsSection(expenses: monthExpenses)

        barChartSection
        categoryListSection

        Divider()
            .padding(.vertical, 8)

        budgetHealthSection
    }

    @ViewBuilder
    private func selectedCategoryTransactionsSection(expenses: [Transaction]) -> some View {
        if let category = selectedCategory {
            categoryTransactionsView(category: category, expenses: expenses)
        }
    }

    private func categoryTransactionsView(category: String, expenses: [Transaction]) -> some View {
        let categoryTxs = Array(expenses.filter { $0.category == category }
            .sorted { $0.date > $1.date }
            .prefix(5))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(category) Transactions")
                    .font(.headline)
                Spacer()
                Button("Clear") { withAnimation { selectedCategory = nil } }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)

            CategoryTransactionRows(transactions: categoryTxs)
                .padding(.horizontal)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var barChartSection: some View {
        Chart(spendingByCategory, id: \.category) { item in
            BarMark(
                x: .value("Category", item.category),
                y: .value("Amount", item.amount)
            )
            .foregroundStyle(by: .value("Category", item.category))
            .annotation(position: .top) {
                Text(item.amount, format: .currency(code: "CAD"))
                    .font(.caption2)
            }
        }
        .padding()
        .frame(height: 300)
    }

    private var categoryListSection: some View {
        List(spendingByCategory, id: \.category) { item in
            HStack {
                Text(item.category)
                    .fontWeight(.medium)
                Spacer()
                Text(item.amount, format: .currency(code: "CAD"))
            }
        }
    }

    @ViewBuilder
    private var budgetHealthSection: some View {
        Text("Budget Health")
            .font(.title2.bold())
            .padding(.horizontal)

        if budgets.isEmpty {
            Text("No budgets set. Go to Budgets to add limits.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            ForEach(budgets) { budget in
                BudgetProgressView(
                    category: budget.category,
                    spent: spent(for: budget.category),
                    limit: budget.limitAmount
                )
                .padding(.horizontal)
            }
        }
    }

    private func moveMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: selectedDate) {
            selectedDate = newDate
        }
    }
}

// MARK: - Category transaction rows (avoids ForEach generic inference in parent)
private struct CategoryTransactionRows: View {
    let transactions: [Transaction]

    var body: some View {
        ForEach(Array(transactions.enumerated()), id: \.element.id) { _, tx in
            HStack {
                Text(tx.cleanDescription.isEmpty ? tx.originalDescription : tx.cleanDescription)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(tx.amount, format: .currency(code: "CAD"))
                    .font(.caption)
                    .bold()
                    .foregroundStyle(tx.amount < 0 ? Color.primary : Color.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(5)
        }
    }
}

// MARK: - Budget progress bar (Safe / Warning / Over)
struct BudgetProgressView: View {
    var category: String
    var spent: Decimal
    var limit: Decimal

    private var progress: Double {
        guard limit > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent).doubleValue / NSDecimalNumber(decimal: limit).doubleValue
    }

    private var color: Color {
        if progress >= 1.0 { return .red }
        if progress >= 0.85 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category)
                    .font(.headline)
                Spacer()
                Text("\(spent, format: .currency(code: "CAD")) / \(limit, format: .currency(code: "CAD"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(progress, 1.0))
                .tint(color)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            if progress >= 1.0 {
                Text("Over budget by \(spent - limit, format: .currency(code: "CAD"))")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Insight card (Phase 8: Income / Expenses / Net Savings)
struct InsightCard: View {
    var title: String
    var amount: Decimal
    var color: Color
    var icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .padding(8)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())
                Spacer()
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(amount, format: .currency(code: "CAD"))
                .font(.title2)
                .bold()
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Trend card (Phase 14: spending vs 3‑month average)
struct TrendInsightCard: View {
    var trendPercent: Double
    private var color: Color { trendPercent > 0 ? .red : .green }
    private var icon: String { trendPercent > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis" }
    private var label: String {
        let sign = trendPercent >= 0 ? "+" : ""
        return "\(sign)\(Int(round(trendPercent)))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .padding(8)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())
                Spacer()
            }
            Text("Trend")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(label)
                .font(.title2)
                .bold()
                .foregroundStyle(color)
                .minimumScaleFactor(0.8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}
