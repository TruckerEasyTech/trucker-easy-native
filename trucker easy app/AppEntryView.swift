import SwiftUI
import SwiftData

struct AppEntryView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false
    @AppStorage("appearanceMode") private var appearanceMode = 0  // 0=Auto, 1=Light, 2=Dark
    @State private var showSplash: Bool = true

    private var appColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        default: return .dark   // Auto (0) and Dark (2) both force dark mode
        }
    }

    var body: some View {
        ZStack {
            if showSplash {
                SplashScreenView(isShowing: $showSplash)
                    .transition(.opacity)
            } else if !hasSeenWelcome {
                WelcomeOnboardingView(onGetStarted: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        hasSeenWelcome = true
                    }
                })
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showSplash)
        .animation(.easeInOut(duration: 0.35), value: hasSeenWelcome)
        .preferredColorScheme(appColorScheme)
    }
}

#Preview {
    AppEntryView()
        .modelContainer(for: [Trip.self, FuelPurchase.self, TruckDocument.self,
                               CommunityPost.self, PostComment.self, WellnessLog.self,
                               Medication.self], inMemory: true)
}
