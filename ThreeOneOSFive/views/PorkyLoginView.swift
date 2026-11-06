import SwiftUI
import UIKit

struct PorkyLoginView: View {
    @ObservedObject var authManager = PorkyAuthManager.shared
    @State private var inputKey: String = ""
    @State private var isFieldFocused: Bool = false
    @State private var shakeOffset: CGFloat = 0
    @State private var glowPulse: Bool = false

    private let cyberGreen = Color(red: 0.35, green: 0.85, blue: 0.25)
    private let darkGreen = Color(red: 0.12, green: 0.55, blue: 0.20)

    var body: some View {
        ZStack {
            // Cyber background
            Color(red: 0.04, green: 0.06, blue: 0.05)
                .ignoresSafeArea()

            // Glowing ambient circles
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(cyberGreen.opacity(0.12))
                        .frame(width: proxy.size.width * 0.9)
                        .blur(radius: 80)
                        .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.2)

                    Circle()
                        .fill(darkGreen.opacity(0.08))
                        .frame(width: proxy.size.width * 0.8)
                        .blur(radius: 70)
                        .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.8)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    // Cyber Core Logo Header
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(cyberGreen.opacity(0.15))
                                .frame(width: 90, height: 90)
                                .blur(radius: glowPulse ? 14 : 6)
                                .scaleEffect(glowPulse ? 1.08 : 0.96)

                            Circle()
                                .stroke(cyberGreen.opacity(0.6), lineWidth: 1.5)
                                .frame(width: 82, height: 82)

                            AppLogo(size: 64)
                        }
                        .onAppear {
                            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                glowPulse = true
                            }
                        }

                        VStack(spacing: 5) {
                            Text("PORKY VIP CONTROL")
                                .font(.system(size: 24, weight: .black, design: .monospaced))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, cyberGreen],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .tracking(1.5)

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(cyberGreen)
                                    .frame(width: 6, height: 6)
                                    .blur(radius: 1)

                                Text("CYBER CORE AUTHENTICATION")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(cyberGreen)
                                    .tracking(2.0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(cyberGreen.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    // Key Input Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("VIP LICENSE KEY")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(cyberGreen.opacity(0.85))
                            .tracking(1.0)

                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(cyberGreen)

                            TextField("PORKY-XXXX-XXXX", text: $inputKey)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .submitLabel(.done)
                                .onChange(of: inputKey) { newValue in
                                    inputKey = newValue.uppercased()
                                }

                            if !inputKey.isEmpty {
                                Button {
                                    inputKey = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                pasteFromClipboard()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("PASTE")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(cyberGreen.opacity(0.18))
                                .foregroundStyle(cyberGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    authManager.errorMessage != nil ? Color.red.opacity(0.8) : cyberGreen.opacity(0.5),
                                    lineWidth: 1.2
                                )
                        )

                        // Error message
                        if let error = authManager.errorMessage {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.red)
                                Text(error)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.red.opacity(0.95))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Activate Button
                        Button {
                            triggerActivation()
                        } label: {
                            HStack(spacing: 8) {
                                if authManager.isVerifying {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .scaleEffect(0.9)
                                    Text("VERIFYING KEY...")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.black)
                                } else {
                                    Image(systemName: "lock.open.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("ACTIVATE VIP ACCESS")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .tracking(1.0)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                LinearGradient(
                                    colors: [cyberGreen, darkGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: cyberGreen.opacity(0.45), radius: 10, y: 3)
                        }
                        .disabled(authManager.isVerifying || inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(inputKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1.0)
                    }
                    .padding(20)
                    .background(Color(red: 0.08, green: 0.11, blue: 0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(cyberGreen.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .offset(x: shakeOffset)

                    // Features & Portal Link
                    VStack(spacing: 16) {
                        HStack(spacing: 18) {
                            featurePill(icon: "bolt.shield.fill", title: "Kernel Patches")
                            featurePill(icon: "sparkles", title: "Tweaks & Lab")
                            featurePill(icon: "shippingbox.fill", title: "Sideloading")
                        }

                        if let portalURL = URL(string: "https://porkyy.joserpb70.workers.dev/") {
                            Link(destination: portalURL) {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 12))
                                    Text("Need a key? Visit PORKY VIP Portal")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(cyberGreen)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(cyberGreen.opacity(0.08))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.top, 10)

                    Spacer(minLength: 30)
                }
            }
        }
    }

    private func featurePill(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(cyberGreen)
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func pasteFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            let trimmed = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            self.inputKey = trimmed
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func triggerActivation() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let success = await authManager.activate(rawKey: inputKey)
            if success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation(.default) {
                    shake()
                }
            }
        }
    }

    private func shake() {
        for index in 0...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                    shakeOffset = (index % 2 == 0) ? -10 : 10
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                shakeOffset = 0
            }
        }
    }
}

