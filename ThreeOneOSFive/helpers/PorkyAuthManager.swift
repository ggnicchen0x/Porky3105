import Foundation
import SwiftUI
import Combine

@MainActor
final class PorkyAuthManager: ObservableObject {
    static let shared = PorkyAuthManager()

    // Obfuscated tokens - no plaintext in Mach-O __cstring
    private static let kEP: [UInt8] = [56, 59, 38, 59, 42, 101, 121, 102, 32, 92, 67, 91, 76, 41, 97, 56, 36, 42, 58, 36, 57, 50, 4, 1, 30, 66, 63, 61, 57, 46, 43, 44, 120, 45, 53, 69, 30, 70, 84, 60, 38, 54, 42, 45, 58]
    private static let kActive: [UInt8] = [17, 12, 6, 2, 15, 26]
    private static let kKeyParam: [UInt8] = [59, 42, 43]
    private static let kStatusKey: [UInt8] = [32, 32, 32, 32, 32, 113, 32, 32, 32, 29, 66, 68, 84, 36, 58, 33]
    private static let kStorageKey: [UInt8] = [32, 32, 32, 32, 32, 113, 32, 32, 32, 29, 93, 89, 86, 53, 33, 33, 46, 18, 58, 47]
    private static let kSigKey: [UInt8] = [32, 32, 32, 32, 32, 113, 32, 32, 32, 29, 66, 89, 82]
    private static let kExpiryKey: [UInt8] = [32, 32, 32, 32, 32, 113, 32, 32, 32, 29, 84, 72, 69, 57, 61, 43]
    private static let kTierKey: [UInt8] = [32, 32, 32, 32, 32, 113, 32, 32, 32, 29, 69, 89, 80, 34]

    private var storageKey: String { PorkySecurityService.shared.deobfuscate(Self.kStorageKey) }
    private var statusKey: String { PorkySecurityService.shared.deobfuscate(Self.kStatusKey) }
    private var sigKey: String { PorkySecurityService.shared.deobfuscate(Self.kSigKey) }
    private var expiryKey: String { PorkySecurityService.shared.deobfuscate(Self.kExpiryKey) }
    private var tierKey: String { PorkySecurityService.shared.deobfuscate(Self.kTierKey) }
    private var activeStatus: String { PorkySecurityService.shared.deobfuscate(Self.kActive) }
    private var keyParamName: String { PorkySecurityService.shared.deobfuscate(Self.kKeyParam) }
    private var endpointURL: URL {
        URL(string: PorkySecurityService.shared.deobfuscate(Self.kEP))!
    }

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
        guard PorkySecurityService.shared.verifyExecutionIntegrity() else {
            self.isAuthenticated = false
            self.errorMessage = "Security integrity violation detected."
            return
        }

        let defaults = UserDefaults.standard
        let savedKey = defaults.string(forKey: storageKey) ?? ""
        let savedStatus = defaults.string(forKey: statusKey) ?? ""
        let savedExpiry = defaults.string(forKey: expiryKey) ?? ""
        let savedTier = defaults.string(forKey: tierKey) ?? "VIP"
        let savedSig = defaults.string(forKey: sigKey) ?? ""

        guard !savedKey.isEmpty, savedStatus == activeStatus else {
            self.isAuthenticated = false
            self.currentKey = ""
            return
        }

        // Cryptographic signature check: prevents modifying UserDefaults plist
        guard PorkySecurityService.shared.verifySessionSignature(
            key: savedKey,
            status: savedStatus,
            expiry: savedExpiry,
            signature: savedSig
        ) else {
            self.deactivate()
            self.errorMessage = "Session signature verification failed."
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
        guard PorkySecurityService.shared.verifyExecutionIntegrity() else {
            self.errorMessage = "Security integrity check failed."
            return false
        }

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
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("PorkyVIP/2.0", forHTTPHeaderField: "User-Agent")

            let payload: [String: Any] = [keyParamName: key]
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

                // Compute cryptographic signature bound to this device
                let sig = PorkySecurityService.shared.computeSessionSignature(
                    key: key,
                    status: activeStatus,
                    expiry: expiry
                )

                // Persist credentials securely
                let defaults = UserDefaults.standard
                defaults.set(key, forKey: storageKey)
                defaults.set(activeStatus, forKey: statusKey)
                defaults.set(sig, forKey: sigKey)
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
        guard PorkySecurityService.shared.verifyExecutionIntegrity() else {
            self.deactivate()
            return
        }
        do {
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let payload: [String: Any] = [keyParamName: currentKey]
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
                let newSig = PorkySecurityService.shared.computeSessionSignature(
                    key: currentKey,
                    status: activeStatus,
                    expiry: newExpiry
                )
                let defaults = UserDefaults.standard
                defaults.set(newExpiry, forKey: expiryKey)
                defaults.set(newSig, forKey: sigKey)
            }
        } catch {
            // Keep offline session
        }
    }

    func deactivate() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: statusKey)
        defaults.removeObject(forKey: sigKey)
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

