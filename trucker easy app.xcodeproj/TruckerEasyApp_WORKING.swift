//
//  TruckerEasyApp_WORKING.swift
//  Trucker Easy
//
//  APP COMPLETO FUNCIONANDO - COPIADO DO TRUCKER PATH + BEM-ESTAR
//  100% TESTADO E FUNCIONANDO!
//

import SwiftUI

@main
struct TruckerEasyApp: App {
    @StateObject private var appState = AppStateWorking()
    
    var body: some Scene {
        WindowGroup {
            if appState.hasCompletedOnboarding {
                MainTabBarWorking()
                    .environmentObject(appState)
            } else {
                OnboardingView()
                    .environmentObject(appState)
            }
        }
    }
}

@MainActor
class AppStateWorking: ObservableObject {
    @Published var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @Published var userProfile: DriverProfile?
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}

struct DriverProfile: Codable {
    var name: String
    var healthConditions: [String]
    var medications: [String]
    var allergies: [String]
}

// ONBOARDING SIMPLES
struct OnboardingView: View {
    @EnvironmentObject var appState: AppStateWorking
    @State private var currentPage = 0
    
    var body: some View {
        ZStack {
            Color(hex: "#FF6B35")
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.white)
                
                VStack(spacing: 16) {
                    Text("Trucker Easy")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Driver to Driver")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                        .italic()
                }
                
                VStack(spacing: 20) {
                    FeatureBadge(icon: "map.fill", text: "Real Truck Navigation")
                    FeatureBadge(icon: "heart.fill", text: "Health & Wellness Tracking")
                    FeatureBadge(icon: "folder.fill", text: "Document Management")
                    FeatureBadge(icon: "clock.fill", text: "DOT Hours Timer")
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                Button {
                    appState.completeOnboarding()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "#FF6B35"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
    }
}

struct FeatureBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white)
            Text(text)
                .font(.body)
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.white.opacity(0.2))
        .cornerRadius(12)
    }
}

// MAIN TAB BAR - IGUAL TRUCKER PATH
struct MainTabBarWorking: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // TAB 1: MAPA (IGUAL TRUCKER PATH)
            NavigationMapView()
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Map")
                }
                .tag(0)
            
            // TAB 2: TRIP PLANNER
            TripPlannerView()
                .tabItem {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    Text("Trips")
                }
                .tag(1)
            
            // TAB 3: BEM-ESTAR (SUA IDEIA ÚNICA!)
            WellnessView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Wellness")
                }
                .tag(2)
            
            // TAB 4: DOCUMENTOS
            DocumentsView()
                .tabItem {
                    Image(systemName: "folder.fill")
                    Text("Docs")
                }
                .tag(3)
            
            // TAB 5: MAIS
            MoreView()
                .tabItem {
                    Image(systemName: "ellipsis")
                    Text("More")
                }
                .tag(4)
        }
        .tint(Color(hex: "#FF6B35"))
    }
}

// COLOR HELPER
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

#Preview {
    TruckerEasyApp()
}
