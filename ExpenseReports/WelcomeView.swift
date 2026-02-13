//
//  WelcomeView.swift
//  ExpenseReports
//
//  First-launch onboarding overlay: welcome message and quick setup guide.
//

import SwiftUI

struct OnboardingRow: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// First-launch welcome sheet: set "hasLaunchedBefore" and dismiss on Get Started.
struct OnboardingWelcomeView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 10) {
                Text("Welcome to Finance OS")
                    .font(.largeTitle.bold())
                Text("Your entire financial life, organized and private.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                OnboardingRow(icon: "arrow.down.doc", title: "Import CIBC Files", desc: "Drag and drop your bank CSVs to get started.")
                OnboardingRow(icon: "bolt.fill", title: "Auto-Categorize", desc: "Rules automatically clean up your messy merchant names.")
                OnboardingRow(icon: "lock.shield", title: "100% Private", desc: "Your data stays on your Mac. No clouds, no tracking.")
            }
            .padding()

            Button("Get Started") {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(width: 500, height: 600)
        .padding()
    }
}
