//
//  MerchantLogoView.swift
//  ExpenseReports
//
//  Shows cached merchant logo or fetches via Clearbit in background; fallback to initial.
//

import SwiftUI
import SwiftData
import AppKit

struct MerchantLogoView: View {
    @Bindable var transaction: Transaction
    @Environment(\.modelContext) private var modelContext

    private var displayName: String {
        transaction.cleanDescription.isEmpty ? transaction.originalDescription : transaction.cleanDescription
    }

    var body: some View {
        Group {
            if let data = transaction.logoData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
                    .background(Color.white)
            } else {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.caption)
                    .bold()
                    .foregroundStyle(.white)
                    .task {
                        guard transaction.logoData == nil else { return }
                        if let newData = await LogoService.fetchLogo(for: displayName) {
                            await MainActor.run {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    transaction.logoData = newData
                                }
                                try? modelContext.save()
                            }
                        }
                    }
            }
        }
        .frame(width: 32, height: 32)
        .background(Color.gray.opacity(0.3))
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.gray.opacity(0.1), lineWidth: 1))
        .contextMenu {
            Button {
                transaction.logoData = nil
                Task {
                    if let newData = await LogoService.fetchLogo(for: displayName) {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                transaction.logoData = newData
                            }
                            try? modelContext.save()
                        }
                    }
                }
            } label: {
                Label("Retry Logo Fetch", systemImage: "arrow.clockwise")
            }
        }
    }
}
