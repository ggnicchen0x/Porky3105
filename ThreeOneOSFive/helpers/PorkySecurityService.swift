import Foundation
import UIKit
import CryptoKit
import Darwin
import MachO

final class PorkySecurityService {
    static let shared = PorkySecurityService()

    private let salt: [UInt8] = [
        0x50, 0x4F, 0x52, 0x4B, 0x59, 0x5F, 0x56, 0x49, 0x50, 0x33, 0x31, 0x30, 0x35
    ]

    private init() {}

    // MARK: - String Obfuscation Decoder
    func deobfuscate(_ bytes: [UInt8]) -> String {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        for (i, b) in bytes.enumerated() {
            out.append(b ^ salt[i % salt.count])
        }
        return String(bytes: out, encoding: .utf8) ?? ""
    }

    // MARK: - Anti-Debugging Check (sysctl P_TRACED)
    func isDebuggerAttached() -> Bool {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&name, UInt32(name.count), &info, &size, nil, 0)
        if result == 0 {
            return (info.kp_proc.p_flag & P_TRACED) != 0
        }
        return false
    }

    // MARK: - Deny Debugger Attachment (ptrace PT_DENY_ATTACH)
    func denyDebugger() {
        typealias PtraceType = @convention(c) (CInt, pid_t, CInt, CInt) -> CInt
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let ptraceSymbol = dlsym(defaultHandle, "ptrace") else { return }
        let ptraceFunc = unsafeBitCast(ptraceSymbol, to: PtraceType.self)
        _ = ptraceFunc(31, 0, 0, 0) // 31 = PT_DENY_ATTACH
    }

    // MARK: - Dynamic Injection & Tamper Detection
    func isEnvironmentTampered() -> Bool {
        // 1. Check DYLD_INSERT_LIBRARIES
        if let env = getenv("DYLD_INSERT_LIBRARIES"), String(cString: env).count > 0 {
            return true
        }

        // 2. Scan loaded dynamic images
        let suspiciousTokens = [
            "frida", "cydiasubstrate", "substitute", "sslkillswitch",
            "cycript", "shadow.dylib", "tweakinject"
        ]

        let count = _dyld_image_count()
        for i in 0..<count {
            if let rawName = _dyld_get_image_name(i) {
                let name = String(cString: rawName).lowercased()
                for token in suspiciousTokens {
                    if name.contains(token) {
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: - Comprehensive Security Gate
    func verifyExecutionIntegrity() -> Bool {
        denyDebugger()

        if isDebuggerAttached() {
            return false
        }

        if isEnvironmentTampered() {
            return false
        }

        return true
    }

    // MARK: - Device-Bound Cryptographic Signature for Session State
    private func deviceSecretKey() -> SymmetricKey {
        let vendor = UIDevice.current.identifierForVendor?.uuidString ?? "porky.default.device.node"
        let rawKeyData = (vendor + "-PORKY-VIP-INTEGRITY-2026").data(using: .utf8)!
        let hashed = SHA256.hash(data: rawKeyData)
        return SymmetricKey(data: hashed)
    }

    func computeSessionSignature(key: String, status: String, expiry: String) -> String {
        let payload = "\(key):\(status):\(expiry)"
        let keySymmetric = deviceSecretKey()
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8),
            using: keySymmetric
        )
        return Data(signature).base64EncodedString()
    }

    func verifySessionSignature(key: String, status: String, expiry: String, signature: String) -> Bool {
        guard !signature.isEmpty else { return false }
        let expected = computeSessionSignature(key: key, status: status, expiry: expiry)
        return expected == signature
    }
}
