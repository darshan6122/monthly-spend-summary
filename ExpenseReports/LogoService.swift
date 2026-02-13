//
//  LogoService.swift
//  ExpenseReports
//
//  Fetches merchant logos: Clearbit first, Google Favicon as fallback.
//

import Foundation

enum LogoService {
    /// Guess domain from merchant name and fetch logo image data. Tries Clearbit, then Google Favicon.
    static func fetchLogo(for merchantName: String) async -> Data? {
        // 1. Clean the name aggressively
        // "Netflix.com *Msg" -> "netflix", strip "payment"/"bill"
        let cleaned = merchantName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
            .lowercased()
            .replacingOccurrences(of: "payment", with: "")
            .replacingOccurrences(of: "bill", with: "")
        guard !cleaned.isEmpty else { return nil }

        // 2. Guess the domain (overrides use "contains" so "amznmktp" -> amazon.ca)
        let overrides: [String: String] = [
            "amzn": "amazon.ca",
            "amazon": "amazon.ca",
            "uber": "uber.com",
            "timhortons": "timhortons.ca",
            "netflix": "netflix.com",
            "apple": "apple.com",
            "cibc": "cibc.com",
            "starbucks": "starbucks.com",
            "costco": "costco.ca",
            "lcbo": "lcbo.com",
        ]

        var domain = cleaned + ".com"
        for (key, val) in overrides {
            if cleaned.contains(key) {
                domain = val
                break
            }
        }

        print("🔍 Looking for logo: \(merchantName) -> Domain: \(domain)")

        // 3. Try Clearbit API (best quality)
        if let data = await download(from: "https://logo.clearbit.com/\(domain)") {
            print("✅ Found Clearbit logo for \(domain)")
            return data
        }

        // 4. Fallback: Google Favicon API (best reliability)
        if let data = await download(from: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128") {
            print("✅ Found Google logo for \(domain)")
            return data
        }

        print("❌ No logo found for \(domain)")
        return nil
    }

    private static func download(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                // Filter out tiny 1x1 tracking pixels or empty files
                if data.count > 100 {
                    return data
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
