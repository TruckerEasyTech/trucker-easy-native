//
//  CheckoutView.swift
//  Trucker Easy
//
//  Sales/Checkout Page - Inspired by Trucker Path
//  Driver to Driver tone
//

import SwiftUI
import StoreKit

struct CheckoutView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var storeManager = StoreManager()
    @State private var selectedPlan: SubscriptionPlan = .annual
    @State private var showingTerms = false
    
    enum SubscriptionPlan {
        case monthly
        case annual
        
        var price: String {
            switch self {
            case .monthly: return "$19.99"
            case .annual: return "$169.90"
            }
        }
        
        var period: String {
            switch self {
            case .monthly: return "per month"
            case .annual: return "per year"
            }
        }
        
        var savings: String? {
            switch self {
            case .monthly: return nil
            case .annual: return "Save $69.98 per year!"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Hero Section
                VStack(spacing: 16) {
                    // Logo/Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color("TruckerOrange"), Color("TruckerOrange").opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "truck.box.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 40)
                    
                    Text("Trucker Easy")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Driver to Driver")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .italic()
                    
                    Text("Created by a driver, for drivers.")
                        .font(.headline)
                        .foregroundColor(Color("TruckerOrange"))
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
                
                // Feature Screenshots
                VStack(spacing: 24) {
                    Text("Everything You Need on the Road")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    FeatureShowcase(
                        imageName: "map.fill",
                        title: "My Horizon",
                        description: "3D truck navigation with real-time community alerts. Paste your load address and go!",
                        accentColor: .blue
                    )
                    
                    FeatureShowcase(
                        imageName: "heart.fill",
                        title: "My Check-up",
                        description: "Track your wellness, medication reminders, and get healthy meal suggestions at rest stops.",
                        accentColor: .red
                    )
                    
                    FeatureShowcase(
                        imageName: "folder.fill",
                        title: "My Cabin",
                        description: "Never miss an expiration. Digital vault for all your CDL, DOT, and insurance documents.",
                        accentColor: .green
                    )
                    
                    FeatureShowcase(
                        imageName: "bubble.left.and.bubble.right.fill",
                        title: "Road Talk",
                        description: "Latest trucking news and Easy, your AI assistant for quick questions on the road.",
                        accentColor: Color("TruckerOrange")
                    )
                }
                .padding(.horizontal)
                
                // Pricing Cards
                VStack(spacing: 20) {
                    Text("Choose Your Plan")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Annual Plan (Recommended)
                    PricingCard(
                        plan: .annual,
                        isSelected: selectedPlan == .annual,
                        isRecommended: true
                    ) {
                        selectedPlan = .annual
                    }
                    
                    // Monthly Plan
                    PricingCard(
                        plan: .monthly,
                        isSelected: selectedPlan == .monthly,
                        isRecommended: false
                    ) {
                        selectedPlan = .monthly
                    }
                }
                .padding(.horizontal)
                
                // Trial Info
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "gift.fill")
                            .foregroundColor(Color("TruckerOrange"))
                        Text("Start Your 3-Day Free Trial")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    
                    Text("No commitment. Cancel anytime.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color("TruckerOrange").opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // CTA Button - High Contrast
                Button {
                    startTrial()
                } label: {
                    VStack(spacing: 8) {
                        Text("Start Free Trial")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("Then \(selectedPlan.price) \(selectedPlan.period)")
                            .font(.subheadline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(
                            colors: [Color("TruckerOrange"), Color("TruckerOrange").opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color("TruckerOrange").opacity(0.5), radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal)
                
                // Trust Badges
                VStack(spacing: 16) {
                    HStack(spacing: 24) {
                        TrustBadge(icon: "checkmark.shield.fill", text: "Secure & Private")
                        TrustBadge(icon: "truck.box.fill", text: "Driver Built")
                        TrustBadge(icon: "star.fill", text: "5-Star Rated")
                    }
                    
                    Text("Powered by Driver for Driver")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                // Fine Print
                VStack(spacing: 8) {
                    Button {
                        showingTerms = true
                    } label: {
                        Text("Terms of Service & Privacy Policy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .underline()
                    }
                    
                    Text("Your subscription automatically renews unless cancelled 24 hours before the end of the current period.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .sheet(isPresented: $showingTerms) {
            TermsView()
        }
    }
    
    private func startTrial() {
        appState.startTrial()
    }
}

// MARK: - Feature Showcase Card
struct FeatureShowcase: View {
    let imageName: String
    let title: String
    let description: String
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                
                Image(systemName: imageName)
                    .font(.system(size: 28))
                    .foregroundColor(accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Pricing Card
struct PricingCard: View {
    let plan: CheckoutView.SubscriptionPlan
    let isSelected: Bool
    let isRecommended: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 16) {
                // Recommended badge
                if isRecommended {
                    Text("BEST VALUE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color("TruckerOrange"))
                        .cornerRadius(20)
                }
                
                // Price
                VStack(spacing: 4) {
                    Text(plan.price)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(plan.period)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Savings badge
                if let savings = plan.savings {
                    Text(savings)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Features
                VStack(alignment: .leading, spacing: 8) {
                    FeatureRow(text: "Full 3D truck navigation")
                    FeatureRow(text: "Health & wellness tracking")
                    FeatureRow(text: "Document vault & reminders")
                    FeatureRow(text: "Community alerts & news")
                    FeatureRow(text: "AI assistant \"Easy\"")
                    FeatureRow(text: "Offline route caching")
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isSelected ? Color("TruckerOrange") : Color.clear,
                                lineWidth: 3
                            )
                    )
            )
            .shadow(
                color: isSelected ? Color("TruckerOrange").opacity(0.3) : .black.opacity(0.05),
                radius: isSelected ? 16 : 8,
                x: 0,
                y: isSelected ? 8 : 4
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

struct FeatureRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.subheadline)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Trust Badge
struct TrustBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Color("TruckerOrange"))
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Terms View
struct TermsView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Terms of Service")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("""
                    Welcome to Trucker Easy - Driver to Driver
                    
                    By using this app, you agree to:
                    
                    • Subscription automatically renews unless cancelled 24 hours before period ends
                    • Payment charged to Apple ID account at purchase confirmation
                    • Cancel anytime in App Store account settings
                    • 3-day free trial for new subscribers
                    • Privacy: We never sell your data
                    • All documents stored securely with end-to-end encryption
                    
                    This app is built by drivers, for drivers. Drive safe!
                    """)
                    .font(.body)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CheckoutView()
        .environmentObject(AppState())
        .environmentObject(SupabaseManager())
}
