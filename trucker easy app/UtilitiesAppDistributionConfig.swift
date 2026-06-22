// UtilitiesAppDistributionConfig.swift — App Store / TestFlight URLs from xcconfig → Info.plist.

import Foundation

enum AppAccessPolicy {
    // ═══════════════════════════════════════════════════════════════════════════════════
    //  🚦  INTERRUPTOR ÚNICO DO PAYWALL — mude SÓ esta linha  🚦
    //
    //  • true  → build de TESTE (TestFlight/QA): libera TODAS as features sem pagar.
    //  • false → build de LANÇAMENTO (App Store): paywall ATIVO (planos Free/Standard/Premium).
    //
    //  Builds de desenvolvimento (DEBUG, simulador/Xcode) ignoram isto e ficam SEMPRE liberados.
    //  Este é o ÚNICO lugar a mudar — não há duplicação. O banner "Test mode" e o unlock seguem daqui.
    //
    //                  ▼▼▼  MUDE PARA false ANTES DE SUBMETER À APP STORE  ▼▼▼
    static let isPreLaunchTestBuild = true
    //                  ▲▲▲  (deixe true enquanto testa no TestFlight)        ▲▲▲
    // ═══════════════════════════════════════════════════════════════════════════════════

    /// When `true`: Premium features + truck-only Valhalla routing liberados sem IAP.
    /// DEBUG = sempre true (dev). Release = segue `isPreLaunchTestBuild` (TestFlight=true; App Store=false).
    static var unlockAllFeaturesForTesting: Bool {
        #if DEBUG
        return true
        #else
        return isPreLaunchTestBuild
        #endif
    }

    #if !DEBUG
    // Lembrete em TODO build de release (aparece no log ao arquivar): confira o interruptor acima.
    #warning("Release: confirme AppAccessPolicy.isPreLaunchTestBuild — true=teste liberado, false=App Store (paywall).")
    #endif

    /// Fleet dispatch portal (loads from dispatcher) — off for solo-driver; nothing to tap while driving.
    static let driverDispatchEnabled = false

    /// Wellness mood sheets only when parked (speed near zero, not navigating).
    static let moodCheckOnlyWhenParked = true

    /// Check-in de bem-estar na abertura SEMPRE ativo (1x/dia) — parte central do produto.
    /// Antes era pulado no modo de testes e a pergunta de estrelas nunca aparecia.
    static var skipLaunchWellnessCheck: Bool { false }

    /// Keep Mapbox as Horizon map renderer (satellite/3D). Valhalla routing is separate and always truck-aware.
    static let useMapKitHorizonMap = false

    /// Truck routes: Valhalla only — never OSRM/MapKit fallback when Valhalla fails (show error instead).
    static var enforceTruckOnlyRouting: Bool { true }

    static func applyTestingDefaultsIfNeeded() {
        guard unlockAllFeaturesForTesting else { return }
        UserDefaults.standard.set(true, forKey: "truckSafeOnlyMode")
    }

    /// Route Easy tier: Free = fastest · Standard = no toll · Premium = AI smart.
    static func requiredPlan(for kind: RouteEasyKind) -> TruckerEasyPlan {
        switch kind {
        case .fastest: return .free
        case .fewerTolls: return .standard
        case .fuelSmart: return .premium
        }
    }

    static func canUseRouteEasyKind(_ kind: RouteEasyKind, plan: TruckerEasyPlan) -> Bool {
        if unlockAllFeaturesForTesting { return true }
        return plan >= requiredPlan(for: kind)
    }
}

enum AppDistributionConfig {
  private static func plistURLString(forKey key: String) -> String? {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
    let t = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "||", with: "//")
    guard !t.isEmpty, !t.contains("$(") else { return nil }
    return t
  }

  static var appStoreURL: URL? {
    plistURLString(forKey: "AppStoreURL").flatMap { URL(string: $0) }
  }

  static var testFlightURL: URL? {
    plistURLString(forKey: "TestFlightURL").flatMap { URL(string: $0) }
  }

  /// Primary public download link: App Store if set, otherwise TestFlight.
  static var publicDownloadURL: URL? {
    appStoreURL ?? testFlightURL
  }

  static var hasPublicDownloadLink: Bool {
    publicDownloadURL != nil
  }

  /// Marketing copy aligned with truckereasy.com (IAP may still show localized StoreKit prices).
  enum MarketingPrice {
    static let monthlyUSD = "$19.99"
    static let annualUSD = "$169.99"
    static let annualPerMonthUSD = "$14.16"
    static let annualSavingsUSD = "$69.89"
    static let trialDays = 3
  }
}
