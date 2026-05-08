//
//  TruckerEasyAppFixed.swift
//  Trucker Easy
//
//  APP PRINCIPAL - 100% NATIVO iOS FUNCIONANDO!
//  SEM REDIRECIONAMENTOS WEB!
//

import SwiftUI

@main
struct TruckerEasyApp: App {
    @StateObject private var appState = AppStateWorking()
    
    var body: some Scene {
        WindowGroup {
            if appState.isSubscribed || appState.isInTrial {
                MainTabViewFixed()
                    .environmentObject(appState)
            } else {
                CheckoutViewFixed()
                    .environmentObject(appState)
            }
        }
    }
}

// AppState FUNCIONANDO
@MainActor
class AppStateWorking: ObservableObject {
    @Published var isSubscribed: Bool = false
    @Published var isInTrial: Bool = false
    @Published var trialStartDate: Date?
    @Published var subscriptionType: SubscriptionType?
    @Published var selectedLanguage: String = "en"
    @Published var userProfile: UserProfile?
    
    private let trialDuration: TimeInterval = 3 * 24 * 60 * 60 // 3 dias
    
    enum SubscriptionType: String, Codable {
        case monthly = "monthly"
        case annual = "annual"
    }
    
    init() {
        loadSubscriptionStatus()
        checkTrialStatus()
        
        print("🚀 App iniciado!")
        print("📱 Trial ativo: \(isInTrial)")
        print("💳 Subscrito: \(isSubscribed)")
    }
    
    func startTrial() {
        print("🎉 Iniciando trial gratuito de 3 dias!")
        
        trialStartDate = Date()
        isInTrial = true
        UserDefaults.standard.set(trialStartDate, forKey: "trialStartDate")
        
        // Haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func checkTrialStatus() {
        guard let startDate = UserDefaults.standard.object(forKey: "trialStartDate") as? Date else {
            isInTrial = false
            return
        }
        
        let elapsed = Date().timeIntervalSince(startDate)
        isInTrial = elapsed < trialDuration && !isSubscribed
        
        if !isInTrial && trialStartDate != nil {
            print("⏰ Trial expirou!")
            trialStartDate = nil
            UserDefaults.standard.removeObject(forKey: "trialStartDate")
        }
    }
    
    func subscribe(type: SubscriptionType) {
        print("💳 Assinatura ativada: \(type.rawValue)")
        
        subscriptionType = type
        isSubscribed = true
        isInTrial = false
        
        UserDefaults.standard.set(type.rawValue, forKey: "subscriptionType")
        UserDefaults.standard.set(true, forKey: "isSubscribed")
        
        // Haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func loadSubscriptionStatus() {
        isSubscribed = UserDefaults.standard.bool(forKey: "isSubscribed")
        if let typeString = UserDefaults.standard.string(forKey: "subscriptionType") {
            subscriptionType = SubscriptionType(rawValue: typeString)
        }
    }
}

// MainTabView FUNCIONANDO
struct MainTabViewFixed: View {
    @EnvironmentObject var appState: AppStateWorking
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: My Horizon (Mapa)
            MyHorizonViewFixed()
                .tabItem {
                    Label("My Horizon", systemImage: "map.fill")
                }
                .tag(0)
            
            // Tab 2: My Check-up (Saúde)
            MyCheckupViewFixed()
                .tabItem {
                    Label("My Check-up", systemImage: "heart.fill")
                }
                .tag(1)
            
            // Tab 3: My Cabin (Documentos)
            MyCabinViewFixed()
                .tabItem {
                    Label("My Cabin", systemImage: "folder.fill")
                }
                .tag(2)
            
            // Tab 4: Road Talk (Chat + Notícias)
            RoadTalkViewFixed()
                .tabItem {
                    Label("Road Talk", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(3)
        }
        .tint(.orange)
        .onAppear {
            print("✅ Tabs carregadas!")
        }
    }
}

// Checkout FUNCIONANDO
struct CheckoutViewFixed: View {
    @EnvironmentObject var appState: AppStateWorking
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
                // Logo
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .orange.opacity(0.7)],
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
                    
                    Text("Driver to Driver")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .italic()
                    
                    Text("Built by a driver, for drivers.")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
                
                // Features
                VStack(spacing: 20) {
                    FeatureRow(icon: "map.fill", title: "3D Navigation", color: .blue)
                    FeatureRow(icon: "heart.fill", title: "Health Tracking", color: .red)
                    FeatureRow(icon: "folder.fill", title: "Document Vault", color: .green)
                    FeatureRow(icon: "bubble.left.fill", title: "AI Chat Assistant", color: .orange)
                }
                .padding(.horizontal)
                
                // Planos
                VStack(spacing: 20) {
                    PricingCardFixed(
                        plan: .annual,
                        isSelected: selectedPlan == .annual,
                        isRecommended: true
                    ) {
                        selectedPlan = .annual
                    }
                    
                    PricingCardFixed(
                        plan: .monthly,
                        isSelected: selectedPlan == .monthly,
                        isRecommended: false
                    ) {
                        selectedPlan = .monthly
                    }
                }
                .padding(.horizontal)
                
                // Trial info
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.orange)
                        Text("3-Day Free Trial")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    Text("No commitment. Cancel anytime.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // CTA BUTTON
                Button {
                    appState.startTrial()
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
                            colors: [.orange, .orange.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .orange.opacity(0.5), radius: 12, y: 6)
                }
                .padding(.horizontal)
                
                // Trust badges
                HStack(spacing: 24) {
                    TrustBadge(icon: "checkmark.shield.fill", text: "Secure")
                    TrustBadge(icon: "truck.box.fill", text: "Driver Built")
                    TrustBadge(icon: "star.fill", text: "5-Star")
                }
                .padding()
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.headline)
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
}

struct PricingCardFixed: View {
    let plan: CheckoutViewFixed.SubscriptionPlan
    let isSelected: Bool
    let isRecommended: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 16) {
                if isRecommended {
                    Text("BEST VALUE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(20)
                }
                
                VStack(spacing: 4) {
                    Text(plan.price)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(plan.period)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
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
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 3)
            )
            .shadow(
                color: isSelected ? Color.orange.opacity(0.3) : .black.opacity(0.05),
                radius: isSelected ? 16 : 8,
                y: isSelected ? 8 : 4
            )
        }
    }
}

struct TrustBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    TruckerEasyApp()
}
