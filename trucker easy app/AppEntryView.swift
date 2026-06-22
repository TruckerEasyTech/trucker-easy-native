import SwiftUI
import SwiftData

struct AppEntryView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false
    @AppStorage("appearanceMode") private var appearanceMode = 0  // 0=Auto, 1=Light, 2=Dark
    @AppStorage("lastMorningCheckIn") private var lastMorningCheckIn: String = ""
    @State private var showSplash: Bool = true
    @State private var showMorningCheckIn: Bool = false
    @State private var regionalSettings = RegionalSettingsManager()

    private var appColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        default: return .dark
        }
    }

    private var needsMorningCheckIn: Bool {
        guard !AppAccessPolicy.skipLaunchWellnessCheck else { return false }
        #if DEBUG
        // Build de teste (Xcode): pergunta de bem-estar em TODA abertura, pra QA sempre ver.
        // Na loja/TestFlight (Release) continua 1x por dia — "Skip" também marca o dia.
        return true
        #else
        let todayStr = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        return lastMorningCheckIn != todayStr
        #endif
    }

    /// After splash, onboarding can still flip `hasSeenWelcome` — `onChange(showSplash)` alone misses that path.
    private func presentMorningCheckInIfNeeded() {
        guard hasSeenWelcome, !showSplash, needsMorningCheckIn, !showMorningCheckIn else { return }
        showMorningCheckIn = true
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
            } else if showMorningCheckIn {
                LaunchWellnessCheckIn(
                    lang: regionalSettings.currentLanguage,
                    onComplete: {
                        let todayStr = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
                        lastMorningCheckIn = todayStr
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showMorningCheckIn = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                MainTabView()
                    .transition(.opacity)
                    .onOpenURL { url in
                        guard AppAccessPolicy.driverDispatchEnabled else { return }
                        if let load = DispatchService.shared.handleDeepLink(url) {
                            DispatchService.shared.handleIncomingLoad(load)
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showSplash)
        .animation(.easeInOut(duration: 0.35), value: hasSeenWelcome)
        .animation(.easeInOut(duration: 0.35), value: showMorningCheckIn)
        .preferredColorScheme(appColorScheme)
        .onChange(of: showSplash) { _, newVal in
            if !newVal { presentMorningCheckInIfNeeded() }
        }
        .onChange(of: hasSeenWelcome) { _, newVal in
            if newVal { presentMorningCheckInIfNeeded() }
        }
        // NÃO tocar o tile store do Mapbox aqui: o 1º acesso a OfflineRouteTileManager.shared cria
        // TileStore.default (I/O síncrono num store grande) na MAIN THREAD durante o splash → congela
        // a tela preta com o spinner (o asyncAfter que dispensa o splash não chega a disparar). A poda
        // já roda, em segurança, no HorizonView.onAppear (depois do mapa montar, idle).
    }
}

#Preview {
    AppEntryView()
        .modelContainer(for: [Trip.self, FuelPurchase.self, TruckDocument.self,
                               CommunityPost.self, PostComment.self, WellnessLog.self,
                               Medication.self], inMemory: true)
}
