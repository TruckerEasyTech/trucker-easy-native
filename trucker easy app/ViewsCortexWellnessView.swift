// ViewsCortexWellnessView.swift — Lotus.ai partner access (external; no API / no PHI in app)

import SafariServices
import SwiftUI
import UIKit

struct CortexWellnessView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var acceptedDisclaimer = false
    @State private var showingInAppBrowser = false

    private let partnerURL = LotusCortexService.partnerPortalURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    partnerHeader

                    disclaimerBlock

                    if !acceptedDisclaimer {
                        Button {
                            withAnimation { acceptedDisclaimer = true }
                        } label: {
                            Text("I understand — continue")
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.Colors.accent)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Button {
                                openURL(partnerURL)
                            } label: {
                                Label("Open Lotus.ai in Safari", systemImage: "safari")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AppTheme.Colors.accent)
                                    .foregroundColor(.black)
                                    .cornerRadius(12)
                            }

                            Button {
                                showingInAppBrowser = true
                            } label: {
                                Label("View in app browser", systemImage: "globe")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundColor(AppTheme.Colors.accent)
                            }

                            Text(partnerURL.absoluteString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }

                    premiumNote
                }
                .padding(20)
            }
            .background(AppTheme.Colors.background.ignoresSafeArea())
            .navigationTitle("Partner wellness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingInAppBrowser) {
            SafariView(url: partnerURL)
                .ignoresSafeArea()
        }
    }

    private var partnerHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(Color(hex: "#7c3aed"))
            VStack(alignment: .leading, spacing: 4) {
                Text("Lotus.ai — partner site")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text("Trucker Easy does not provide medical care. Account and services are offered by Lotus.ai under their terms.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
    }

    private var disclaimerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Important", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.Colors.warning)

            Text("""
            • Trucker Easy is a navigation and driver tools app — not a medical device.
            • Anything on Lotus.ai is provided by Lotus.ai, not by Trucker Easy.
            • We do not send your health data or login to Lotus from this app.
            • For emergencies call local emergency services. For medical advice see a licensed professional.
            • Use of Lotus.ai may require a separate account or payment with Lotus.ai.
            """)
            .font(.system(size: 13))
            .foregroundColor(AppTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundSecond)
        .cornerRadius(12)
    }

    private var premiumNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundColor(Color(hex: "#f59e0b"))
            Text("Included in TruckerEasy Pro as a partner access benefit. Lotus.ai sets its own pricing and availability.")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(10)
    }
}

// MARK: - In-app Safari (no cookies/tokens injected by Trucker Easy)

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(red: 0.79, green: 0.66, blue: 0.30, alpha: 1)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Checkup entry card (marketing / premium justification only)

struct LotusCortexCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#7c3aed").opacity(0.85), Color(hex: "#4f46e5").opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: "link")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Lotus.ai Partner")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("PRO")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#f59e0b"))
                            .cornerRadius(4)
                    }
                    Text("Link to partner wellness site — separate account with Lotus.ai")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(AppTheme.Colors.accent)
            }
            .padding(14)
            .background(AppTheme.Colors.backgroundSecond)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "#7c3aed").opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LotusCortexCard(onTap: {})
        .padding()
        .background(AppTheme.Colors.background)
        .preferredColorScheme(.dark)
}
