import Foundation
import SwiftUI
import Combine

@MainActor
final class PorkyAuthManager: ObservableObject {
    static let shared = PorkyAuthManager()

    private let storageKey = "porky.vip.licenseKey"
    private let statusKey = "porky.vip.status"
    private let expiryKey = "porky.vip.expiry"
    private let tierKey = "porky.vip.tier"

    private let endpoint = URL(string: "https://porkyy.joserpb70.workers.dev/validate")!

    @Published var isAuthenticated: Bool = false
    @Published var currentKey: String = ""
    @Published var expiryDate: String = ""
    @Published var tier: String = "VIP"
    @Published var isVerifying: Bool = false
    @Published var errorMessage: String? = nil

    init() {
        loadPersistedState()
    }

    private func loadPersistedState() {
        let defaults = UserDefaults.standard
        let savedKey = defaults.string(forKey: storageKey) ?? ""
        let savedStatus = defaults.string(forKey: statusKey) ?? ""
        let savedExpiry = defaults.string(forKey: expiryKey) ?? ""
        let savedTier = defaults.string(forKey: tierKey) ?? "VIP"

        guard !savedKey.isEmpty, savedStatus == "ACTIVE" else {
            self.isAuthenticated = false
            self.currentKey = ""
            return
        }

        // Check local expiry if present
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsed = formatter.date(from: savedExpiry)
        if parsed == nil {
            formatter.formatOptions = [.withInternetDateTime]
            parsed = formatter.date(from: savedExpiry)
        }

        if let date = parsed, date < Date() {
            self.isAuthenticated = false
            self.currentKey = savedKey
            self.expiryDate = savedExpiry
            self.errorMessage = "Your VIP license has expired."
        } else {
            self.isAuthenticated = true
            self.currentKey = savedKey
            self.expiryDate = savedExpiry
            self.tier = savedTier

            // Silent background verification
            Task {
                await self.silentRevalidate()
            }
        }
    }

    func activate(rawKey: String) async -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else {
            self.errorMessage = "Please enter your VIP license key."
            return false
        }

        self.isVerifying = true
        self.errorMessage = nil

        defer {
            self.isVerifying = false
        }

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("PorkyVIP/2.0", forHTTPHeaderField: "User-Agent")

            let payload: [String: Any] = ["key": key]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                self.errorMessage = "Connection error. Please check your internet."
                return false
            }

            guard (200...299).contains(http.statusCode) else {
                self.errorMessage = "Authentication server error (\(http.statusCode))."
                return false
            }

            let result = try JSONDecoder().decode(PorkyValidationResponse.self, from: data)

            if result.isValid {
                let expiry = result.data?.attributes?.expiry ?? ""
                let tier = result.data?.attributes?.metadata?.tier ?? "VIP"

                self.currentKey = key
                self.expiryDate = expiry
                self.tier = tier
                self.isAuthenticated = true
                self.errorMessage = nil

                // Persist credentials
                let defaults = UserDefaults.standard
                defaults.set(key, forKey: storageKey)
                defaults.set("ACTIVE", forKey: statusKey)
                defaults.set(expiry, forKey: expiryKey)
                defaults.set(tier, forKey: tierKey)
                return true
            } else {
                let msg = result.errors?.first?.detail ?? "Invalid or expired license key."
                self.errorMessage = msg
                self.isAuthenticated = false
                return false
            }
        } catch {
            self.errorMessage = "Network error: \(error.localizedDescription)"
            return false
        }
    }

    private func silentRevalidate() async {
        guard !currentKey.isEmpty else { return }
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let payload: [String: Any] = ["key": currentKey]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }

            let result = try JSONDecoder().decode(PorkyValidationResponse.self, from: data)
            if !result.isValid {
                self.deactivate()
                self.errorMessage = "VIP license was revoked or has expired."
            } else if let newExpiry = result.data?.attributes?.expiry {
                self.expiryDate = newExpiry
                UserDefaults.standard.set(newExpiry, forKey: expiryKey)
            }
        } catch {
            // Keep offline session
        }
    }

    func deactivate() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: statusKey)
        defaults.removeObject(forKey: expiryKey)
        defaults.removeObject(forKey: tierKey)

        self.currentKey = ""
        self.expiryDate = ""
        self.isAuthenticated = false
        self.errorMessage = nil
    }

    var maskedKey: String {
        guard currentKey.count > 8 else { return currentKey }
        let prefix = currentKey.prefix(6)
        let suffix = currentKey.suffix(4)
        return "\(prefix)••••\(suffix)"
    }

    var formattedExpiry: String {
        guard !expiryDate.isEmpty else { return "Permanent / Unlimited" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsed = formatter.date(from: expiryDate)
        if parsed == nil {
            formatter.formatOptions = [.withInternetDateTime]
            parsed = formatter.date(from: expiryDate)
        }
        guard let date = parsed else { return expiryDate }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}

struct PorkyValidationResponse: Decodable {
    let success: Bool?
    let valid: Bool?
    let status: String?
    let data: PorkyLicenseData?
    let errors: [PorkyErrorDetail]?

    var isValid: Bool {
        if let v = valid, v { return true }
        if let s = success, s { return true }
        if status?.uppercased() == "ACTIVE" { return true }
        return false
    }
}

struct PorkyLicenseData: Decodable {
    let id: String?
    let attributes: PorkyLicenseAttributes?
}

struct PorkyLicenseAttributes: Decodable {
    let status: String?
    let key: String?
    let valid: Bool?
    let expiry: String?
    let suspended: Bool?
    let metadata: PorkyLicenseMetadata?
}

struct PorkyLicenseMetadata: Decodable {
    let tier: String?
    let mode: String?
}

struct PorkyErrorDetail: Decodable {
    let title: String?
    let detail: String?
}

