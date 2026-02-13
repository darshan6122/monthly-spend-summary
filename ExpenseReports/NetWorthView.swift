//
//  NetWorthView.swift
//  ExpenseReports
//
//  Net Worth Tracker: accounts (Bank, Investment, Debt) and total.
//

import SwiftUI
import SwiftData

struct NetWorthView: View {
    @Query(sort: \Account.name) private var accounts: [Account]
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddAccount = false

    private var netWorth: Decimal {
        accounts.reduce(Decimal(0)) { $0 + $1.balance }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Total Net Worth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(netWorth, format: .currency(code: "CAD"))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
            }
            .padding(.vertical, 30)

            List {
                ForEach(accounts) { account in
                    NetWorthAccountRow(account: account)
                }
                .onDelete { indexSet in
                    for index in indexSet { modelContext.delete(accounts[index]) }
                    try? modelContext.save()
                }
            }
        }
        .navigationTitle("Net Worth")
        .toolbar {
            Button("Add Account") { showingAddAccount = true }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountSheet()
        }
    }
}

// MARK: - Account row with inline balance edit
private struct NetWorthAccountRow: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.headline)
                Text("Last updated: \(account.lastUpdated.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Balance", value: $account.balance, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .multilineTextAlignment(.trailing)
                .onChange(of: account.balance) { _, _ in
                    account.lastUpdated = Date()
                    try? modelContext.save()
                }
        }
    }
}

// MARK: - Add Account Sheet
struct AddAccountSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var balanceString = ""
    @State private var accountType = "Bank"

    private static let accountTypes = ["Bank", "Investment", "Debt"]

    private var parsedBalance: Decimal? {
        let trimmed = balanceString.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Decimal(string: trimmed)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Account")
                .font(.headline)
                .padding(.top)
            Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 15) {
                GridRow {
                    Text("Name:")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    TextField("e.g. Chequing", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Type:")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $accountType) {
                        ForEach(Self.accountTypes, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Balance:")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $balanceString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }
            .padding()
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add Account") {
                    addAccount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 280)
    }

    private func addAccount() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let balance = parsedBalance ?? 0
        let account = Account(name: trimmedName, balance: balance, type: accountType)
        modelContext.insert(account)
        try? modelContext.save()
        dismiss()
    }
}
