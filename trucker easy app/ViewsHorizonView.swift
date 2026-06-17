// ViewsHorizonView.swift — REWRITTEN: clean layout + extracted sub-views
// Critical fixes:
//   1. Bottom sheet OPAQUE (no .ultraThinMaterial, no .opacity on dark bg)
//   2. ETA bar OPAQUE (no .opacity(0.38))
//   3. applyRoute() validates route before applying
// Sub-views extracted to: HorizonModels, HorizonBottomSheet, HorizonNavigationOverlays,
//   HorizonAlertOverlays, HorizonIdleOverlays, HorizonSheets

import SwiftUI
import MapKit
import SwiftData
import CoreLocation
import HealthKit
import Speech
import AVFoundation

#if DEBUG
import OSLog

private func horizonLogDebugWorkingDirectory() {
    let debugPath = FileManager.default.currentDirectoryPath
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruckerEasy", category: "HorizonView")
    logger.debug("📁 Debug path: \(debugPath, privacy: .public)")
}
#endif


// MARK: - Horizon View (Tab 1) — Map + Load Management
struct HorizonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var dispatchService = DispatchService.shared
    @State private var store = StoreKitManager.shared
    @Query private var trips: [Trip]
    @Query private var geofences: [GeofenceRegion]

    @State private var locationManager = LocationManager()
    @State private var selectedMapStyle: MapStyleOption = .globe
    @State private var mapAlerts: [MapAlert] = []
    @State private var route: MKRoute?
    @State private var truckRoute: TruckRoute?
    @State private var lastRoutingProvider: RoutingService.RoutingProvider = .unknown
    @State private var routeSteps: [DisplayRouteStep] = []
    @State private var currentStepIndex = 0
    @State private var showingSteps = false

    @State private var navigationEngine = NavigationEngine()
    @State private var restrictionWarningManager = TruckRestrictionWarningManager()
    /// Motor de telemetria — consolida HOS + navegação + restrições num NavigationState único.
    @State private var telemetryEngine = NavigationTelemetryEngine()
    @State private var dismissedRestrictionIds: Set<UUID> = []

    @State private var truckProfile = TruckProfile.loadSaved()
    @State private var showingTruckSettings = false
    @State private var truckWarnings: [TruckRestrictionWarning] = []
    @State private var showingTruckWarnings = false

    @State private var mapZoomIn:   (() -> Void)? = nil
    @State private var mapZoomOut:  (() -> Void)? = nil
    @State private var mapRecenter: (() -> Void)? = nil

    @State private var pendingDispatchLoad: DispatchedLoad?
    @State private var showingDispatchAlert = false
    @State private var activeLoad: DispatchedLoad?
    @State private var showingFuelReport = false

    @State private var selectedNearbyCategory: NearbyCategory? = nil
    @State private var nearbyItems: [NearbyStopItem] = []
    @State private var isLoadingNearby = false

    @State private var truckStopService = TruckStopService.shared
    @State private var routeSignageService = RouteSignageService.shared
    @State private var showingTruckStops = false
    @State private var selectedTruckStop: TruckStopItem? = nil
    @State private var showingTruckStopDetail = false
    @State private var showingHOSSettings = false

    @State private var currentTruckStop: TruckStopItem? = nil
    @State private var truckStopArrivedAt: Date? = nil
    @State private var parkingPromptShownFor: String = ""
    @State private var showingParkingPrompt = false

    @State private var locationHistory: [CLLocation] = []
    /// Sub-sample fixes into `locationHistory` — grade/curve alerts only need sparse points; avoids work every GPS tick.
    @State private var lastLocationHistorySampleAt: Date = .distantPast
    @State private var lastLocationHistorySample: CLLocation?
    @State private var showingGradeAlert = false
    @State private var gradeAlertMessage = ""
    @State private var gradeIsDescending = false
    @State private var showingCurveAlert = false
    @State private var showingWindAlert = false
    @State private var windAlertMph: Int = 0
    @State private var windAlertIsGust = false
    @State private var lastNavFuelEtaVoiceAt: Date = .distantPast
    @State private var lastGradeCheckAt: Date = .distantPast
    @State private var lastCurveCheckAt: Date = .distantPast
    @State private var lastWindCheckAt: Date = .distantPast

    @State private var showingDockFinder = false
    @State private var dockResults: [NearbyStopItem] = []
    @State private var dockCheckDone = false

    @State private var foodSuggestion: FoodSuggestion? = nil
    @State private var showingFoodSuggestion = false
    @State private var lastFoodSuggestionLocation: CLLocation? = nil

    @State private var showingLoadSheet = false
    @State private var showingTripLog = false

    @State private var destinationAddress = ""
    @State private var activeRouteDestination: CLLocationCoordinate2D? = nil
    @State private var isCalculatingRoute = false
    @State private var routeError: String?
    @State private var showingRouteError = false
    @AppStorage("truckSafeOnlyMode") private var truckSafeOnlyMode = AppAccessPolicy.enforceTruckOnlyRouting
    @State private var pendingFallbackRoute: TruckRoute?
    @State private var pendingFallbackProvider: RoutingService.RoutingProvider = .unknown
    @State private var showingFallbackConfirmation = false

    @State private var bottomSheetExpanded = false
    @State private var launchSafeScreenHeight: CGFloat = UIScreen.main.bounds.height
    @State private var isIdleBottomSheetReady = false

    private var idleBottomSheetHeight: CGFloat {
        bottomSheetExpanded ? launchSafeScreenHeight * 0.62 : idleCollapsedChromeHeight
    }

    /// Dispatch UI hidden for driver beta — backend hooks remain for fleet portal later.
    private var dispatchDriverUIEnabled: Bool { AppAccessPolicy.driverDispatchEnabled }

    @State private var navigationPOIsHidden = false

    /// POIs on map (always during navigation unless driver taps Hide).
    ///
    /// Trucker Path–style: during navigation we keep POIs visible in a ~40 mi window
    /// AHEAD of the driver (truck stops, rest areas, weigh, fuel, repair), prioritising
    /// those on/near the heading and nearest first, then cap the count so Mapbox stays
    /// smooth on the 8GB M1. We never auto-hide here — only the explicit "Hide POIs"
    /// toggle clears the layer. Selection updates as the rig advances because the source
    /// list (`nearbyStops`) is refreshed every ~2 km while navigating.
    private var mapTruckStopsForDisplay: [TruckStopItem] {
        guard !navigationPOIsHidden else { return [] }
        let stops = truckStopService.nearbyStops
        guard !stops.isEmpty else { return [] }

        // Idle: keep the nearest cluster around the rig so the map isn't bare.
        guard isNavigating, let loc = locationManager.currentLocation else {
            return Array(
                stops.sorted { $0.distanceMeters < $1.distanceMeters }
                    .prefix(Self.idlePoiDisplayCap)
            )
        }

        let aheadWindowMeters = 64_373.0 // ~40 mi lookahead corridor
        let heading = locationManager.currentHeading?.trueHeading
        let origin = loc.coordinate

        let candidates = stops.filter { stop in
            guard stop.distanceMeters <= aheadWindowMeters else { return false }
            // Anything very close stays (could be just ahead even if bearing is noisy at low speed).
            if stop.distanceMeters <= 1_200 { return true }
            guard let heading else { return true }
            let diff = abs(angleDeltaDegrees(heading, origin.bearing(to: stop.coordinate)))
            return diff <= 80 // keep the corridor ahead; drop POIs behind the driver
        }

        return Array(
            candidates.sorted { $0.distanceMeters < $1.distanceMeters }
                .prefix(Self.navigationPoiDisplayCap)
        )
    }

    /// Pin caps keep Mapbox annotation churn cheap on the 8GB M1.
    private static let navigationPoiDisplayCap = 20
    private static let idlePoiDisplayCap = 24

    /// Upcoming truck stops + weigh ahead (Trucker Path–style corridor rail).
    private var corridorRailItems: [HorizonCorridorRailItem] {
        guard isNavigating, let loc = locationManager.currentLocation else { return [] }
        let heading = locationManager.currentHeading?.trueHeading
        var items: [HorizonCorridorRailItem] = []

        if showingScaleAlert {
            items.append(HorizonCorridorRailItem(
                id: "scale-\(scaleAlertName)",
                kind: .weighStation,
                title: scaleAlertName,
                distanceMiles: scaleAlertDistanceMiles,
                status: scaleAlertStatus,
                isOfficialStatus: scaleAlertProvenance.isOfficial
            ))
        }

        for stop in truckStopService.nearbyStops {
            let distMeters = stop.distanceMeters
            guard distMeters <= 80_467 else { continue } // 50 mi
            if let heading {
                let coord = stop.coordinate
                let diff = abs(angleDeltaDegrees(heading, loc.coordinate.bearing(to: coord)))
                guard diff <= 75 else { continue }
            }
            let parkingStatus: ScaleAlertBanner.ScaleStatus? = {
                if let avail = stop.amenities.parkingAvailable {
                    return avail == 0 ? .closed : .open
                }
                switch stop.amenities.parkingStatus {
                case .full: return .closed
                case .available, .limited: return .open
                case .unknown: return nil
                }
            }()
            items.append(HorizonCorridorRailItem(
                id: stop.id.uuidString,
                kind: .truckStop,
                title: stop.name,
                distanceMiles: distMeters / 1609.34,
                status: parkingStatus,
                isOfficialStatus: stop.dataSource == .supabase && parkingStatus != nil
            ))
        }

        return items
            .sorted { $0.distanceMiles < $1.distanceMiles }
            .prefix(5)
            .map { $0 }
    }

    /// Comfort dark chrome: always while navigating; when idle, local time 18:00–05:59 (driver timezone).
    private var navigationPrefersDarkChrome: Bool {
        if isNavigating { return true }
        let h = Calendar.current.component(.hour, from: Date())
        return h < 6 || h >= 18
    }

    private var idleCollapsedChromeHeight: CGFloat {
        GPSDesignSystem.Metrics.toolbarHeight + 14 + 84
    }

    /// Espaço acima da tab bar nativa (Meu Horizonte, Check-up…).
    private var mainTabBarClearance: CGFloat { 52 }

    /// Para posicionar zoom/IA sem sobrepor o painel idle.
    private var idleMapControlsBottomInset: CGFloat {
        idleBottomSheetHeight + mainTabBarClearance + 12
    }

    private var navigationTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 52
    }

    /// Altura estimada do topo em navegação (barra compacta + faixas opcionais).
    private var navigationTopChromeHeight: CGFloat {
        guard isNavigating else { return 110 }
        var height = navigationTopInset + 88
        if !routeSteps.isEmpty,
           currentStepIndex < routeSteps.count,
           isHighwayStep(routeSteps[currentStepIndex].instructions) {
            height += GPSDesignSystem.Metrics.laneGuidanceHeight + 4
        }
        return height
    }

    /// Margem direita — coluna de zoom/mute no chrome de navegação.
    private var navigationRightRailWidth: CGFloat { 56 }

    /// Largura reservada para o pill DOT (banner não invade este slot).
    private var dotHosPillSlotWidth: CGFloat { 128 }

    private var dotHosTopPadding: CGFloat {
        isNavigating ? max(8, navigationTopInset - 2) : 56
    }

    private var dotHosReservedTrailing: CGFloat { dotHosPillSlotWidth + 14 }

    /// Keeps the leading tool column scrollable on short phones so it never runs into the bottom parking/control row.
    private var idleLeadingToolsScrollMaxHeight: CGFloat {
        let h = launchSafeScreenHeight
        return max(140, min(360, h - 400))
    }

    @State private var showingGlobalSearch = false

    @State private var hosContext = DotHosContext()
    @State private var showingHosDetail = false

    @State private var showingMoodCheck = false
    @State private var hasShownMoodAtDuskToday = false
    @State private var lastSpeedCheckDate: Date = .distantPast
    @State private var speedMonitorTimer: Timer? = nil
    @AppStorage("lastMoodCheckDate") private var lastMoodCheckDateString: String = ""
    @AppStorage("lastCheckInDate") private var lastCheckInDateStr: String = ""

    @State private var weatherService = WeatherService.shared
    @State private var showingWeather = false
    @State private var weatherShownThisLaunch = false

    @State private var showingShareTrip = false
    @State private var loadPickupAddress = ""
    @State private var loadDropoffAddress = ""
    @State private var loadCargoOnBoard = false
    @State private var isAnalyzingLoadRoute = false

    @State private var showingWeighStation = false

    @State private var showingScaleAlert = false
    @State private var scaleAlertName = ""
    @State private var scaleAlertDistanceMiles: Double = 5.0
    @State private var scaleAlertStatus: ScaleAlertBanner.ScaleStatus = .unknown
    @State private var scaleAlertCoordinate: CLLocationCoordinate2D?
    @State private var scaleAlertPoiPlaceId: UUID?
    @State private var scaleAlertGovStatus: String?
    @State private var scaleAlertGovSource: String?
    @State private var scaleAlertGovSiteOpen: Bool?
    @State private var scaleAlertProvenance: WeighStationStatusProvenance = .locationOnly
    @State private var scaleAlertCommunityHint: WeighStationStatus?
    @State private var scaleAlertCommunitySummary: WeighStationCommunitySummary?
    /// Staged alerts already fired ("stationKey#tier") — first at 50 mi, update at 20 mi, final at 5 mi.
    @State private var scaleAlertNotifiedTierKeys: Set<String> = []
    @State private var lastScaleVoiceKey: String?
    @State private var lastWeighCrowdSyncAt: Date = .distantPast
    @State private var lastScaleCheckLocation: CLLocation? = nil
    /// Cooldown do retry de POIs com lista vazia — sem isto, re-tentava a cada tick de GPS
    /// (~13 buscas MapKit/ciclo), estourava a cota iOS de 50 req/min (GEOErrorDomain -3)
    /// e derrubava TODA busca por nome no app (sugestões e geocode do destino).
    @State private var lastNearbySearchAttemptAt: Date = .distantPast
    /// ETA × HOS: nível já anunciado nesta rota (nil = ainda não falou) —
    /// 0 confortável · 1 apertado (<30min de folga) · 2 estoura o limite de direção.
    @State private var hosEtaAnnouncedLevel: Int? = nil
    @State private var lastHosEtaCheckAt: Date = .distantPast

    @State private var showingCheapestDiesel = false
    @State private var cheapestDieselStop: TruckStopItem? = nil
    @State private var publicDieselPrice: FuelPricePoint? = nil
    /// Limite de velocidade real (km/h) da via atual, do Valhalla /locate. Issue 2.
    @State private var currentEdgeSpeedLimitKmh: Double? = nil

    @State private var currentTollResult: TollResult? = nil
    @State private var currentProfitability: TripProfitability? = nil

    @State private var nearestParkingName: String = ""
    @State private var nearestParkingMiles: Double = 0
    @State private var nearestParkingFull: Bool = false
    @State private var showParkingPill: Bool = false
    @State private var showingStopsSheet: Bool = false

    @State private var showingAIChat = false
    @State private var aiChatMessages: [(role: String, text: String)] = []
    @State private var aiChatInput = ""
    @State private var aiIsStreaming = false

    @State private var showingRouteEasyPicker = false
    @State private var showingRouteEasyUpgrade = false
    @State private var routeEasyUpsellKind: RouteEasyKind = .fewerTolls
    @State private var routeEasyOptions: [RouteEasyOption] = []
    @State private var routeEasyPendingCoordinate: CLLocationCoordinate2D?
    @State private var routeEasyPendingAddress: String = ""
    @State private var integrationHealthResults: [IntegrationHealthResult] = []
    @State private var integrationHealthChecked = false

    @State private var logisticsNewsService = LogisticsNewsService.shared

    @State private var reviewTargetStop: TruckStopItem? = nil
    @State private var showingStopReview = false

    private struct PendingFacilityVisit: Equatable {
        let load: DispatchedLoad
        let type: FacilityReviewType
        let coordinate: CLLocationCoordinate2D
        let arrivedAt: Date
    }
    @State private var pendingFacilityVisit: PendingFacilityVisit? = nil

    private let stopReviewMinDwellSeconds: TimeInterval = 180
    private let facilityReviewMinDwellSeconds: TimeInterval = 120
    private let facilityDepartureRadiusMeters: Double = 500

    @State private var showingFacilityReview = false
    @State private var facilityReviewType: FacilityReviewType = .pickup
    @State private var facilityReviewLoad: DispatchedLoad? = nil
    @State private var facilityReviewCoordinate: CLLocationCoordinate2D? = nil
    @State private var loadPickedUp = false

    @State private var showingArrival = false
    @State private var arrivalDestinationName = ""
    @State private var lastRerouteAt: Date = .distantPast

    /// Idle-only: blocks duplicate route starts within a short window (same origin/destination), e.g. suggestion tap + stray submit.
    @State private var lastIdleRouteDedupeKey: String = ""
    @State private var lastIdleRouteDedupeAt: Date = .distantPast

    private var gpsIsLive: Bool {
        guard let loc = locationManager.currentLocation else { return false }
        let age = abs(loc.timestamp.timeIntervalSinceNow)
        let maxAge: TimeInterval = isNavigating ? 30 : 60
        let maxAccuracy: CLLocationDistance = isNavigating ? 150 : 120
        return age <= maxAge && loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= maxAccuracy
    }

    /// Distância mínima (m) do motorista a uma polyline de rota. Amostra os pontos (rota pode ter
    /// milhares) — aproximação suficiente pra ESCOLHER qual corredor está mais perto (Fase 1.2b).
    private func minDistanceToRoute(_ loc: CLLocation, _ coords: [CLLocationCoordinate2D]) -> Double {
        guard !coords.isEmpty else { return .greatestFiniteMagnitude }
        var best = Double.greatestFiniteMagnitude
        let step = max(1, coords.count / 400)
        var i = 0
        while i < coords.count {
            let c = coords[i]
            let d = loc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < best { best = d }
            i += step
        }
        return best
    }

    private var gpsStatusText: String {
        guard let loc = locationManager.currentLocation else { return lang.horizonGpsSearching }
        let age = Int(abs(loc.timestamp.timeIntervalSinceNow))
        if gpsIsLive { return lang.horizonGpsLive(accuracyMeters: Int(loc.horizontalAccuracy)) }
        return lang.horizonGpsStale(seconds: age)
    }
    @State private var lastOpsRefreshAt: Date = .distantPast
    @State private var lastOpsRefreshLocation: CLLocation? = nil
    @State private var lastExternalRefreshAt: Date = .distantPast
    @State private var lastExternalRefreshLocation: CLLocation? = nil

    @State private var voiceManager = VoiceNavigationManager.shared
    @State private var countryCompliance = CountryComplianceManager.shared
    @State private var fleetTelemetryService = FleetTelemetryService.shared
    @State private var jurisdictionPolicyService = JurisdictionPolicyService.shared
    @State private var networkReachability = NetworkReachability.shared
    @State private var operationalFeedService = OperationalFeedService.shared
    @State private var showingSpeedComplianceAlert = false
    @State private var speedComplianceMessage = ""
    @State private var lastSpeedComplianceAlertAt: Date = .distantPast
    @State private var geofenceInsideState: [UUID: Bool] = [:]
    @State private var showDataDiagnostics = false

    var activeTrip: Trip? { trips.first(where: { $0.isActive }) }
    var lang: AppLanguage { regionalSettings.currentLanguage }
    /// Purple route line when solver is Neal / Leap / Braket (geometry still from Valhalla/OSRM/MapKit).
    private var routeQuantumMapLineAccent: Bool { truckRoute?.provenance?.usesQuantumAccentPolyline ?? false }
    private var isNavigating: Bool { truckRoute != nil || route != nil }

    /// HOS REAL vindo do timer DOT (DotHosContext) — substitui o antigo HOSState.mock
    /// (4h30 fixos) que chegava aos painéis de truck stop. Dado real, sem adivinhação.
    private var liveHOSState: HOSState {
        HOSState(
            driveTimeRemainingHours: hosContext.drivingRemaining / 3600,
            dutyTimeRemainingHours: hosContext.shiftRemaining / 3600,
            isInBreak: hosContext.status == .offDuty || hosContext.status == .sleeper,
            breakEndsAt: nil,
            averageDrivingSpeedMph: hosContext.averageDrivingSpeedMph
        )
    }
    private var subscriptionPlan: TruckerEasyPlan { store.effectivePlan }
    private var routingAccessMode: RoutingService.RoutingAccessMode {
        if subscriptionPlan.hasTruckRoutes || AppAccessPolicy.unlockAllFeaturesForTesting {
            return .truckAware
        }
        return .automobileOnly
    }
    private var routeEasyIncludesFuelSmart: Bool {
        subscriptionPlan.hasRouteIntelligence
    }
    private var activeDistanceMeters: Double { truckRoute?.distanceMeters ?? route?.distance ?? 0 }
    private var activeDurationSeconds: Double {
        if let here = truckRoute { return here.durationSeconds }
        return route?.expectedTravelTime ?? 0
    }

    // MARK: - Body (split into 3 levels for Swift type-checker)

    var body: some View {
        withSheetModifiers
            .modifier(VoiceNavigationModifier(
                voiceManager: voiceManager, lang: lang,
                currentStepIndex: currentStepIndex, routeSteps: routeSteps,
                isNavigating: isNavigating, truckRoute: truckRoute,
                showingScaleAlert: showingScaleAlert, scaleAlertName: scaleAlertName,
                scaleAlertDistanceMiles: scaleAlertDistanceMiles,
                mapAlerts: mapAlerts,
                formatDistance: { regionalSettings.formatDistance($0) }
            ))
            // Tab bar always visible — hiding it trapped users on Horizon after route preview.
            .toolbar(.visible, for: .tabBar)
            // ━━━ NUCLEAR FIX: white background behind EVERYTHING ━━━
            .background(Color.white.ignoresSafeArea())
            .dotSpeedFeeder(locationManager: locationManager, hosContext: hosContext)
    }

    // MARK: - Lifecycle + onChange modifiers
    @ViewBuilder private var withLifecycleModifiers: some View {
        mainStack
            .onAppear {
                #if DEBUG
                horizonLogDebugWorkingDirectory()
                #endif
                isIdleBottomSheetReady = false
                launchSafeScreenHeight = UIScreen.main.bounds.height
                DispatchQueue.main.async {
                    self.isIdleBottomSheetReady = true
                }
                // Atualiza o style pack offline do Mapbox p/ a versão atual (Offline API) — limpa o
                // aviso "outdated resource mapbox://styles/mapbox/standard shall be updated".
                OfflineRouteTileManager.shared.updateOfflineResources()
                // Clear ALL old route caches to prevent stale data from causing issues
                for key in ["offlineRouteCache_v1", "offlineRouteCache_v2"] {
                    UserDefaults.standard.removeObject(forKey: key)
                }
                locationManager.requestPermission()
                locationManager.startTracking()
                NetworkReachability.shared.start()
                #if canImport(HealthKit)
                if let hk = HealthKitManager.shared { hk.requestAuthorization() }
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if let loc = locationManager.currentLocation {
                        // Truck stops load from handleLocationUpdate (avoids duplicate places_near on launch).
                        Task {
                            await fleetTelemetryService.refreshIfNeeded()
                            await countryCompliance.refreshIfNeeded(for: loc)
                            await jurisdictionPolicyService.refreshIfNeeded(for: loc)
                            await operationalFeedService.refreshIfNeeded(for: loc.coordinate)
                            await MainActor.run { syncRegionalPolicyFromLocation() }
                        }
                        Task { await weatherService.refresh(for: loc.coordinate) }
                    }
                    loadRemoteAlerts()
                }
                let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
                let hour = Calendar.current.component(.hour, from: Date())
                if lastMoodCheckDateString != todayStr && hour >= 18 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        presentMoodCheckIfParked()
                    }
                }
                if let loc = locationManager.currentLocation {
                    Task {
                        await WeighStationStatusService.shared.fetchRemoteReports(
                            near: loc.coordinate,
                            radiusKm: 200
                        )
                    }
                }
                startSpeedMonitoringForDusk()
                Task { if dispatchDriverUIEnabled { await fetchPendingDispatchLoads() } }
                let hos = regionalSettings.hosRules
                hosContext.updateRules(maxDriving: hos.maxDrivingHours, serviceWindow: hos.serviceWindowHours,
                                       breakAfter: hos.mandatoryBreakAfterHours, breakMinutes: hos.mandatoryBreakMinutes)
                let mph = max(0, (locationManager.currentLocation?.speed ?? 0) * 2.23694)
                hosContext.reconcileParkedAtLaunch(isNavigating: isNavigating, speedMph: mph)
                Task {
                    let health = await IntegrationsHealthCheck.checkValhalla()
                    #if DEBUG
                    print("[TruckerEasy] Valhalla \(health.ok ? "ONLINE" : "OFFLINE") — \(health.detail)")
                    #endif
                }
            }
            .onDisappear {
                locationManager.stopTracking(); speedMonitorTimer?.invalidate(); speedMonitorTimer = nil
                UIApplication.shared.isIdleTimerDisabled = false
                mapAlerts.removeAll(); dismissedRestrictionIds.removeAll(); truckWarnings = []
                URLCache.shared.removeAllCachedResponses()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                mapAlerts = Array(mapAlerts.suffix(10)); dismissedRestrictionIds.removeAll()
                truckWarnings = []; URLCache.shared.removeAllCachedResponses()
            }
            .onChange(of: truckProfile) { _, newProfile in newProfile.save() }
            .onChange(of: selectedNearbyCategory) { _, cat in
                nearbyItems = []; if let cat = cat { searchNearby(category: cat) }
            }
            .onChange(of: route) { _, newRoute in
                handleRouteStateChange(hasRoute: newRoute != nil || truckRoute != nil)
            }
            .onChange(of: truckRoute) { _, newHere in
                handleTruckRouteStateChange(hasRoute: newHere != nil || route != nil)
            }
            .onChange(of: isNavigating) { _, navigating in
                handleNavigationModeChange(navigating)
            }
            .onChange(of: dispatchService.pendingLoad) { _, newLoad in
                guard dispatchDriverUIEnabled else { return }
                if let load = newLoad { pendingDispatchLoad = load; withAnimation { showingDispatchAlert = true } }
            }
            .onChange(of: regionalSettings.currentRegion) { _, _ in
                let hos = regionalSettings.hosRules
                hosContext.updateRules(maxDriving: hos.maxDrivingHours, serviceWindow: hos.serviceWindowHours,
                                       breakAfter: hos.mandatoryBreakAfterHours, breakMinutes: hos.mandatoryBreakMinutes)
            }
            .onChange(of: jurisdictionPolicyService.gpsHosRegion) { _, region in
                // Compliance P0: a regra de HOS segue o país do GPS ao vivo. Cruzou US<->CA, troca
                // 11h/14h <-> 13h/16h sem o motorista mexer em nada. Unidades/moeda NÃO mudam.
                guard let region else { return }
                let hos = region.hosRules
                hosContext.updateRules(maxDriving: hos.maxDrivingHours, serviceWindow: hos.serviceWindowHours,
                                       breakAfter: hos.mandatoryBreakAfterHours, breakMinutes: hos.mandatoryBreakMinutes)
            }
            .onChange(of: regionalSettings.currentLanguage) { _, newLang in
                navigationEngine.language = newLang; VoiceNavigationManager.shared.resetForNewRoute()
            }
            .onChange(of: locationManager.locationFixEpoch) { _, _ in
                handleLocationUpdate()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active, .background:
                    locationManager.startTracking()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
    }

    // MARK: - Sheet modifiers
    @ViewBuilder private var withSheetModifiers: some View {
        withLifecycleModifiers
            .sheet(isPresented: $showingLoadSheet) {
                HorizonGotALoadSheet(lang: lang, onRouteConfirmed: { address in
                    destinationAddress = address; showingLoadSheet = false; calculateRoute(to: address)
                })
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingTruckSettings) {
                HorizonTruckSettingsSheet(profile: $truckProfile, truckSafeOnlyMode: $truckSafeOnlyMode, lang: lang)
                    .presentationDetents([.medium]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingHOSSettings) {
                HOSSettingsSheet(hos: $truckStopService.hos)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(item: $selectedTruckStop) { stop in
                TruckStopDetailSheet(stop: stop, hos: liveHOSState, onNavigate: { truckStop in
                    calculateRoute(to: truckStop.coordinate, address: truckStop.name); showingTruckStops = false
                })
                .presentationDetents([.large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingStopReview, onDismiss: { reviewTargetStop = nil }) {
                if let stop = reviewTargetStop {
                    StopReviewSheet(stop: stop) { review in
                        try await submitStopReview(review, for: stop)
                    }
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showingFacilityReview) {
                if let load = facilityReviewLoad, let coordinate = facilityReviewCoordinate {
                    FacilityReviewSheet(
                        load: load,
                        type: facilityReviewType,
                        visitCoordinate: coordinate,
                        onSubmit: { review in
                            Task { await submitFacilityReview(review) }
                        },
                        onSkip: {
                            facilityReviewLoad = nil
                            facilityReviewCoordinate = nil
                            pendingFacilityVisit = nil
                        }
                    )
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showingGlobalSearch) {
                HorizonGlobalSearchSheet(locationManager: locationManager,
                    onSelectResult: { coordinate, address in showingGlobalSearch = false; calculateRoute(to: coordinate, address: address) },
                    onSelectCategory: { category in showingGlobalSearch = false; selectedNearbyCategory = category })
                .presentationDetents([.large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingMoodCheck) {
                HorizonMoodCheckSheet(lang: lang, onSubmit: { rating in
                    let log = WellnessLog(category: .mental, date: Date(), notes: "Mood \(rating)/5")
                    log.stressLevel = 6 - rating
                    modelContext.insert(log)
                    try? modelContext.save()
                    WellnessCloudSync.pushDailyCheckin(moodStars: rating, source: .horizon)
                    showingMoodCheck = false
                }, onSkip: { showingMoodCheck = false })
                    .presentationDetents([.medium]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingShareTrip) {
                ShareTripProgressSheet(trip: activeTrip, route: route, locationManager: locationManager, isPresented: $showingShareTrip)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingWeighStation) {
                WeighStationStatusSheet(
                    driverLocation: locationManager.currentLocation,
                    prefilledTarget: weighReportPrefillTarget(),
                    lang: lang,
                    formatDistance: { regionalSettings.formatDistance($0) },
                    isPresented: $showingWeighStation
                )
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingHosDetail) {
                DotHosDetailSheet(hosContext: hosContext)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingFuelReport) {
                if let load = activeLoad {
                    HorizonFuelReportSheet(load: load) { gallons, price, station in
                        #if DEBUG
                        print("FuelReport: \(gallons) gal @ $\(price) at \(station ?? "unknown")")
                        #endif
                    }
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
                }
            }
            .alert(lang.horizonRouteErrorTitle, isPresented: $showingRouteError) { Button(lang.okLabel) {} }
                message: { Text(routeError ?? lang.horizonRouteErrorCouldNotCalculate) }
            .confirmationDialog(lang.horizonTruckSafeUnavailableTitle, isPresented: $showingFallbackConfirmation, titleVisibility: .visible) {
                Button(lang.horizonContinueWithFallbackGPS) { applyPendingFallbackRoute() }
                Button(lang.cancelLabel, role: .cancel) { pendingFallbackRoute = nil; pendingFallbackProvider = .unknown; bottomSheetExpanded = false }
            } message: {
                Text(lang.horizonTruckSafeFallbackExplanation(provider: pendingFallbackProvider.rawValue))
            }
            .sheet(isPresented: $showingRouteEasyPicker) {
                HorizonRouteEasyPickerSheet(
                    options: routeEasyOptions,
                    destinationName: routeEasyPendingAddress,
                    useMiles: !regionalSettings.currentRegion.usesMetric,
                    currentPlan: subscriptionPlan,
                    lang: lang,
                    onSelect: { option in
                        selectRouteEasyOption(option)
                    },
                    onUpgrade: { kind in
                        presentRouteEasyUpgrade(for: kind)
                    },
                    onCancel: {
                        showingRouteEasyPicker = false
                        routeEasyOptions = []
                        routeEasyPendingCoordinate = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(isCalculatingRoute)
            }
            .sheet(isPresented: $showingRouteEasyUpgrade) {
                SubscriptionView(highlightPlan: AppAccessPolicy.requiredPlan(for: routeEasyUpsellKind))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
    }

    // MARK: - Main Map ZStack

    @ViewBuilder private var mainStack: some View {
        ZStack(alignment: .top) {
            // Layer 0: matte black while navigating / at night; light when idle day map browsing
            (navigationPrefersDarkChrome ? Color(hex: "#0f0d0b") : Color.white).ignoresSafeArea(.all)

            Group {
                #if canImport(MapboxMaps)
                if MapProviderConfig.isMapboxHorizonRendererEnabled {
                    HorizonMapboxSurface(
                        selectedMapStyle: selectedMapStyle,
                        locationManager: locationManager,
                        mapAlerts: [],
                        route: route,
                        truckRoute: truckRoute,
                        routeQuantumLineAccent: routeQuantumMapLineAccent,
                        isNavigating: isNavigating,
                        dimRoute: navigationEngine.shouldDimOldRoute,
                        onStyleChange: { selectedMapStyle = $0 },
                        onControlsReady: { zoomIn, zoomOut, recenter in
                            mapZoomIn = zoomIn; mapZoomOut = zoomOut; mapRecenter = recenter
                        },
                        truckStops: isNavigating ? mapTruckStopsForDisplay : [],
                        routeSignage: isNavigating ? routeSignageService.onRouteSignage : [],
                        onTruckStopTapped: { stop in selectedTruckStop = stop }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                } else {
                    HorizonMapSurface(
                        selectedMapStyle: selectedMapStyle,
                        locationManager: locationManager,
                        mapAlerts: isNavigating ? [] : mapAlerts,
                        route: route,
                        truckRoute: truckRoute,
                        routeQuantumLineAccent: routeQuantumMapLineAccent,
                        isNavigating: isNavigating,
                        onStyleChange: { selectedMapStyle = $0 },
                        onControlsReady: { zoomIn, zoomOut, recenter in
                            mapZoomIn = zoomIn; mapZoomOut = zoomOut; mapRecenter = recenter
                        },
                        truckStops: mapTruckStopsForDisplay,
                        onTruckStopTapped: { stop in selectedTruckStop = stop }
                    )
                }
                #else
                HorizonMapSurface(
                    selectedMapStyle: selectedMapStyle,
                    locationManager: locationManager,
                    mapAlerts: isNavigating ? [] : mapAlerts,
                    route: route,
                    truckRoute: truckRoute,
                    routeQuantumLineAccent: routeQuantumMapLineAccent,
                    isNavigating: isNavigating,
                    onStyleChange: { selectedMapStyle = $0 },
                    onControlsReady: { zoomIn, zoomOut, recenter in
                        mapZoomIn = zoomIn; mapZoomOut = zoomOut; mapRecenter = recenter
                    },
                    truckStops: mapTruckStopsForDisplay,
                    onTruckStopTapped: { stop in selectedTruckStop = stop }
                )
                #endif
            }
            .ignoresSafeArea()
            .preferredColorScheme(navigationPrefersDarkChrome ? .dark : .light)

            if !isNavigating {
                HorizonTopHUD(
                    activeTrip: activeTrip, regionalSettings: regionalSettings,
                    truckProfile: $truckProfile, truckWarnings: truckWarnings,
                    showingTruckSettings: $showingTruckSettings, selectedMapStyle: $selectedMapStyle,
                    onReportAlert: { addAlert(type: $0) },
                    showingTruckStops: $showingTruckStops, locationManager: locationManager,
                    truckStopService: truckStopService, selectedNearbyCategory: $selectedNearbyCategory,
                    showingHOSSettings: $showingHOSSettings, showingGlobalSearch: $showingGlobalSearch,
                    showingWeighStation: $showingWeighStation, voiceManager: voiceManager
                )
            }

            // DOT/HOS — hidden during active navigation (competitor-style clean map).
            if !isNavigating {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: 0)
                        horizonDotHosPill
                            .frame(width: dotHosPillSlotWidth, alignment: .trailing)
                    }
                    .padding(.top, dotHosTopPadding)
                    .padding(.trailing, 10)
                    Spacer(minLength: 0)
                }
                .zIndex(310)
                .allowsHitTesting(true)
            }

            if isNavigating, !routeSteps.isEmpty {
                let safeStepIndex = min(max(currentStepIndex, 0), routeSteps.count - 1)
                HorizonTruckerPathNavigationChrome(
                    step: routeSteps[safeStepIndex],
                    nextStepInstruction: routeSteps.indices.contains(safeStepIndex + 1)
                        ? routeSteps[safeStepIndex + 1].instructions : nil,
                    liveManeuverDistanceMeters: navigationEngine.distanceToNextStep,
                    formatDistance: { m in regionalSettings.formatDistance(m) },
                    roadLine: navigationRoadLine,
                    totalDistanceText: regionalSettings.formatDistance(activeDistanceMeters),
                    totalDurationText: formatNavDuration(activeDurationSeconds),
                    arrivalText: formatArrivalClock(),
                    speedLimit: navSpeedLimitText,
                    currentSpeed: navCurrentSpeedText,
                    speedUnit: regionalSettings.currentRegion.distanceUnit == "mi" ? "MPH" : "KM/H",
                    isOverspeeding: navOverspeeding,
                    // Falso-positivo removido: a barra mostrava sempre 4 faixas todas ativas (sem dado
                    // real de qual faixa pegar). Fica oculta até o lane guidance REAL (parse de
                    // maneuver.lanes do Valhalla) — feature do Tier 2 pós-TestFlight.
                    showLaneBar: false,
                    selectedMapStyle: $selectedMapStyle,
                    voiceManager: voiceManager,
                    lang: lang,
                    corridorRailItems: corridorRailItems,
                    hosContext: hosContext,
                    onHosTap: { showingHosDetail = true },
                    onZoomIn: { mapZoomIn?() },
                    onZoomOut: { mapZoomOut?() },
                    onRecenter: { mapRecenter?() },
                    onReroute: activeRouteDestination.map { dest in
                        let label = truckRoute?.destinationName ?? route?.name ?? ""
                        return { calculateRoute(to: dest, address: label) }
                    },
                    onStopNavigation: {
                        navigationEngine.stopNavigation()
                        restrictionWarningManager.clearWarnings()
                        #if canImport(MapboxMaps)
                        OfflineRouteTileManager.shared.clear()
                        #endif
                        var t = Transaction(animation: nil); t.disablesAnimations = true
                        withTransaction(t) {
                            truckRoute = nil
                            route = nil
                            routeSteps = []
                            currentStepIndex = 0
                        }
                    },
                    onToggleSteps: { showingSteps.toggle() },
                    onTogglePOIs: { navigationPOIsHidden.toggle() },
                    poisHidden: navigationPOIsHidden
                )
                .zIndex(400)
            }

            // Fase 1.4: banner honesto de offline durante a navegação. O GPS é local (continua) e
            // a rota está em cache — só o recálculo online está fora. Nunca esconder esse estado.
            if isNavigating && !networkReachability.isOnline {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash").font(.system(size: 12, weight: .bold))
                        Text(lang.horizonOfflineFollowRoute).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .overlay(Capsule().stroke(Color.orange.opacity(0.55), lineWidth: 1))
                    .padding(.top, 150)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(420)
            }

            navigationOverlays
            alertOverlays
            if !isNavigating { mapControlsOverlay }
            warningsDispatchAndBottomOverlays
        }
        .animation(.spring(response: 0.35), value: navigationTopChromeHeight)
    }

    // MARK: - Navigation Overlays

    /// Left column: icon-only quick actions + HOS (same gestures as before; avoids overlapping TopHUD and bottom parking pill).
    // idleLeadingToolColumn removed — tools are accessible via bottom sheet

    /// Top-trailing DOT/HOS status. This replaces the old GPS text chip so Horizon highlights
    /// hours-of-service compliance instead of exposing raw location/debug status.
    @ViewBuilder private var horizonDotHosPill: some View {
        DotHosBar(hosContext: hosContext) {
            withAnimation(.spring(response: 0.28)) {
                showingHosDetail = true
            }
        }
        .accessibilityLabel("DOT Hours of Service")
    }

    /// Bottom inset for map chrome while navigating (barra compacta + tab bar).
    private var navigatingMapChromeBottomInset: CGFloat { 88 }

    @ViewBuilder private var horizonParkingPill: some View {
        Button(action: { showingStopsSheet = true }) {
            HStack(spacing: 6) {
                Image(systemName: "p.circle.fill").font(.system(size: 13, weight: .bold))
                    .foregroundColor(nearestParkingFull ? Color(hex: "#ef4444") : Color(hex: "#10b981"))
                Text(String(format: "%.1f mi", nearestParkingMiles))
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                Circle().fill(nearestParkingFull ? Color(hex: "#ef4444") : Color(hex: "#10b981"))
                    .frame(width: 7, height: 7)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Color(hex: "#0d1117")).cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    @ViewBuilder private var navigationOverlays: some View {
        if showingSteps, isNavigating, !routeSteps.isEmpty {
            VStack {
                Spacer().frame(height: navigationTopChromeHeight + 20)
                HorizonRouteStepsList(
                    steps: routeSteps, currentIndex: currentStepIndex,
                    formatDistance: { m in regionalSettings.formatDistance(m) },
                    onSelect: { idx in
                        syncNavigationStepIndexFromUI(idx)
                        showingSteps = false
                    },
                    onClose: { showingSteps = false }, lang: lang
                )
                .padding(.horizontal, AppTheme.Spacing.md)
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        // Arrival Card
        if showingArrival {
            VStack {
                Spacer().allowsHitTesting(false)
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: "#22d474"), Color(hex: "#16a34a")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(lang.horizonYouHaveArrived)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(arrivalDestinationName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "#22d474"))
                        .multilineTextAlignment(.center).lineLimit(2)
                    Button(action: {
                        withAnimation { showingArrival = false }
                        truckRoute = nil; route = nil; routeSteps = []; currentStepIndex = 0
                        UIApplication.shared.isIdleTimerDisabled = false
                    }) {
                        Text(lang.doneLabel).font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Color(hex: "#22d474")).cornerRadius(AppTheme.Radius.lg)
                    }
                }
                .padding(24)
                .background(Color(hex: "#0d1f16"))
                .cornerRadius(AppTheme.Radius.xl)
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.xl).stroke(Color(hex: "#22d474").opacity(0.4), lineWidth: 1.5))
                .shadow(color: Color(hex: "#22d474").opacity(0.25), radius: 24, y: 8)
                .padding(.horizontal, 32).padding(.bottom, 120)
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }

        if showingScaleAlert, isNavigating {
            VStack {
                Spacer()
                ScaleAlertBanner(
                    stationName: scaleAlertName.isEmpty ? lang.horizonGenericWeighStation : scaleAlertName,
                    distanceMiles: scaleAlertDistanceMiles,
                    status: scaleAlertStatus,
                    lang: lang,
                    onDismiss: { withAnimation { showingScaleAlert = false } },
                    provenance: scaleAlertProvenance,
                    communityHint: scaleAlertCommunityHint,
                    communitySummary: scaleAlertCommunitySummary,
                    onReport: { submitScaleReport($0) },
                    onMoreDetails: { openScaleDetailsSheet() }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, navigatingMapChromeBottomInset)
            }
            .zIndex(405)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Alert Overlays

    @ViewBuilder private var alertOverlays: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer().frame(height: isNavigating ? navigationTopChromeHeight : 110)

            // Restrições — só se houver alerta ativo; compacto
            if isNavigating, !restrictionWarningManager.activeWarnings.isEmpty {
                TruckRestrictionsOverlay(
                    warnings: restrictionWarningManager.activeWarnings,
                    currentLocation: locationManager.currentLocation,
                    dismissedWarningIds: Binding(
                        get: { restrictionWarningManager.dismissedWarningIds },
                        set: { restrictionWarningManager.dismissedWarningIds = $0 }
                    )
                )
                .frame(maxHeight: 72)
                .padding(.trailing, navigationRightRailWidth)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showingScaleAlert, !isNavigating {
                ScaleAlertBanner(stationName: scaleAlertName.isEmpty ? lang.horizonGenericWeighStation : scaleAlertName, distanceMiles: scaleAlertDistanceMiles,
                                 status: scaleAlertStatus, lang: lang,
                                 onDismiss: { withAnimation { showingScaleAlert = false } },
                                 provenance: scaleAlertProvenance,
                                 communityHint: scaleAlertCommunityHint,
                                 communitySummary: scaleAlertCommunitySummary,
                                 onReport: { submitScaleReport($0) },
                                 onMoreDetails: { openScaleDetailsSheet() })
                    .frame(maxWidth: 320)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showingSpeedComplianceAlert {
                SpeedComplianceBanner(message: speedComplianceMessage,
                                      onDismiss: { withAnimation { showingSpeedComplianceAlert = false } })
                    .frame(maxWidth: 340)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showingGradeAlert {
                GradeAlertBanner(message: gradeAlertMessage, isDescending: gradeIsDescending,
                                 onDismiss: { withAnimation { showingGradeAlert = false } })
                    .frame(maxWidth: 320)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showingCurveAlert {
                SharpCurveAlertBanner(onDismiss: { withAnimation { showingCurveAlert = false } })
                    .frame(maxWidth: 300)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showingWindAlert {
                WindAlertBanner(mph: windAlertMph, isGust: windAlertIsGust,
                                onDismiss: { withAnimation { showingWindAlert = false } })
                    .frame(maxWidth: 300)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.leading, AppTheme.Spacing.md)
        .zIndex(100)
        .animation(.spring(response: 0.35), value: showingScaleAlert)
        .animation(.spring(response: 0.35), value: showingSpeedComplianceAlert)
        .animation(.spring(response: 0.35), value: showingGradeAlert)
        .animation(.spring(response: 0.3), value: showingCurveAlert)
        .animation(.spring(response: 0.35), value: showingWindAlert)

        if showingDockFinder && !dockResults.isEmpty {
            VStack {
                Spacer()
                DockFinderPanel(results: dockResults,
                    onSelect: { item in calculateRoute(to: item.coordinate, address: item.name); showingDockFinder = false },
                    onDismiss: { withAnimation { showingDockFinder = false } })
                    .padding(.horizontal, AppTheme.Spacing.md).padding(.bottom, 200)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: showingDockFinder)
        }

        if showingTruckStops && !isNavigating {
            VStack {
                Spacer().frame(height: 190)
                TruckStopsPanel(stops: truckStopService.nearbyStops, hos: liveHOSState,
                    isLoading: truckStopService.isLoading, onClose: { showingTruckStops = false },
                    onSelect: { stop in selectedTruckStop = stop; showingTruckStopDetail = true })
                    .padding(.horizontal, AppTheme.Spacing.md)
                Spacer(minLength: 120)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35), value: showingTruckStops)
        }

        if let category = selectedNearbyCategory, !isNavigating {
            VStack {
                Spacer().frame(height: 190)
                HorizonNearbyStopsPanel(category: category, items: nearbyItems,
                    truckStops: truckStopService.nearbyStops, isLoading: isLoadingNearby,
                    onClose: { selectedNearbyCategory = nil; nearbyItems = [] },
                    onSelect: { item in selectedNearbyCategory = nil; calculateRoute(to: item.coordinate, address: item.name) },
                    lang: lang)
                    .padding(.horizontal, AppTheme.Spacing.md)
                Spacer(minLength: 120)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35), value: selectedNearbyCategory != nil)
        }

        if showingAIChat && !isNavigating {
            VStack {
                Spacer()
                HorizonAIChatPanel(messages: $aiChatMessages, inputText: $aiChatInput,
                    isStreaming: $aiIsStreaming, navigationContext: buildAINavigationContext(),
                    onRouteIntent: { handleAIRouteIntent($0) },
                    onClose: { withAnimation(.spring(response: 0.3)) { showingAIChat = false } })
                    .padding(.horizontal, 12).padding(.bottom, isNavigating ? 120 : 150)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35), value: showingAIChat)
        }
    }

    // MARK: - Map Controls Overlay

    @ViewBuilder private var mapControlsOverlay: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                if !isNavigating && showParkingPill {
                    horizonParkingPill
                        .padding(.leading, 12)
                        .padding(.bottom, idleMapControlsBottomInset)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                if !isNavigating {
                    VStack(spacing: 10) {
                        HorizonMapControlsPanel(
                            onZoomIn: { mapZoomIn?() }, onZoomOut: { mapZoomOut?() }, onRecenter: { mapRecenter?() }
                        )
                        Button(action: { withAnimation(.spring(response: 0.3)) { showingAIChat.toggle() } }) {
                            Image(systemName: "sparkles").font(.system(size: 17, weight: .semibold))
                                .foregroundColor(showingAIChat ? .white : Color(hex: "#c9a84c"))
                                .frame(width: 44, height: 44)
                                .background(showingAIChat ? Color(hex: "#c9a84c") : Color(hex: "#1a1a1f"))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: "#c9a84c").opacity(0.5), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, idleMapControlsBottomInset)
                }
            }
        }
        .zIndex(120)
        .sheet(isPresented: $showingStopsSheet) {
            StopsView().presentationDetents([.large]).preferredColorScheme(.dark)
        }
        .animation(.spring(response: 0.4), value: showParkingPill)
    }

    // MARK: - Warnings, Dispatch, ETA & Bottom Sheet

    @ViewBuilder private var warningsDispatchAndBottomOverlays: some View {
        // Truck Restriction Warnings
        if !truckWarnings.isEmpty && showingTruckWarnings && !isNavigating {
            VStack {
                Spacer().frame(height: 160)
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(AppTheme.Colors.warning)
                        Text(lang.truckRestrictionsOnRoute).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        Spacer()
                        Button(action: { showingTruckWarnings = false }) {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    ForEach(truckWarnings, id: \.id) { warning in
                        HStack(spacing: 10) {
                            Image(systemName: warningIcon(for: warning.type)).font(.system(size: 13))
                                .foregroundColor(AppTheme.Colors.warning).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.message).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                Text(warning.coordinate.map { String(format: "%.5f, %.5f", $0.latitude, $0.longitude) } ?? "Route warning")
                                    .font(.system(size: 11)).foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        Divider().background(AppTheme.Colors.backgroundCard)
                    }
                }
                .background(AppTheme.Colors.backgroundCard).cornerRadius(AppTheme.Radius.md)
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).stroke(AppTheme.Colors.warning.opacity(0.5), lineWidth: 1))
                .padding(.horizontal, AppTheme.Spacing.md)
                Spacer()
            }
        }

        // Dispatch Load Alert (fleet portal — hidden in driver beta)
        if dispatchDriverUIEnabled, showingDispatchAlert, let load = pendingDispatchLoad, !isNavigating {
            VStack {
                Spacer()
                HorizonDispatchLoadBanner(load: load, lang: lang) {
                    dispatchService.acknowledgeLoad(load) { _ in }
                    dispatchService.startRoute(for: load)
                    activeLoad = load; pendingDispatchLoad = nil; showingDispatchAlert = false
                    Task { @MainActor in await runQuantumBackedDispatchRoute(for: load) }
                } onDecline: {
                    pendingDispatchLoad = nil; showingDispatchAlert = false
                }
                .padding(.horizontal, AppTheme.Spacing.md).padding(.bottom, 120)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: showingDispatchAlert)
        }

        // Active Load Bar (hidden in driver beta)
        if dispatchDriverUIEnabled, let load = activeLoad, !showingDispatchAlert, !isNavigating {
            VStack {
                Spacer()
                HorizonActiveLoadBar(load: load, isPickedUp: loadPickedUp,
                    onFuelReport: { showingFuelReport = true },
                    onMarkPickedUp: {
                        let coord = locationManager.currentLocation?.coordinate
                            ?? activeRouteDestination
                            ?? load.destinationCoordinate
                        loadPickedUp = true
                        pendingFacilityVisit = PendingFacilityVisit(
                            load: load,
                            type: .pickup,
                            coordinate: coord,
                            arrivedAt: Date()
                        )
                    },
                    onMarkDelivered: {
                        dispatchService.markDelivered(load) { _ in }
                        pendingFacilityVisit = PendingFacilityVisit(
                            load: load,
                            type: .delivery,
                            coordinate: load.destinationCoordinate,
                            arrivedAt: Date()
                        )
                        activeLoad = nil
                        loadPickedUp = false
                    })
                    .padding(.horizontal, AppTheme.Spacing.md).padding(.bottom, 100)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35), value: activeLoad?.id)
        }

        if !isNavigating { bottomLeftOverlay }

        // Parking Crowdsource Banner
        if showingParkingPrompt, let stop = currentTruckStop {
            VStack {
                Spacer().frame(height: 170)
                HorizonTruckStopParkingBanner(stopName: stop.name) { status in
                    withAnimation { showingParkingPrompt = false }
                    let prefs = UserDefaults.standard
                    prefs.set(status.rawValue, forKey: "parking_\(stop.name)_\(Date().formatted(.dateTime.day().month()))")
                    submitParkingAvailability(status, for: stop)
                } onDismiss: {
                    withAnimation { showingParkingPrompt = false }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: showingParkingPrompt)
        }

        // Comida — só parado em posto reconhecido (Pilot, Love's, TA, etc.)
        if showingFoodSuggestion,
           let suggestion = foodSuggestion,
           let stop = currentTruckStop,
           stop.qualifiesAsFuelStopForFood,
           !isNavigating {
            VStack {
                Spacer()
                FoodSuggestionBanner(suggestion: suggestion, lang: lang) {
                    calculateRoute(to: suggestion.coordinate, address: suggestion.name)
                    showingFoodSuggestion = false
                } onDismiss: { showingFoodSuggestion = false }
                .padding(.horizontal, AppTheme.Spacing.md).padding(.bottom, 120)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: showingFoodSuggestion)
        }

        // ━━━ Bottom chrome idle (toolbar + sheet = um bloco) ━━━
        if !isNavigating {
            VStack(spacing: 0) {
                Spacer().allowsHitTesting(false)
                if isIdleBottomSheetReady {
                    idleBottomChrome
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(hex: "#0d1117"))
                        .frame(height: idleCollapsedChromeHeight)
                        .padding(.horizontal, GPSDesignSystem.Metrics.screenHorizontalInset)
                        .padding(.bottom, mainTabBarClearance)
                }
            }
            .id("idle-mode-overlay")
        }
    }

    /// Painel único no mapa parado — evita toolbar flutuando em cima do sheet.
    @ViewBuilder private var idleBottomChrome: some View {
        VStack(spacing: 0) {
            HorizonGPSToolbar(
                lang: lang,
                embeddedInChrome: true,
                onDirections: {
                    bottomSheetExpanded = true
                    showingGlobalSearch = true
                },
                onPlaces: { showingTruckStops = true },
                onWeighStation: { showingWeighStation = true },
                onRestAreas: { selectedNearbyCategory = .rest },
                onRouteOptions: {
                    if routeEasyPendingCoordinate != nil, !routeEasyOptions.isEmpty {
                        showingRouteEasyPicker = true
                    } else {
                        bottomSheetExpanded = true
                    }
                },
                onWeather: { showingWeather = true },
                onCommunity: { showingAIChat = true },
                onTrafficMap: { selectedMapStyle = .hybrid }
            )
            .padding(.horizontal, 8)
            .padding(.top, 8)

            HorizonBottomSheet(
                locationManager: locationManager, activeTrip: activeTrip,
                isCalculatingRoute: $isCalculatingRoute, isNavigating: false,
                distanceMeters: activeDistanceMeters, durationSeconds: activeDurationSeconds,
                isExpanded: $bottomSheetExpanded,
                region: regionalSettings.currentRegion, lang: lang,
                onCenterLocation: {},
                onCalculateRoute: { address in calculateRoute(to: address) },
                onCalculateRouteToCoordinate: { coordinate, name in calculateRoute(to: coordinate, address: name) },
                onSelectCategory: { category in selectedNearbyCategory = category },
                onClearRoute: { truckRoute = nil; route = nil },
                showingShareTrip: $showingShareTrip,
                loadPickupAddress: $loadPickupAddress,
                loadDropoffAddress: $loadDropoffAddress,
                loadCargoOnBoard: $loadCargoOnBoard,
                isAnalyzingLoadRoute: isAnalyzingLoadRoute,
                onAnalyzeLoadRoute: {
                    let dropoff = loadDropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !dropoff.isEmpty else { return }
                    isAnalyzingLoadRoute = true
                    calculateRoute(to: dropoff)
                    isAnalyzingLoadRoute = false
                },
                unifiedChrome: true,
                onRouteIntent: { handleAIRouteIntent($0) }
            )
        }
        .frame(height: idleBottomSheetHeight, alignment: .top)
        .clipped()
        .background(GPSDesignSystem.Colors.chromeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: -2)
        .padding(.horizontal, GPSDesignSystem.Metrics.screenHorizontalInset)
        .padding(.bottom, mainTabBarClearance)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: bottomSheetExpanded)
        .id("idle-bottom-chrome")
        .allowsHitTesting(true)
    }

    // MARK: - ETA Bar (navigation, OPAQUE solid background)

    private var navigationRoadLine: String {
        let road = navCurrentRoadName
        let regionTag: String = {
            switch regionalSettings.currentRegion {
            case .usa: return "US"
            case .canada: return "CA"
            case .mexico: return "MX"
            default: return regionalSettings.currentRegion.rawValue
            }
        }()
        if road.isEmpty {
            return truckRoute?.destinationName ?? route?.name ?? regionTag
        }
        return "\(road) • \(regionTag)"
    }

    private var navCurrentRoadName: String {
        guard !routeSteps.isEmpty, currentStepIndex < routeSteps.count else { return "" }
        let step = routeSteps[currentStepIndex]
        let raw = step.instructions
        let lower = raw.lowercased()
        for keyword in [" onto ", " on ", " para "] {
            if let range = lower.range(of: keyword) {
                return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return raw
    }

    private var navRoadNameBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "road.lanes")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppTheme.Colors.accent)
            Text(navCurrentRoadName)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            if let dest = truckRoute?.destinationName ?? route?.name, !dest.isEmpty {
                Text("·")
                    .foregroundColor(Color.white.opacity(0.4))
                Text(dest)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(hex: "#0d1117").opacity(0.95))
    }

    private var etaBar: some View {
        HStack(spacing: 12) {
            Button(action: { showingShareTrip = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("Tap to Chat")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(hex: "#1f2937"))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatNavDuration(activeDurationSeconds))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white).lineLimit(1)
                Text(regionalSettings.formatDistance(activeDistanceMeters))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                Text(formatArrivalClock())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#9ca3af"))
            }
            if let toll = currentTollResult {
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: toll.hasTolls ? "dollarsign.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(toll.hasTolls ? Color(hex: "#f59e0b") : Color(hex: "#22c55e"))
                        Text(toll.formattedShort).font(.system(size: 12, weight: .bold))
                            .foregroundColor(toll.hasTolls ? Color(hex: "#f59e0b") : Color(hex: "#22c55e"))
                    }
                    Text("Tolls").font(.system(size: 9, weight: .medium)).foregroundColor(AppTheme.Colors.textSecondary)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if let diesel = publicDieselPrice {
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        
                        Image(systemName: "fuelpump.fill").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "#3b82f6"))
                        Text(String(format: "%@%.2f", diesel.currencyCode == "USD" ? "$" : "", diesel.dieselPrice))
                            .font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "#3b82f6"))
                    }
                    Text(diesel.unitLabel).font(.system(size: 9, weight: .medium)).foregroundColor(AppTheme.Colors.textSecondary)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if let profit = currentProfitability {
                let netColor: Color = profit.netProfitUSD >= 0 ? Color(hex: "#22c55e") : Color(hex: "#ef4444")
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: profit.netProfitUSD >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(netColor)
                        Text(profit.formatted.net).font(.system(size: 12, weight: .bold)).foregroundColor(netColor)
                    }
                    Text("Net est.").font(.system(size: 9, weight: .medium)).foregroundColor(AppTheme.Colors.textSecondary)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            Spacer()
            if dispatchDriverUIEnabled {
                Button(action: { showingDispatchAlert = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "ellipsis.circle.fill").font(.system(size: 12, weight: .bold))
                        Text("More").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#1f2937"))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            Button(action: {
                var t = Transaction(animation: nil); t.disablesAnimations = true
                withTransaction(t) { truckRoute = nil; route = nil }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13, weight: .bold))
                    Text("Stop").font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color(hex: "#ef4444")).cornerRadius(12)
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 34)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "#0d1117"))
                .shadow(color: .black.opacity(0.4), radius: 12, y: -4)
        )
        .onAppear {
        }
        .animation(.spring(response: 0.4), value: currentTollResult != nil)
    }

    // MARK: - Bottom-Left Overlay (idle only)

    @ViewBuilder private var bottomLeftOverlay: some View {
        VStack {
            Spacer().allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if showDataDiagnostics {
                        DataPipelineDiagnosticsCard(locationManager: locationManager,
                            fleetTelemetryService: fleetTelemetryService,
                            jurisdictionPolicyService: jurisdictionPolicyService,
                            operationalFeedService: operationalFeedService,
                            integrationHealth: integrationHealthResults,
                            onClose: { showDataDiagnostics = false })
                            .frame(maxWidth: 300)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .task {
                                guard !integrationHealthChecked else { return }
                                integrationHealthChecked = true
                                integrationHealthResults = await IntegrationsHealthCheck.runAll()
                            }
                    }
                    if showingWeather, let weather = weatherService.currentWeather {
                        WeatherPanel(weather: weather) { showingWeather = false }
                            .frame(maxWidth: 280)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.spring(response: 0.4), value: showingWeather)
                    }
                    if showingCheapestDiesel, let dieselStop = cheapestDieselStop {
                        CheapestDieselBanner(stop: dieselStop, lang: lang) {
                            showingCheapestDiesel = false
                            calculateRoute(to: dieselStop.coordinate, address: dieselStop.address)
                        }
                        .frame(maxWidth: 300)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let publicDieselPrice {
                        HStack(spacing: 10) {
                            GPSFuelMarkerView(price: publicDieselPrice.dieselPrice, isDeal: true, size: 44)
                            DieselMarketBanner(pricePoint: publicDieselPrice) { showingTruckStops = true }
                        }
                        .frame(maxWidth: 300)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.leading, AppTheme.Spacing.md).padding(.bottom, 120)
                Spacer()
            }
        }
    }

    // MARK: - Route / HOS sync

    private func handleRouteStateChange(hasRoute: Bool) {
        if hasRoute {
            hosContext.beginRouteSession(estimatedDrivingSeconds: activeDurationSeconds)
        } else if truckRoute == nil && route == nil {
            routeSteps = []
            currentStepIndex = 0
            showingSteps = false
        }
    }

    private func handleTruckRouteStateChange(hasRoute: Bool) {
        if hasRoute {
            hosContext.beginRouteSession(estimatedDrivingSeconds: activeDurationSeconds)
        } else if truckRoute == nil && route == nil {
            routeSteps = []
            currentStepIndex = 0
            showingSteps = false
            currentTollResult = nil
            currentProfitability = nil
        }
    }

    // MARK: - Navigation mode

    private func handleNavigationModeChange(_ navigating: Bool) {
        UIApplication.shared.isIdleTimerDisabled = navigating
        locationManager.setNavigationMode(navigating)
        if !navigating {
            lastScaleVoiceKey = nil
            scaleAlertNotifiedTierKeys.removeAll()
            routeSignageService.clear()
            hosContext.endRouteSession()
            return
        }
        // P0 #5: navegação com a tela bloqueada / app em 2º plano só recebe GPS com permissão
        // "Sempre". Se está só em "Quando em uso", o boneco congela ao bloquear a tela. Escala
        // AGORA (início da rota) — é o momento em que o 2º plano passa a importar.
        if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestPermission()
        }
        bottomSheetExpanded = false
        showingAIChat = false
        showingSteps = false
        showingTruckStops = false
        selectedNearbyCategory = nil
        showingDispatchAlert = false
        showingRouteError = false
        routeError = nil
        // Do not switch Mapbox style mid-navigation — triggers "Updated style is ignored"
        // and clears route polyline annotations on device.
        hosContext.beginRouteSession(estimatedDrivingSeconds: activeDurationSeconds)
        guard let loc = locationManager.currentLocation else { return }
        Task {
            await truckStopService.searchNearby(location: loc)
            await MainActor.run {
                truckStopService.applyOperationalSignals(operationalFeedService.parkingSignals)
                checkForNearbyScales(from: loc)
            }
        }
    }

    // MARK: - Location Update Handler

    private func handleLocationUpdate() {
        guard let loc = locationManager.currentLocation else { return }
        let now = Date()
        let gpsSpeedMph = max(0, loc.speed * 2.23694)

        navigationEngine.updateLocation(loc)
        restrictionWarningManager.updateLocation(loc)
        truckWarnings = restrictionWarningManager.activeWarnings
        if isNavigating, let coords = truckRoute?.coordinates, coords.count >= 2 {
            routeSignageService.refresh(location: loc, routeCoordinates: coords)
        }
        evaluateTruckSpeedCompliance(using: loc)
        evaluateGeofenceEvents(using: loc)
        hosContext.feedSpeed(fleetTelemetryService.preferredSpeedMph(gpsSpeedMph: gpsSpeedMph))
        evaluateHosEtaAdvisory(now: now)

        // Consolida HOS + navegação + restrições num NavigationState único (montador,
        // sem efeito colateral — lê o que já foi atualizado acima). Em DEBUG, loga no console.
        telemetryEngine.assemble(hos: hosContext, nav: navigationEngine, warnings: truckWarnings)

        #if DEBUG
        if !HorizonViewFirstGpsFixLogged.didLog,
           loc.horizontalAccuracy > 0, loc.horizontalAccuracy < 80 {
            HorizonViewFirstGpsFixLogged.didLog = true
            print("[HorizonGPS] firstFix acc=\(Int(loc.horizontalAccuracy))m speedMph=\(Int(gpsSpeedMph)) bearing=\(Int(locationManager.bestBearing))°")
        }
        #endif

        let shouldRefreshOps: Bool = {
            guard now.timeIntervalSince(lastOpsRefreshAt) >= 10 else { return false }
            guard let last = lastOpsRefreshLocation else { return true }
            return loc.distance(from: last) >= 250
        }()
        if shouldRefreshOps {
            lastOpsRefreshAt = now
            lastOpsRefreshLocation = loc
            Task {
                await fleetTelemetryService.refreshIfNeeded()
                await countryCompliance.refreshIfNeeded(for: loc)
                await jurisdictionPolicyService.refreshIfNeeded(for: loc)
                await operationalFeedService.refreshIfNeeded(for: loc.coordinate)
                await MainActor.run {
                    syncRegionalPolicyFromLocation()
                    operationalFeedService.applyWeighSignals()
                }
            }
        }

        let shouldRefreshExternal: Bool = {
            guard now.timeIntervalSince(lastExternalRefreshAt) >= 30 else { return false }
            guard let last = lastExternalRefreshLocation else { return true }
            return loc.distance(from: last) >= 1000
        }()
        if shouldRefreshExternal {
            lastExternalRefreshAt = now
            lastExternalRefreshLocation = loc
            Task {
                await weatherService.refresh(for: loc.coordinate)
                await logisticsNewsService.refresh(for: loc.coordinate)
                let publicPrice = await FuelPriceService.shared.fetchPublicDieselPrice(for: regionalSettings.currentRegion)
                let edgeLimit = await ValhallaRoutingService.shared.fetchEdgeSpeedLimitKmh(at: loc.coordinate)
                await MainActor.run {
                    publicDieselPrice = publicPrice
                    currentEdgeSpeedLimitKmh = edgeLimit
                    if weatherService.currentWeather != nil && !weatherShownThisLaunch {
                        weatherShownThisLaunch = true
                        showingWeather = true
                    }
                }
            }
        }

        let shouldRefresh: Bool
        if truckStopService.nearbyStops.isEmpty {
            // Lista vazia: re-tenta no máximo 1x/min (cooldown) em vez de a cada tick de GPS.
            shouldRefresh = now.timeIntervalSince(lastNearbySearchAttemptAt) >= 60
        }
        else if let last = lastScaleCheckLocation, loc.distance(from: last) > (isNavigating ? 2_000 : 16_000) { shouldRefresh = true }
        else { shouldRefresh = false }
        if shouldRefresh {
            lastNearbySearchAttemptAt = now
            lastScaleCheckLocation = loc
            Task {
                await truckStopService.searchNearby(location: loc)
                await MainActor.run {
                    truckStopService.applyOperationalSignals(operationalFeedService.parkingSignals)
                    updateCheapestDiesel(); checkForNearbyScales(from: loc); refreshNearestParking(from: loc)
                }
            }
        }

        if isNavigating, now.timeIntervalSince(lastWeighCrowdSyncAt) >= 90 {
            lastWeighCrowdSyncAt = now
            Task {
                await WeighStationStatusService.shared.fetchRemoteReports(near: loc.coordinate, radiusKm: 120)
            }
        }

        let speed = max(0, loc.speed)
        checkTruckStopProximity(from: loc, speed: speed)
        checkFacilityVisitDeparture(from: loc)
        announceNavTruckFuelEtasIfNeeded(location: loc, speed: speed, now: now)
        #if canImport(MapboxMaps)
        if isNavigating { OfflineRouteTileManager.shared.refreshAheadWindow(from: loc.coordinate) }
        #endif
        appendLocationHistorySample(loc, now: now)
        checkGradeAlert(from: loc); checkSharpCurveAlert(at: loc); checkWindAlert()
        if isNavigating { checkDestinationDock(from: loc) }
    }

    /// Keeps a short trail for grade/curve heuristics without recording every Core Location callback.
    private func appendLocationHistorySample(_ loc: CLLocation, now: Date) {
        if let prev = lastLocationHistorySample {
            let dt = now.timeIntervalSince(lastLocationHistorySampleAt)
            let moved = loc.distance(from: prev) >= 38
            guard dt >= 1.05 || moved else { return }
        }
        lastLocationHistorySampleAt = now
        lastLocationHistorySample = loc
        locationHistory.append(loc)
        let cap = 20
        if locationHistory.count > cap {
            locationHistory.removeFirst(locationHistory.count - cap)
        }
    }

    // MARK: - ETA × HOS (diferencial: "você chega dentro das suas horas?")

    /// Compara o ETA da navegação com as horas de direção DOT restantes e anuncia por voz:
    /// confortável ("chega 1h12 antes do limite"), apertado (<30min de folga) ou estouro
    /// (alerta + aviso visual). Fala só quando o nível MUDA — sem tagarelar na cabine.
    private func evaluateHosEtaAdvisory(now: Date) {
        guard isNavigating else { return }
        guard hosContext.status == .driving else { return }   // só com o timer DOT rodando
        guard now.timeIntervalSince(lastHosEtaCheckAt) >= 60 else { return }
        lastHosEtaCheckAt = now

        let etaSeconds = navigationEngine.timeRemaining > 0
            ? navigationEngine.timeRemaining
            : activeDurationSeconds
        guard etaSeconds > 60 else { return }

        // Mantém o ETA vivo no contexto DOT: o chip DOT (barra inferior + pill) muda de cor
        // (verde → âmbar → vermelho) quando a chegada estoura o limite de direção. Sem modal.
        hosContext.beginRouteSession(estimatedDrivingSeconds: etaSeconds)

        let margin = hosContext.drivingRemaining - etaSeconds
        let level = margin <= 0 ? 2 : (margin < 1800 ? 1 : 0)
        guard hosEtaAnnouncedLevel != level else { return }
        hosEtaAnnouncedLevel = level

        let minutes = max(1, Int(abs(margin) / 60))
        let phrase: String
        switch level {
        case 2: phrase = lang.hosEtaOverPhrase(shortByMinutes: minutes)
        case 1: phrase = lang.hosEtaTightPhrase(spareMinutes: minutes)
        default: phrase = lang.hosEtaComfortablePhrase(spareMinutes: minutes)
        }
        VoiceNavigationManager.shared.announceHosEta(phrase, lang: lang)
        // Sem pop-up: a violação prevista aparece de forma discreta no chip DOT
        // (cor vermelha via DotHosContext.barColor) e nos detalhes do DotHosDetailSheet.
        #if DEBUG
        print("[HOS-ETA] level=\(level) marginMin=\(Int(margin / 60)) etaMin=\(Int(etaSeconds / 60))")
        #endif
    }

    // MARK: - Route Calculation

    /// Accept dispatch: optional `POST /v1/optimize` then same road-geometry stack as manual search.
    @MainActor
    private func runQuantumBackedDispatchRoute(for load: DispatchedLoad) async {
        guard let origin = locationManager.currentLocation else {
            routeError = lang.horizonRouteErrorLocationUnavailable
            showingRouteError = true
            return
        }

        isCalculatingRoute = true
        bottomSheetExpanded = false
        defer { isCalculatingRoute = false }

        var optimizeResponse: RouteOptimizeResponseDTO?
        if QuantumRouteOptimizationClient.shared.isConfigured, let trip = activeTrip {
            do {
                let built = try await RouteOptimizePayloadBuilder.build(
                    load: load,
                    trip: trip,
                    truckProfile: truckProfile,
                    currentLocation: origin,
                    loadPickedUp: loadPickedUp
                )
                let resp = try await QuantumRouteOptimizationClient.shared.optimize(built.request)
                optimizeResponse = resp
                persistRouteOptimizeResponse(resp, trip: trip, load: load)
                #if DEBUG
                print("[Quantum] optimize OK solver=\(resp.solverUsed) status=\(resp.status)")
                #endif
            } catch {
                #if DEBUG
                print("[Quantum] POST /v1/optimize skipped or failed: \(error.localizedDescription)")
                #endif
            }
        }

        do {
            let routing = RoutingService.shared
            let result = try await routing.calculateTruckRoute(
                from: origin,
                to: load.destinationCoordinate,
                destinationName: load.destinationAddress,
                profile: truckProfile,
                accessMode: routingAccessMode
            )
            var finalRoute = result
            if let resp = optimizeResponse, resp.status != "error", !resp.orderedLocationIds.isEmpty {
                finalRoute = result.withQuantumOptimization(from: resp)
            }
            if AppAccessPolicy.enforceTruckOnlyRouting, !routing.lastProvider.isTruckAware {
                bottomSheetExpanded = false
                routeError = lang.horizonRouteErrorValhallaUnavailable
                showingRouteError = true
                return
            }
            applyRoute(finalRoute, suppressUIErrors: false, destinationCoordinate: load.destinationCoordinate)
        } catch {
            bottomSheetExpanded = false
            routeError = lang.horizonRoutingFailureMessage(error)
            showingRouteError = true
        }
    }

    @MainActor
    private func persistRouteOptimizeResponse(_ resp: RouteOptimizeResponseDTO, trip: Trip, load: DispatchedLoad) {
        trip.lastRouteOptimizeRequestId = resp.requestId
        trip.lastRouteOptimizeLoadId = load.id
        trip.lastRouteOptimizeAt = Date()
        trip.lastRouteOptimizeSolverUsed = resp.solverUsed
        if let m = resp.metrics {
            trip.lastRouteOptimizeKmSavedApprox = m.approxKmSaved
            trip.lastRouteOptimizeKmBaselineApprox = m.approxKmBaselineManualOrder
            trip.lastRouteOptimizeKmOptimizedApprox = m.approxKmOptimizedOrder
        }
        try? modelContext.save()
    }

    private func calculateRoute(to coordinate: CLLocationCoordinate2D, address: String) {
        let isReroute = isNavigating // If already navigating, this is a reroute
        // Parte da MELHOR localização disponível (incl. A-GPS/cached) — nunca trava esperando um
        // GPS "perfeito" (igual Google/Apple Maps). O fix preciso chega e o nav se ajusta sozinho.
        guard let origin = locationManager.currentLocation else {
            if !isReroute { routeError = lang.horizonRouteErrorLocationUnavailable; showingRouteError = true }
            return
        }
        if !isReroute {
            let key = [
                String(format: "%.5f,%.5f", origin.coordinate.latitude, origin.coordinate.longitude),
                String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude),
                address
            ].joined(separator: "|")
            let now = Date()
            if key == lastIdleRouteDedupeKey, now.timeIntervalSince(lastIdleRouteDedupeAt) < 2.0 {
                #if DEBUG
                print("[Route] SKIP duplicate coordinate route within 2s → \(address)")
                #endif
                return
            }
            lastIdleRouteDedupeKey = key
            lastIdleRouteDedupeAt = now
        }
        if !isReroute { isCalculatingRoute = true; bottomSheetExpanded = false }
        #if DEBUG
        print("[Route] \(isReroute ? "REROUTE" : "NEW") → \(address) from \(String(format: "%.5f,%.5f", origin.coordinate.latitude, origin.coordinate.longitude))")
        #endif
        if isReroute {
            // Dirigindo: reroute silencioso, rota única (não abre seletor no meio da viagem).
            runSingleTruckRoute(from: origin, to: coordinate, address: address, isReroute: true)
        } else {
            // Rota inicial: monta e apresenta os 3 modos (Rápida / Sem Pedágio / Easy-AI).
            runRouteEasyPlanning(from: origin, to: coordinate, address: address)
        }
    }

    private func calculateRoute(to address: String) {
        let isReroute = isNavigating
        guard let origin = locationManager.currentLocation else {
            if !isReroute { routeError = lang.horizonRouteErrorLocationUnavailable; showingRouteError = true }
            return
        }
        if !isReroute {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = [
                String(format: "%.5f,%.5f", origin.coordinate.latitude, origin.coordinate.longitude),
                "geocode",
                trimmed
            ].joined(separator: "|")
            let now = Date()
            if key == lastIdleRouteDedupeKey, now.timeIntervalSince(lastIdleRouteDedupeAt) < 2.0 {
                #if DEBUG
                print("[Route] SKIP duplicate address route within 2s → '\(trimmed)'")
                #endif
                return
            }
            lastIdleRouteDedupeKey = key
            lastIdleRouteDedupeAt = now
        }
        if !isReroute { isCalculatingRoute = true; bottomSheetExpanded = false }
        #if DEBUG
        print("[Route] \(isReroute ? "REROUTE" : "NEW") → '\(address)'")
        #endif
        Task {
            let reroute = isReroute
            do {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = address
                request.resultTypes = [.pointOfInterest, .address]
                request.region = MKCoordinateRegion(
                    center: origin.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
                )
                var response = try await MKLocalSearch(request: request).start()
                if response.mapItems.isEmpty {
                    let fallbackRequest = MKLocalSearch.Request()
                    fallbackRequest.naturalLanguageQuery = address
                    fallbackRequest.resultTypes = [.pointOfInterest, .address]
                    response = try await MKLocalSearch(request: fallbackRequest).start()
                }
                let sortedByDistance = response.mapItems.sorted {
                    origin.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)) < origin.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
                }
                guard let first = sortedByDistance.first else {
                    throw RoutingServiceError.geocodeFailed(address)
                }
                let destinationName = first.name ?? address
                let destinationDistance = origin.distance(from: CLLocation(latitude: first.placemark.coordinate.latitude, longitude: first.placemark.coordinate.longitude))
                guard destinationDistance < 1_500_000 else {
                    throw RoutingServiceError.geocodeFailed("Destination too far from current location (\(Int(destinationDistance/1000)) km)")
                }
                let coord = first.placemark.coordinate
                await MainActor.run {
                    if reroute {
                        runSingleTruckRoute(from: origin, to: coord, address: destinationName, isReroute: true)
                    } else {
                        runRouteEasyPlanning(from: origin, to: coord, address: destinationName)
                    }
                }
            } catch {
                await MainActor.run {
                    if !reroute { isCalculatingRoute = false }
                    if reroute {
                        #if DEBUG
                        print("[Route] ⚠️ Reroute failed (keeping current route): \(error.localizedDescription)")
                        #endif
                        if case RoutingServiceError.allProvidersFailed = error {
                            lastRerouteAt = Date().addingTimeInterval(150)
                        }
                    } else {
                        bottomSheetExpanded = false
                        if let parsed = parseCoordinateAddress(address) {
                            routeError = lang.horizonRouteErrorAddressNoSafeRoute
                            showingRouteError = true
                            #if DEBUG
                            print("[Route] Parsed coordinate route blocked for safety: \(parsed.latitude),\(parsed.longitude)")
                            #endif
                        } else {
                            routeError = lang.horizonRouteErrorCouldNotResolveAddress
                            showingRouteError = true
                        }
                    }
                }
            }
        }
    }

    private func emergencyDirectRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String
    ) -> TruckRoute {
        let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destLoc = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distanceMeters = max(originLoc.distance(from: destLoc), 10)
        let durationSeconds = distanceMeters / 22.352

        let pointCount = max(10, Int(distanceMeters / 1000))
        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(pointCount + 1)
        for i in 0...pointCount {
            let fraction = Double(i) / Double(pointCount)
            let lat = origin.latitude + fraction * (destination.latitude - origin.latitude)
            let lon = origin.longitude + fraction * (destination.longitude - origin.longitude)
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        let steps = [
            RouteStep(
                instruction: lang.horizonNavigateToDestination(destinationName),
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                maneuver: "continue"
            )
        ]

        return TruckRoute(
            coordinates: coordinates,
            steps: steps,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            destinationName: destinationName,
            truckNotices: [TruckRouteNotice(code: "EMERGENCY", title: lang.horizonEmergencyRouteTitle, details: lang.horizonEmergencyRouteDetails)]
        )
    }

    @MainActor
    private func syncNavigationStepIndexFromUI(_ newIndex: Int) {
        currentStepIndex = newIndex
        navigationEngine.syncStepIndexFromUI(newIndex)
    }

    // MARK: - Apply Route (FIX #3: validates before applying)

    @MainActor
    private func applyRoute(
        _ result: TruckRoute,
        suppressUIErrors: Bool = false,
        destinationCoordinate: CLLocationCoordinate2D? = nil
    ) {
        #if DEBUG
        print("[ApplyRoute] ✅ coords=\(result.coordinates.count), steps=\(result.steps.count), dist=\(Int(result.distanceMeters))m, name='\(result.destinationName)'")
        #endif
        for (i, s) in result.steps.prefix(5).enumerated() {
            #if DEBUG
            print("[ApplyRoute]   step[\(i)]: '\(s.instruction)' maneuver='\(s.maneuver)' dist=\(Int(s.distanceMeters))m")
            #endif
        }

        if !suppressUIErrors {
            routeError = nil
            showingRouteError = false
        }

        guard !result.coordinates.isEmpty else {
            if suppressUIErrors {
                #if DEBUG
                print("[ApplyRoute] ⚠️ Suppressed error: route has no coordinates")
                #endif
                return
            }
            routeError = lang.horizonRouteErrorNoCoordinates; showingRouteError = true; return
        }
        guard result.distanceMeters > 0 else {
            if suppressUIErrors {
                #if DEBUG
                print("[ApplyRoute] ⚠️ Suppressed error: route distance is zero")
                #endif
                return
            }
            routeError = lang.horizonRouteErrorZeroDistance; showingRouteError = true; return
        }

        // Filter steps once — UI and NavigationEngine must share the same indices.
        let (steps, engineSteps) = Self.filteredNavigationSteps(from: result, lang: lang)

        print("[ApplyRoute] ✅ navigation ON · steps=\(steps.count) · \(Int(result.distanceMeters))m · '\(result.destinationName)'")
        #if DEBUG
        for (i, s) in engineSteps.prefix(5).enumerated() {
            print("[ApplyRoute]   step[\(i)]: '\(s.instruction)' maneuver='\(s.maneuver)' dist=\(Int(s.distanceMeters))m")
        }
        #endif

        let routeForNavigation = TruckRoute(
            coordinates: result.coordinates,
            steps: engineSteps,
            distanceMeters: result.distanceMeters,
            durationSeconds: result.durationSeconds,
            destinationName: result.destinationName,
            truckNotices: result.truckNotices,
            provenance: result.provenance,
            tollCostUSD: result.tollCostUSD,
            tollCurrency: result.tollCurrency,
            tollPoints: result.tollPoints
        )

        var t = Transaction(animation: nil); t.disablesAnimations = true
        withTransaction(t) {
            bottomSheetExpanded = false; showingSteps = false
            truckRoute = routeForNavigation; route = nil
            routeSteps = steps; currentStepIndex = 0
        }
        #if DEBUG
        print("[TRACE-NAV] 9 · transaction OK (truckRoute setado)")
        #endif
        activeRouteDestination = destinationCoordinate ?? result.coordinates.last
        #if canImport(MapboxMaps)
        // Offline C3 — baixa tiles do corredor (visão geral + janela à frente) ao aplicar a rota.
        // Só com rede: offline o download falharia em silêncio e enfileiraria lixo no Mapbox
        // (acontece no switch offline pra alternativa do corredor — os tiles já vieram online).
        if MapProviderConfig.isMapboxHorizonRendererEnabled, result.coordinates.count >= 2,
           NetworkReachability.shared.isOnline {
            OfflineRouteTileManager.shared.cacheRoute(coordinates: result.coordinates, style: selectedMapStyle.mapboxStyleURI)
        }
        #endif
        #if DEBUG
        print("[TRACE-NAV] 10 · tiles offline despachados")
        #endif
        showingFallbackConfirmation = false
        pendingFallbackRoute = nil
        pendingFallbackProvider = .unknown

        let provider = RoutingService.shared.lastProvider
        lastRoutingProvider = provider; dockCheckDone = false
        navigationEngine.language = lang
        navigationEngine.startNavigation(route: routeForNavigation)
        // startNavigation reseta o passo p/ 0. Se isto é uma TROCA de rota no meio da viagem
        // (reroute / switch offline do corredor), alimenta a posição atual JÁ — o engine acha o
        // ponto mais próximo mid-rota e corrige o passo no mesmo ciclo, sem anunciar o passo 0 errado.
        if let loc = locationManager.currentLocation {
            navigationEngine.updateLocation(loc)
        }
        #if DEBUG
        print("[TRACE-NAV] 11 · navigationEngine ligado")
        #endif
        VoiceNavigationManager.shared.resetForNewRoute()
        // ETA × HOS: nova rota = re-anuncia o status das horas na primeira avaliação.
        hosEtaAnnouncedLevel = nil
        lastHosEtaCheckAt = .distantPast
        #if DEBUG
        print("[TRACE-NAV] 12 · voz resetada")
        #endif
        lastNavFuelEtaVoiceAt = .distantPast
        UIApplication.shared.isIdleTimerDisabled = true
        mapRecenter?()
        #if DEBUG
        print("[TRACE-NAV] 13 · recenter OK")
        #endif

        // Toll data
        let distanceM = result.distanceMeters
        let freightVal = activeLoad?.valorFrete ?? 0
        let tollResult = TollResult(totalCost: result.tollCostUSD, currency: result.tollCurrency, tolls: result.tollPoints)
        currentTollResult = tollResult.hasTolls ? tollResult : TollResult.zero

        let dieselPrice = publicDieselPrice?.dieselPrice ?? 3.85
        let mpg: Double = (truckProfile.truckType == .straight) ? 10.0 : 6.5
        let fuelCost = TripProfitability.estimateFuelCost(distanceMeters: distanceM, mpg: mpg, dieselPricePerGallon: dieselPrice)
        if freightVal > 0 {
            currentProfitability = TripProfitability(freightValueUSD: freightVal, estimatedFuelCostUSD: fuelCost, tollCostUSD: result.tollCostUSD, otherExpensesUSD: 0)
        }

        // Load truck restriction warnings
        if let userLocation = locationManager.currentLocation {
            Task { @MainActor in
                let effectiveProfile = jurisdictionPolicyService.effectiveRegulationProfile(base: countryCompliance.regulationProfile)
                await restrictionWarningManager.loadWarnings(from: result, userLocation: userLocation,
                    specs: truckProfile.toSpecifications(), regulations: effectiveProfile)
                truckWarnings = restrictionWarningManager.activeWarnings
            }
        }

        // Navigation callbacks
        navigationEngine.onStepChanged = { stepIndex, step in
            currentStepIndex = stepIndex
        }
        navigationEngine.onNeedsReroute = {
            // Fase 1 offline: sem sinal, recalcular ia falhar (timeout) e penalizar 2.5min com
            // passos errados. Em vez disso MANTEM a rota em cache ativa e re-arma a deteccao — o
            // snap do NavigationEngine continua guiando o motorista de volta a rota (corredor).
            // Honesto e sem thrash. (cancelPendingReroute = re-arma + restaura a linha da rota.)
            if !NetworkReachability.shared.isOnline {
                // Fase 1.2b: offline, tenta trocar pra a alternativa do corredor MAIS PERTO do
                // motorista (sem rede — já está em cache). Reusa applyRoute (mesmo caminho do
                // reroute online). COOLDOWN obrigatório: applyRoute reseta passo/voz e dispara
                // tasks — sem o cooldown isto dispararia a cada ciclo de detecção (thrash). Só
                // troca 1x/30s e se a alternativa for nitidamente mais perto (>120m, anti-flap
                // do ruído de GPS). Senão, mantém a rota e re-arma (comportamento 1.3).
                if Date().timeIntervalSince(lastRerouteAt) > 30,
                   let driver = locationManager.currentLocation,
                   let active = truckRoute, !active.corridorAlternates.isEmpty {
                    let activeDist = minDistanceToRoute(driver, active.coordinates)
                    let scored = active.corridorAlternates.enumerated()
                        .map { (idx: $0.offset, route: $0.element, dist: minDistanceToRoute(driver, $0.element.coordinates)) }
                    if let best = scored.min(by: { $0.dist < $1.dist }), best.dist + 120 < activeDist {
                        lastRerouteAt = Date()   // trava o switch por 30s (anti-thrash)
                        #if DEBUG
                        print("[Route] Reroute OFFLINE → troca p/ alternativa do corredor (\(Int(best.dist))m vs principal \(Int(activeDist))m)")
                        #endif
                        var chosen = best.route
                        // preserva as opções: demais alternativas + a principal antiga (sem aninhar corredor).
                        var remaining = active.corridorAlternates.enumerated().filter { $0.offset != best.idx }.map { $0.element }
                        var oldPrimary = active; oldPrimary.corridorAlternates = []
                        remaining.append(oldPrimary)
                        chosen.corridorAlternates = remaining
                        applyRoute(chosen, suppressUIErrors: true, destinationCoordinate: activeRouteDestination)
                        return
                    }
                }
                #if DEBUG
                print("[Route] Reroute OFFLINE — mantendo rota em cache, re-armando deteccao")
                #endif
                navigationEngine.cancelPendingReroute()
                return
            }
            // Cooldown: don't reroute more than once per 30 seconds (prevents API rate limiting)
            guard Date().timeIntervalSince(lastRerouteAt) > 30 else {
                #if DEBUG
                print("[Route] Reroute skipped — cooldown active (\(Int(30 - Date().timeIntervalSince(lastRerouteAt)))s remaining)")
                #endif
                // Re-arm detection and restore the route line so we retry on the next divergence.
                navigationEngine.cancelPendingReroute()
                return
            }
            lastRerouteAt = Date()
            guard let dest = activeRouteDestination else {
                #if DEBUG
                print("[Route] Reroute skipped — destination coordinate unavailable")
                #endif
                navigationEngine.cancelPendingReroute()
                return
            }
            calculateRoute(to: dest, address: result.destinationName)
        }
        navigationEngine.onArrival = {
            let dest = result.destinationName.isEmpty ? lang.horizonArrivalYourDestination : result.destinationName
            arrivalDestinationName = dest
            navigationEngine.stopNavigation()
            var t = Transaction(animation: nil); t.disablesAnimations = true
            withTransaction(t) {
                truckRoute = nil; route = nil; routeSteps = []; currentStepIndex = 0
                bottomSheetExpanded = false; showingSteps = false
            }
            UIApplication.shared.isIdleTimerDisabled = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showingArrival = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { withAnimation { showingArrival = false } }
        }
        if !result.truckNotices.isEmpty { withAnimation { showingTruckWarnings = true } }
    }

    @MainActor
    private func prepareFallbackRoute(
        _ route: TruckRoute,
        provider: RoutingService.RoutingProvider,
        destinationCoordinate: CLLocationCoordinate2D? = nil
    ) {
        bottomSheetExpanded = false
        // Sem modal "Routing Notice": fallback de provider é aplicado silenciosamente.
        #if DEBUG
        print("[Route] fallback provider applied: \(provider.rawValue)")
        #endif
        applyRoute(route, destinationCoordinate: destinationCoordinate)
    }

    @MainActor
    private func applyPendingFallbackRoute() {
        guard let pending = pendingFallbackRoute else { return }
        pendingFallbackRoute = nil; pendingFallbackProvider = .unknown
        applyRoute(pending)
    }

    private func parseCoordinateAddress(_ input: String) -> CLLocationCoordinate2D? {
        let cleaned = input.replacingOccurrences(of: ";", with: ",")
        let parts = cleaned.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              (-90...90).contains(lat),
              (-180...180).contains(lon) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Nearby Search

    private func searchNearby(category: NearbyCategory) {
        guard let location = locationManager.currentLocation else { return }
        isLoadingNearby = true
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = countryCompliance.nearbyQuery(base: category.searchQuery, categoryKey: category.rawValue)
            let activePolyline = truckRoute?.polyline ?? route?.polyline
            if let polyline = activePolyline {
                let routeRect = polyline.boundingMapRect
                let expandedRect = routeRect.insetBy(dx: -routeRect.width * 0.15, dy: -routeRect.height * 0.15)
                request.region = MKCoordinateRegion(expandedRect)
            } else {
                request.region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.30))
            }
            let results = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
            await MainActor.run {
                nearbyItems = results.prefix(15).compactMap { item in
                    let loc = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude); let dist = location.distance(from: loc)
                    let addrText = item.placemark.title ?? item.name ?? ""
                    return NearbyStopItem(name: item.name ?? "Unknown", address: addrText,
                        coordinate: item.placemark.coordinate, distanceMeters: dist, phone: item.phoneNumber, category: category)
                }.sorted { $0.distanceMeters < $1.distanceMeters }
                isLoadingNearby = false
            }
        }
    }

    private func updateCheapestDiesel() {
        let stopsWithPrice = truckStopService.nearbyStops.filter { $0.amenities.dieselPrice != nil }
        guard let cheapest = stopsWithPrice.min(by: { ($0.amenities.dieselPrice ?? 999) < ($1.amenities.dieselPrice ?? 999) }) else {
            cheapestDieselStop = nil; showingCheapestDiesel = false; return
        }
        cheapestDieselStop = cheapest
        withAnimation(.spring(response: 0.5)) { showingCheapestDiesel = true }
    }

    private func refreshNearestParking(from location: CLLocation) {
        Task {
            var resolvedName = ""
            var resolvedMiles = Double.greatestFiniteMagnitude
            var isFull = false

            if SupabaseConfig.isConfigured,
               let rows = try? await PoiPlacesService.shared.fetchPlacesNear(
                   location: location,
                   radiusMeters: 40_000,
                   poiTypes: ["truck_stop", "rest_area"],
                   limit: 25
               ) {
                let heading = locationManager.currentHeading?.trueHeading
                let ahead = rows.compactMap { row -> (PlacesNearRow, Double)? in
                    let dist = row.distance_m ?? location.distance(
                        from: CLLocation(latitude: row.lat, longitude: row.lon)
                    )
                    guard dist < 24_140 else { return nil }
                    if let heading {
                        let coord = CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon)
                        let diff = abs(angleDeltaDegrees(heading, location.coordinate.bearing(to: coord)))
                        guard diff <= 75 else { return nil }
                    }
                    return (row, dist)
                }.sorted { $0.1 < $1.1 }.first

                if let (row, distMeters) = ahead {
                    resolvedName = row.name ?? row.brand ?? "Truck parking"
                    resolvedMiles = distMeters / 1609.34
                    let available = row.gov_parking_available ?? row.parking_available
                    if let available, available == 0 { isFull = true }
                    else if row.parking_status?.lowercased() == "full" { isFull = true }
                    else if let siteOpen = row.gov_site_open, !siteOpen { isFull = true }
                }
            }

            if resolvedMiles > 15 {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = "truck parking"
                request.region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
                if let items = try? await MKLocalSearch(request: request).start() {
                    let nearest = items.mapItems.compactMap { item -> (String, Double)? in
                        guard let name = item.name else { return nil }
                        let coord = item.placemark.coordinate
                        let dist = location.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) / 1609.34
                        return (name, dist)
                    }.sorted { $0.1 < $1.1 }.first
                    if let (name, miles) = nearest, miles < resolvedMiles {
                        resolvedName = name
                        resolvedMiles = miles
                        isFull = false
                    }
                }
            }

            guard resolvedMiles < 15, !resolvedName.isEmpty else {
                await MainActor.run { showParkingPill = false }
                return
            }

            if !isFull {
                let reports = (try? await SupabaseClient.shared.fetchRecentRoadReports(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    radiusKm: 25
                )) ?? []
                let cutoff = Date().addingTimeInterval(-3600 * 4)
                isFull = reports.contains {
                    $0.report_type == "parkingFull"
                        && $0.location_name == resolvedName
                        && (ISO8601DateFormatter().date(from: $0.reported_at) ?? .distantPast) > cutoff
                }
            }

            await MainActor.run {
                nearestParkingName = resolvedName
                nearestParkingMiles = resolvedMiles
                nearestParkingFull = isFull
                withAnimation { showParkingPill = true }
            }
        }
    }

    // MARK: - Scale (Weigh Station) Detection

    private func openScaleDetailsSheet() {
        openWeighStationReportSheet()
    }

    private func openWeighStationReportSheet() {
        showingWeighStation = true
    }

    private func weighReportPrefillTarget() -> WeighStationReportTarget? {
        guard scaleAlertPoiPlaceId != nil || !scaleAlertName.isEmpty else { return nil }
        let coord = scaleAlertCoordinate ?? locationManager.currentLocation?.coordinate
        guard let coord else { return nil }
        let name = scaleAlertName.isEmpty ? lang.horizonGenericWeighStation : scaleAlertName
        return WeighStationReportTarget(
            id: scaleAlertPoiPlaceId ?? UUID(),
            name: name,
            latitude: coord.latitude,
            longitude: coord.longitude,
            poiPlaceId: scaleAlertPoiPlaceId,
            distanceMeters: scaleAlertDistanceMiles * 1609.34,
            govStatus: scaleAlertGovStatus,
            govSource: scaleAlertGovSource,
            countryCode: nil
        )
    }

    private func submitScaleReport(_ status: WeighStationStatus) {
        let name = scaleAlertName.isEmpty ? lang.horizonGenericWeighStation : scaleAlertName
        let coord = scaleAlertCoordinate ?? locationManager.currentLocation?.coordinate
        WeighStationStatusService.shared.submit(
            status: status,
            for: name,
            latitude: coord?.latitude,
            longitude: coord?.longitude,
            poiPlaceId: scaleAlertPoiPlaceId
        )
        let resolved = WeighStationStatusService.shared.resolve(
            stationName: name,
            near: coord,
            govStatus: scaleAlertGovStatus,
            govSource: scaleAlertGovSource,
            govSiteOpen: scaleAlertGovSiteOpen
        )
        scaleAlertStatus = resolved.displayStatus
        scaleAlertProvenance = resolved.provenance
        scaleAlertCommunityHint = resolved.communityHint ?? status
        scaleAlertCommunitySummary = resolved.communitySummary
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Auto scale detection — no driver action. Wider corridor + GPS course when navigating.
    /// Navigating: 50 mi alert horizon so staged notifications (50 → 20 → 5 mi) can fire.
    private func scaleDetectionProfile(for location: CLLocation) -> (alertMeters: Double, searchMeters: Double, headingTolerance: Double) {
        if isNavigating {
            return (80_467, 96_561, 100)
        }
        return (5_000, 24_140, 70)
    }

    /// Staged alert tier: 3 = first heads-up (≤50 mi), 2 = update (≤20 mi), 1 = final (≤5 mi).
    /// Idle uses a single close-range tier. Returns nil when out of alert range.
    private func scaleAlertTier(forDistanceMeters meters: Double) -> Int? {
        if isNavigating {
            if meters <= 8_047 { return 1 }
            if meters <= 32_187 { return 2 }
            if meters <= 80_467 { return 3 }
            return nil
        }
        return meters <= 5_000 ? 1 : nil
    }

    private func isScaleAhead(
        of location: CLLocation,
        target: CLLocationCoordinate2D,
        headingTolerance: Double
    ) -> Bool {
        let bearing = locationManager.bestBearing
        guard location.speed >= 2 || locationManager.currentHeading != nil else { return true }
        let diff = abs(angleDeltaDegrees(bearing, location.coordinate.bearing(to: target)))
        return diff <= headingTolerance
    }

    @MainActor
    private func presentMoodCheckIfParked() {
        guard !isNavigating else { return }
        if AppAccessPolicy.moodCheckOnlyWhenParked {
            let speedMph = max(0, (locationManager.currentLocation?.speed ?? 0) * 2.23694)
            guard speedMph < 3 else { return }
        }
        let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        guard lastMoodCheckDateString != todayStr else { return }
        showingMoodCheck = true
        lastMoodCheckDateString = todayStr
    }

    private func checkForNearbyScales(from location: CLLocation) {
        Task {
            let limits = scaleDetectionProfile(for: location)
            var stationName = lang.horizonGenericWeighStation
            var distMeters: Double = .greatestFiniteMagnitude
            var stationCoord: CLLocationCoordinate2D?
            var govWeighStatus: String?
            var govWeighSource: String?
            var govSiteOpen: Bool?
            var poiPlaceId: UUID?

            // 1) Supabase: OSM + USDOT NTAD weigh POIs (official locations)
            if let rows = try? await PoiPlacesService.shared.fetchWeighStationsNear(
                location: location,
                radiusMeters: limits.searchMeters,
                limit: isNavigating ? 60 : 40
            ) {
                let ahead = rows.compactMap { row -> (PlacesNearRow, Double)? in
                    let coord = CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon)
                    let itemLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let dist = location.distance(from: itemLoc)
                    guard dist < limits.searchMeters else { return nil }
                    guard isScaleAhead(of: location, target: coord, headingTolerance: limits.headingTolerance) else { return nil }
                    return (row, dist)
                }.sorted { ($0.1) < ($1.1) }.first

                if let (row, dist) = ahead, dist <= limits.alertMeters {
                    stationName = row.name ?? stationName
                    distMeters = dist
                    stationCoord = CLLocationCoordinate2D(latitude: row.lat, longitude: row.lon)
                    poiPlaceId = row.id
                    govWeighStatus = row.gov_weigh_status
                    govWeighSource = row.gov_weigh_source
                    govSiteOpen = row.gov_site_open
                }
            }

            // 2) MapKit fallback when Supabase has no weigh POI nearby
            if distMeters > limits.alertMeters {
                let queries = countryCompliance.weighQueries
                let region = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: limits.searchMeters,
                    longitudinalMeters: limits.searchMeters
                )
                var allItems: [MKMapItem] = []
                for query in queries {
                    let req = MKLocalSearch.Request(); req.naturalLanguageQuery = query; req.region = region
                    let items = (try? await MKLocalSearch(request: req).start())?.mapItems ?? []
                    allItems.append(contentsOf: items)
                }
                var deduped: [MKMapItem] = []
                for item in allItems {
                    let loc = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
                    if !deduped.contains(where: { CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude).distance(from: loc) < 500 }) {
                        deduped.append(item)
                    }
                }
                let nearest = deduped.map { item in
                    let itemLoc = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
                    let dist = location.distance(from: itemLoc)
                    let isAhead = isScaleAhead(
                        of: location,
                        target: item.placemark.coordinate,
                        headingTolerance: limits.headingTolerance
                    )
                    return (item, dist, isAhead)
                }.filter { $0.2 }.filter { $0.1 < limits.searchMeters }.sorted { $0.1 < $1.1 }.first

                guard let (nearestItem, d, _) = nearest, d <= limits.alertMeters else {
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.2)) { showingScaleAlert = false }
                    }
                    return
                }
                stationName = nearestItem.name ?? stationName
                distMeters = d
                stationCoord = nearestItem.placemark.coordinate
            }

            guard distMeters <= limits.alertMeters else {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) { showingScaleAlert = false }
                }
                return
            }

            let distMiles = distMeters / 1609.34
            let weighService = WeighStationStatusService.shared
            await weighService.fetchRemoteReports(near: stationCoord ?? location.coordinate, radiusKm: 80)
            await operationalFeedService.refreshIfNeeded(for: stationCoord ?? location.coordinate)
            operationalFeedService.applyWeighSignals()

            let resolved = weighService.resolve(
                stationName: stationName,
                near: stationCoord,
                govStatus: govWeighStatus,
                govSource: govWeighSource,
                govSiteOpen: govSiteOpen
            )

            await MainActor.run {
                scaleAlertName = stationName
                scaleAlertDistanceMiles = distMiles
                scaleAlertCoordinate = stationCoord
                scaleAlertPoiPlaceId = poiPlaceId
                scaleAlertGovStatus = govWeighStatus
                scaleAlertGovSource = govWeighSource
                scaleAlertGovSiteOpen = govSiteOpen
                scaleAlertStatus = resolved.displayStatus
                scaleAlertProvenance = resolved.provenance
                scaleAlertCommunityHint = resolved.communityHint
                scaleAlertCommunitySummary = resolved.communitySummary

                // Staged notifications: fire once per tier (50 / 20 / 5 mi), never repeat
                // inside a tier — a dismissed banner stays dismissed until the next tier.
                let tier = scaleAlertTier(forDistanceMeters: distMeters)
                let stationKey = poiPlaceId?.uuidString ?? stationName
                let tierKey = "\(stationKey)#\(tier ?? 0)"
                let isNewTier = tier != nil && !scaleAlertNotifiedTierKeys.contains(tierKey)
                if isNewTier {
                    if scaleAlertNotifiedTierKeys.count > 64 { scaleAlertNotifiedTierKeys.removeAll() }
                    scaleAlertNotifiedTierKeys.insert(tierKey)
                    withAnimation(.spring(response: 0.4)) { showingScaleAlert = true }
                }
                if isNavigating, isNewTier {
                    let distText = regionalSettings.formatDistance(distMeters)
                    let statusNote: String?
                    switch scaleAlertProvenance {
                    case .official:
                        switch scaleAlertStatus {
                        case .open: statusNote = lang.voiceScaleOfficialOpenPhrase
                        case .closed: statusNote = lang.voiceScaleOfficialClosedPhrase
                        case .bypass, .monitoring, .unknown: statusNote = nil
                        }
                    case .community:
                        if let hint = scaleAlertCommunityHint {
                            switch hint {
                            case .open: statusNote = lang.voiceScaleReportedOpenPhrase
                            case .closed: statusNote = lang.voiceScaleReportedClosedPhrase
                            case .monitoring: statusNote = lang.voiceScaleUnconfirmedPhrase
                            }
                        } else {
                            statusNote = lang.voiceScaleUnconfirmedPhrase
                        }
                    case .locationOnly:
                        statusNote = lang.voiceScaleUnconfirmedPhrase
                    }
                    if lastScaleVoiceKey != tierKey {
                        lastScaleVoiceKey = tierKey
                        VoiceNavigationManager.shared.announceScaleAheadWithStatus(
                            stationName: stationName,
                            distanceText: distText,
                            statusNote: statusNote,
                            lang: lang
                        )
                    }
                }
            }
        }
    }

    // MARK: - Alerts

    private func addAlert(type: MapAlert.AlertType) {
        guard let location = locationManager.currentLocation else { return }
        let alert = MapAlert(type: type, coordinate: location.coordinate)
        mapAlerts.append(alert)
        if mapAlerts.count > 50 { mapAlerts.removeFirst() }
        Task {
            let payload = RoadReportPayload(driver_id: SupabaseClient.shared.currentDriverId, report_type: type.rawValue.lowercased(),
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, location_name: nil)
            do {
                try await SupabaseClient.shared.submitRoadReport(payload)
            } catch {
                #if DEBUG
                print("MapAlert: sync failed — \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func confirmAlert(_ alert: MapAlert) {
        if let idx = mapAlerts.firstIndex(where: { $0.id == alert.id }) { mapAlerts[idx].confirmations += 1 }
    }

    private func removeAlert(_ alert: MapAlert) { mapAlerts.removeAll { $0.id == alert.id } }

    private func loadRemoteAlerts() {
        guard let location = locationManager.currentLocation else { return }
        Task {
            do {
                let records = try await SupabaseClient.shared.fetchRecentRoadReports(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, radiusKm: 160)
                await MainActor.run {
                    for record in records {
                        let coord = CLLocationCoordinate2D(latitude: record.latitude, longitude: record.longitude)
                        let alreadyExists = mapAlerts.contains { existing in
                            CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude)
                                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) < 500
                                && existing.type.rawValue.lowercased() == record.report_type
                        }
                        guard !alreadyExists else { continue }
                        let alertType: MapAlert.AlertType
                        switch record.report_type.lowercased() {
                        case "scale": alertType = .scale; case "police": alertType = .police
                        case "accident": alertType = .accident; case "weather": alertType = .weather
                        case "hazmat": alertType = .hazmat; default: continue
                        }
                        var alert = MapAlert(type: alertType, coordinate: coord)
                        alert.confirmations = record.confirmations ?? 1
                        mapAlerts.append(alert)
                        if mapAlerts.count > 50 { mapAlerts.removeFirst() }
                    }
                }
            } catch {
                #if DEBUG
                print("MapAlerts: remote fetch failed — \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func fetchPendingDispatchLoads() async {
        do {
            let records = try await SupabaseClient.shared.fetchPendingLoads()
            guard let first = records.first else { return }
            let load = DispatchedLoad(id: first.id, driverId: first.driver_id ?? SupabaseClient.shared.currentDriverId ?? "unknown",
                loadNumber: first.load_number, originAddress: first.origin_address, destinationAddress: first.destination_address,
                destinationLatitude: first.destination_lat, destinationLongitude: first.destination_lng,
                pickupTime: nil, deliveryTime: nil, commodity: first.commodity, weightLbs: first.weight_lbs,
                specialInstructions: first.special_instructions, status: .pending, companyId: first.company_id,
                companyName: first.company_name, valorFrete: first.valor_frete, precoDieselEia: first.preco_diesel_eia)
            await MainActor.run {
                guard !showingDispatchAlert else { return }
                dispatchService.handleIncomingLoad(load)
            }
        } catch {
            #if DEBUG
            print("HorizonView: fetchPendingDispatchLoads failed — \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Compliance

    @MainActor private func syncRegionalPolicyFromLocation() {
        let recommendedRegion = countryCompliance.recommendedRegion
        if regionalSettings.currentRegion != recommendedRegion { regionalSettings.currentRegion = recommendedRegion }
    }

    @MainActor private func evaluateTruckSpeedCompliance(using location: CLLocation) {
        guard location.speed >= 0 else { return }
        let gpsSpeedMph = max(0, location.speed * 2.23694)
        let effectiveMph = fleetTelemetryService.preferredSpeedMph(gpsSpeedMph: gpsSpeedMph)
        let speedKmh = effectiveMph * 1.60934
        // Issue 2: usa o limite REAL da via (Valhalla /locate) quando disponível, pegando o MENOR
        // entre ele e o baseline da jurisdição (seguro p/ caminhão). Antes: só o genérico (ex.: 65).
        let jurisdictionLimit = jurisdictionPolicyService.effectiveSpeedLimitKmh(fallback: countryCompliance.truckSpeedLimitKmh)
        let legalLimit = min(jurisdictionLimit, currentEdgeSpeedLimitKmh ?? jurisdictionLimit)
        // Issue 2 (teste de estrada): só avisa com folga real (~+5 mph / +8 km/h) e no
        // máximo a cada 3 min. Antes disparava a +3 km/h e re-disparava a cada 45s, virando
        // "nag" constante ao cruzar acima do limite-base. (O limite em si vem de fonte pesada;
        // conectar a um DB de limite por trecho de via é um passo de dados separado.)
        guard speedKmh > legalLimit + 8 else { return }
        let now = Date(); guard now.timeIntervalSince(lastSpeedComplianceAlertAt) > 180 else { return }
        lastSpeedComplianceAlertAt = now
        let currentSpeed = regionalSettings.formatSpeed(speedKmh)
        let limitText = regionalSettings.formatSpeed(legalLimit)
        speedComplianceMessage = lang.truckSpeedComplianceMessage(currentFormatted: currentSpeed, limitFormatted: limitText)
        withAnimation(.spring(response: 0.35)) { showingSpeedComplianceAlert = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            withAnimation(.easeOut(duration: 0.25)) { showingSpeedComplianceAlert = false }
        }
    }

    @MainActor private func evaluateGeofenceEvents(using location: CLLocation) {
        let activeFences = geofences.filter { $0.isActive && $0.radius > 0 }
        guard !activeFences.isEmpty else { return }
        for fence in activeFences {
            let center = CLLocation(latitude: fence.latitude, longitude: fence.longitude)
            let isInside = location.distance(from: center) <= fence.radius
            let wasInside = geofenceInsideState[fence.id] ?? false
            if !wasInside && isInside && fence.notifyOnEntry {
                geofenceInsideState[fence.id] = true
                emitGeofenceEvent(type: "entry", geofenceName: fence.name, at: location.coordinate)
            } else if wasInside && !isInside && fence.notifyOnExit {
                geofenceInsideState[fence.id] = false
                emitGeofenceEvent(type: "exit", geofenceName: fence.name, at: location.coordinate)
            } else { geofenceInsideState[fence.id] = isInside }
        }
    }

    @MainActor private func emitGeofenceEvent(type: String, geofenceName: String, at coordinate: CLLocationCoordinate2D) {
        let title = lang.horizonGeofenceBanner(isEntry: type == "entry", name: geofenceName)
        speedComplianceMessage = title
        withAnimation(.spring(response: 0.35)) { showingSpeedComplianceAlert = true }
        let voiceId = UUID()
        voiceManager.announceRoadAlert(type: speedComplianceMessage, alertId: voiceId, lang: lang)
        Task {
            let payload = RoadReportPayload(driver_id: SupabaseClient.shared.currentDriverId, report_type: "geofence_\(type)",
                latitude: coordinate.latitude, longitude: coordinate.longitude, location_name: geofenceName)
            try? await SupabaseClient.shared.submitRoadReport(payload)
        }
    }

    // MARK: - Truck Stop Proximity

    private func checkTruckStopProximity(from location: CLLocation, speed: Double) {
        let arrivalThreshold: Double = 350
        let departureThreshold: Double = 600
        let stops = truckStopService.nearbyStops
        guard !stops.isEmpty else { return }

        var nearest: TruckStopItem?
        var nearestDist = Double.greatestFiniteMagnitude
        for stop in stops {
            let dist = location.distance(from: CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude))
            if dist < nearestDist {
                nearestDist = dist
                nearest = stop
            }
        }
        guard let nearestStop = nearest else { return }

        let distToNearest = nearestDist
        let isStopped = speed < 3.0

        if distToNearest < arrivalThreshold && isStopped && nearestStop.qualifiesAsFuelStopForFood {
            if currentTruckStop?.name != nearestStop.name {
                currentTruckStop = nearestStop
                truckStopArrivedAt = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [self] in
                    guard currentTruckStop?.name == nearestStop.name, isStoppedAtTruckStop else { return }
                    lastFoodSuggestionLocation = nil
                    loadFoodSuggestion()
                }
                if parkingPromptShownFor != nearestStop.name {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [self] in
                        guard currentTruckStop?.name == nearestStop.name, isStoppedAtTruckStop else { return }
                        parkingPromptShownFor = nearestStop.name
                        withAnimation(.spring(response: 0.4)) { showingParkingPrompt = true }
                    }
                }
            }
        } else if distToNearest > departureThreshold || (speed > 8.0 && distToNearest > arrivalThreshold) {
            if let prevStop = currentTruckStop {
                let dwell = truckStopArrivedAt.map { Date().timeIntervalSince($0) } ?? 0
                currentTruckStop = nil
                truckStopArrivedAt = nil
                showingParkingPrompt = false
                showingFoodSuggestion = false
                foodSuggestion = nil

                guard dwell >= stopReviewMinDwellSeconds else { return }
                reviewTargetStop = prevStop
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [self] in
                    guard reviewTargetStop?.name == prevStop.name, !showingStopReview else { return }
                    withAnimation(.spring(response: 0.4)) { showingStopReview = true }
                }
            }
        } else if speed > 5.0 {
            showingFoodSuggestion = false
        }
    }

    private var isStoppedAtTruckStop: Bool {
        guard let loc = locationManager.currentLocation else { return false }
        return loc.speed >= 0 && loc.speed < 3.5
    }

    @MainActor
    private func checkFacilityVisitDeparture(from location: CLLocation) {
        guard let visit = pendingFacilityVisit, !showingFacilityReview else { return }
        let center = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        let dist = location.distance(from: center)
        let dwell = Date().timeIntervalSince(visit.arrivedAt)
        guard dist > facilityDepartureRadiusMeters, dwell >= facilityReviewMinDwellSeconds else { return }

        pendingFacilityVisit = nil
        facilityReviewLoad = visit.load
        facilityReviewType = visit.type
        facilityReviewCoordinate = visit.coordinate
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [self] in
            guard facilityReviewLoad?.loadNumber == visit.load.loadNumber else { return }
            withAnimation(.spring(response: 0.4)) { showingFacilityReview = true }
        }
    }

    private func submitParkingAvailability(
        _ status: HorizonTruckStopParkingBanner.ParkingAvailability,
        for stop: TruckStopItem
    ) {
        guard SupabaseClient.shared.isAuthenticated,
              let driverId = SupabaseClient.shared.currentDriverId else {
            #if DEBUG
            print("[ParkingReport] skipped remote sync: driver is not authenticated")
            #endif
            return
        }
        // Não fabricar contagem a partir do status qualitativo (era 65%/20% de um total `?? 50`
        // inventado, enviado ao backend como nº real). O status (many/some/full) é o dado REAL do
        // motorista; a contagem exata não é conhecida → nil. Só 'full' = 0 vaga é honesto.
        let available: Int? = (status == .full) ? 0 : nil

        let structured = TruckStopParkingReportPayload(
            poi_place_id: stop.dataSource == .supabase ? stop.id : nil,
            driver_id: driverId,
            location_name: stop.name,
            latitude: stop.coordinate.latitude,
            longitude: stop.coordinate.longitude,
            status: status.rawValue.lowercased(),
            available_slots: available,
            total_slots: stop.amenities.parkingSlots
        )

        Task {
            do {
                try await SupabaseClient.shared.submitTruckStopParkingReport(structured)
            } catch {
                let fallbackType: CrowdsourceReport.ReportType = status == .full ? .parkingFull : .parkingAvailable
                let fallback = RoadReportPayload(
                    driver_id: driverId,
                    report_type: fallbackType.backendKey,
                    latitude: stop.coordinate.latitude,
                    longitude: stop.coordinate.longitude,
                    location_name: stop.name
                )
                do {
                    try await SupabaseClient.shared.submitRoadReport(fallback)
                } catch {
                    #if DEBUG
                    print("[ParkingReport] fallback sync failed: \(error.localizedDescription)")
                    #endif
                }
                #if DEBUG
                print("[ParkingReport] structured sync failed, fallback attempted: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func submitStopReview(_ review: StopReview, for stop: TruckStopItem) async throws {
        let ratings = [review.serviceRating, review.showerRating, review.foodRating].filter { $0 > 0 }
        let overall = ratings.isEmpty ? 1.0 : Double(ratings.reduce(0, +)) / Double(ratings.count)

        if SupabaseClient.shared.isAuthenticated,
           let driverId = SupabaseClient.shared.currentDriverId {
            let payload = TruckStopReviewPayload(
                poi_place_id: stop.dataSource == .supabase ? stop.id : nil,
                driver_id: driverId,
                location_name: stop.name,
                latitude: stop.coordinate.latitude,
                longitude: stop.coordinate.longitude,
                easy_access_rating: nil,
                cleanliness_rating: review.showerRating > 0 ? review.showerRating : nil,
                restaurants_rating: review.foodRating > 0 ? review.foodRating : nil,
                friendly_service_rating: review.serviceRating > 0 ? review.serviceRating : nil,
                price_rating: nil,
                overall_rating: max(1.0, min(5.0, overall)),
                restaurant_names: [],
                has_healthy_options: nil,
                comments: review.notes.isEmpty ? nil : review.notes
            )
            try await SupabaseClient.shared.submitTruckStopReview(payload)
        }

        await MainActor.run {
            WellnessVisitLinker.linkTruckStopReview(
                review,
                stopName: stop.name,
                coordinate: stop.coordinate,
                modelContext: modelContext
            )
            reviewTargetStop = nil
            showingStopReview = false
        }
    }

    @MainActor
    private func submitFacilityReview(_ review: FacilityReview) async {
        let ratings = [review.treatmentRating, review.bathroomRating, review.foodAccessRating, review.accessRating].filter { $0 > 0 }
        let overall = ratings.isEmpty ? 1.0 : Double(ratings.reduce(0, +)) / Double(ratings.count)

        if SupabaseClient.shared.isAuthenticated,
           let driverId = SupabaseClient.shared.currentDriverId {
            let payload = ShipperFacilityReviewPayload(
                driver_id: driverId,
                load_number: review.loadNumber,
                company_id: review.companyId,
                company_name: review.companyName,
                review_type: review.type == .pickup ? "pickup" : "delivery",
                latitude: review.coordinate.latitude,
                longitude: review.coordinate.longitude,
                treatment_rating: review.treatmentRating > 0 ? review.treatmentRating : nil,
                bathroom_rating: review.bathroomRating > 0 ? review.bathroomRating : nil,
                food_access_rating: review.foodAccessRating > 0 ? review.foodAccessRating : nil,
                access_rating: review.accessRating > 0 ? review.accessRating : nil,
                wait_minutes: review.waitMinutes,
                overall_rating: max(1.0, min(5.0, overall)),
                notes: review.notes.isEmpty ? nil : review.notes
            )
            do {
                try await SupabaseClient.shared.submitShipperFacilityReview(payload)
            } catch {
                #if DEBUG
                print("[FacilityReview] sync failed: \(error.localizedDescription)")
                #endif
            }
        }

        WellnessVisitLinker.linkFacilityReview(review, modelContext: modelContext)

        facilityReviewLoad = nil
        facilityReviewCoordinate = nil
        showingFacilityReview = false
    }

    /// During navigation: voice when a nearby truck stop is ~30 minutes away (diesel awareness).
    private func announceNavTruckFuelEtasIfNeeded(location: CLLocation, speed: Double, now: Date) {
        guard isNavigating, voiceManager.isEnabled else { return }
        guard now.timeIntervalSince(lastNavFuelEtaVoiceAt) >= 24 else { return }
        guard !truckStopService.nearbyStops.isEmpty else { return }

        let minSpeedMs = max(speed, 6.7)
        for stop in truckStopService.nearbyStops.prefix(36) {
            let dist = location.distance(from: CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude))
            let etaMinutes = Int(round((dist / minSpeedMs) / 60.0))
            guard (26...34).contains(etaMinutes) else { continue }
            // Heads-up de vaga (dor nº1) — reaproveita as frases de report já traduzidas (10 idiomas).
            let parkingNote: String? = {
                if let avail = stop.amenities.parkingAvailable {
                    return avail == 0 ? lang.reportSubParkingFull : lang.reportSubParkingAvailable
                }
                switch stop.amenities.parkingStatus {
                case .full: return lang.reportSubParkingFull
                case .available, .limited: return lang.reportSubParkingAvailable
                case .unknown: return nil
                }
            }()
            VoiceNavigationManager.shared.announceTruckFuelEta(stopName: stop.name, etaMinutes: etaMinutes, parkingNote: parkingNote, lang: lang)
            lastNavFuelEtaVoiceAt = now
            return
        }
    }

    // MARK: - Engineering Safety Alerts

    private func checkGradeAlert(from location: CLLocation) {
        guard location.verticalAccuracy >= 0 && location.verticalAccuracy < 30 else { return }
        let now = Date(); guard now.timeIntervalSince(lastGradeCheckAt) > 15 else { return }
        let ref = locationHistory.reversed().dropFirst().first { let d = location.distance(from: $0); return d >= 200 && d <= 800 }
        guard let ref else { return }
        let horizontal = location.distance(from: ref); guard horizontal > 50 else { return }
        let grade = (location.altitude - ref.altitude) / horizontal * 100.0
        guard abs(grade) >= 5.0 else { return }
        lastGradeCheckAt = now; let isDown = grade < 0
        gradeAlertMessage = isDown ? "Downhill \(String(format: "%.0f", abs(grade)))% grade — engine brake, watch speed"
            : "Uphill \(String(format: "%.0f", abs(grade)))% grade — lower gear, watch engine temp"
        gradeIsDescending = isDown
        withAnimation(.spring(response: 0.35)) { showingGradeAlert = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { withAnimation(.easeOut) { showingGradeAlert = false } }
    }

    private func checkSharpCurveAlert(at location: CLLocation) {
        guard location.course >= 0 && location.speed > 8.9 else { return }
        let now = Date(); guard now.timeIntervalSince(lastCurveCheckAt) > 12 else { return }
        guard locationHistory.count >= 6 else { return }
        let old = locationHistory[locationHistory.count - 6]; guard old.course >= 0 else { return }
        let headingDelta = abs(angleDeltaDegrees(location.course, old.course))
        let dist = location.distance(from: old)
        guard headingDelta > 45 && dist < 500 && dist > 30 else { return }
        lastCurveCheckAt = now
        withAnimation(.spring(response: 0.3)) { showingCurveAlert = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { withAnimation(.easeOut) { showingCurveAlert = false } }
    }

    private func checkWindAlert() {
        guard let weather = weatherService.currentWeather else { return }
        let now = Date(); guard now.timeIntervalSince(lastWindCheckAt) > 120 else { return }
        let gust = weather.windGustMPH ?? 0; let sustained = weather.windSpeedMPH
        let effective = max(sustained, gust)
        if effective < 30 { if showingWindAlert { withAnimation(.easeOut) { showingWindAlert = false } }; return }
        lastWindCheckAt = now; windAlertMph = Int(effective); windAlertIsGust = gust > sustained
        withAnimation(.spring(response: 0.35)) { showingWindAlert = true }
    }

    private func checkDestinationDock(from location: CLLocation) {
        guard !dockCheckDone, let destCoord = truckRoute?.coordinates.last else { return }
        let destLoc = CLLocation(latitude: destCoord.latitude, longitude: destCoord.longitude)
        guard location.distance(from: destLoc) < 2000 else { return }
        dockCheckDone = true
        Task {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = "truck entrance loading dock receiving warehouse"
            req.region = MKCoordinateRegion(center: destCoord, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
            let results = (try? await MKLocalSearch(request: req).start())?.mapItems ?? []
            await MainActor.run {
                dockResults = results.prefix(5).compactMap { item in
                    let dist = location.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude))
                    let addr = item.placemark.title ?? item.name ?? ""
                    return NearbyStopItem(name: item.name ?? "Loading Dock", address: addr,
                        coordinate: item.placemark.coordinate, distanceMeters: dist, phone: item.phoneNumber, category: .rest)
                }
                if !dockResults.isEmpty {
                    withAnimation(.spring(response: 0.4)) { showingDockFinder = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { withAnimation(.easeOut) { showingDockFinder = false } }
                }
            }
        }
    }

    // MARK: - Wellness

    private func loadFoodSuggestion() {
        guard let location = locationManager.currentLocation,
              let stop = currentTruckStop,
              stop.qualifiesAsFuelStopForFood,
              isStoppedAtTruckStop,
              !isNavigating else {
            showingFoodSuggestion = false
            return
        }
        if let last = lastFoodSuggestionLocation, location.distance(from: last) < 500 { return }

        let profile = HealthProfile.loadSaved()
        let isMetric = lang != .english
        let stopLocation = CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude)
        let restaurant = stop.amenities.restaurantNames.first
        let name = restaurant.map { "\(stop.name) · \($0)" } ?? stop.name
        foodSuggestion = FoodSuggestion(
            name: name,
            address: stop.address,
            coordinate: stop.coordinate,
            distanceMeters: location.distance(from: stopLocation),
            reason: "\(profile.suggestionReason) · parada \(stop.network.rawValue)",
            useMetric: isMetric
        )
        showingFoodSuggestion = true
        lastFoodSuggestionLocation = location
    }

    // MARK: - Utility Functions

    private func isHighwayStep(_ instructions: String) -> Bool {
        let t = instructions.lowercased()
        return t.contains("i-") || t.contains("interstate") || t.contains("highway")
            || t.contains("freeway") || t.contains("merge") || t.contains("us-")
    }

    private func angleDeltaDegrees(_ a: Double, _ b: Double) -> Double {
        var delta = (a - b).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
        return delta
    }

    private func warningIcon(for type: TruckRestrictionWarning.WarningType) -> String {
        switch type {
        case .lowBridge: return "arrow.down.to.line"; case .weightLimit: return "scalemass.fill"
        case .heightLimit: return "arrow.up.and.down"; case .hazmat: return "biohazard"
        case .tunnel: return "road.lanes"; case .narrowRoad: return "road.lanes"
        case .general: return "exclamationmark.triangle.fill"
        }
    }

    private func warningTypeForNotice(_ code: String) -> TruckRestrictionWarning.WarningType {
        let lower = code.lowercased()
        if lower.contains("height") || lower.contains("clearance") { return .heightLimit }
        if lower.contains("weight") || lower.contains("axle") { return .weightLimit }
        if lower.contains("hazmat") || lower.contains("haz") { return .hazmat }
        if lower.contains("lez") || lower.contains("emission") || lower.contains("eco-zone") { return .general }
        if lower.contains("tunnel") { return .tunnel }
        return .lowBridge
    }

    private func isDuskNow(at date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date); return hour >= 18 && hour <= 21
    }

    private func isVehicleStopped() -> Bool {
        if let speed = locationManager.currentLocation?.speed, speed >= 0 { return speed <= 1.0 }
        return false
    }

    private func startSpeedMonitoringForDusk() {
        speedMonitorTimer?.invalidate()
        speedMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            // O bloco do Timer é nonisolated; este corpo toca estado/métodos @MainActor.
            Task { @MainActor in
                let now = Date(); guard now.timeIntervalSince(lastSpeedCheckDate) > 25 else { return }
                lastSpeedCheckDate = now
                if isDuskNow(at: now) && isVehicleStopped() && !hasShownMoodAtDuskToday && !isNavigating {
                    presentMoodCheckIfParked()
                    hasShownMoodAtDuskToday = true
                }
                if Calendar.current.isDateInToday(now) == false { hasShownMoodAtDuskToday = false }
            }
        }
    }

    private func truckStopSearchQuery(for language: AppLanguage) -> String {
        switch language {
        case .portuguese: return "Graal Restaurante Petrobras Ipiranga Posto BR posto caminhão parador"
        case .spanish, .spanishLatam: return "Pemex parador camiones truck stop gasolinera autopista estación servicio"
        case .german, .polish: return "Autohof Rasthof LKW-Parkplatz Tank Rast Motorway services truck stop"
        case .french: return "Aire repos relais routier camion truck stop service routier"
        case .russian: return "стоянка грузовиков truck stop АЗС Газпромнефть"
        case .hindi: return "dhaba truck stop highway restaurant petrol pump"
        case .arabic: return "محطة وقود استراحة شاحنات truck stop service station"
        default: return "Loves Travel Stop Pilot Flying J TA TravelCenters Petro Kwik Trip truck stop travel center Petro-Canada Husky Cenex"
        }
    }

    private func isTruckStopName(_ name: String) -> Bool {
        let keywords = ["loves", "pilot", "flying j", "ta travel", "petro", "kwik trip", "truck stop", "travel center", "truckstop",
            "petro-canada", "husky", "graal", "posto br", "ipiranga", "petrobras", "parador", "pemex", "autohof", "rasthof",
            "tank rast", "motorway services", "aire de repos", "relais routier", "truck", "trucker", "caminhão", "camion"]
        return keywords.contains { name.lowercased().contains($0) }
    }

    private func interstateBadge(from step: DisplayRouteStep) -> String? {
        let text = step.instructions.uppercased()
        let patterns = ["I-", "INTERSTATE "]
        guard patterns.contains(where: { text.contains($0) }) else { return nil }
        if let range = text.range(of: "I-") {
            let number = text[range.upperBound...].prefix { $0.isNumber }
            if !number.isEmpty { return "I-\(number)" }
        }
        if let interRange = text.range(of: "INTERSTATE ") {
            let number = text[interRange.upperBound...].prefix { $0.isNumber }
            if !number.isEmpty { return "I-\(number)" }
        }
        return nil
    }

    private func formatNavDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600; let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m) min" : "\(m) min"
    }

    private var navSpeedLimitText: String {
        let legalLimit = jurisdictionPolicyService.effectiveSpeedLimitKmh(fallback: countryCompliance.truckSpeedLimitKmh)
        return "\(regionalSettings.formatSpeed(legalLimit)) LIMIT"
    }

    private var navCurrentSpeedText: String {
        guard let speed = locationManager.currentLocation?.speed, speed >= 0 else { return "0 MPH" }
        let mph = max(0, speed * 2.23694)
        return "\(Int(mph.rounded())) MPH"
    }

    private var navOverspeeding: Bool {
        guard let speed = locationManager.currentLocation?.speed, speed >= 0 else { return false }
        let legalLimit = jurisdictionPolicyService.effectiveSpeedLimitKmh(fallback: countryCompliance.truckSpeedLimitKmh)
        return (max(0, speed * 3.6)) > (legalLimit + 2)
    }

    private var navigationAlertDistanceBadges: [String] {
        guard let current = locationManager.currentLocation else { return [] }
        var badges: [String] = []
        if isNavigating {
            let restrictionPairs = restrictionWarningManager.activeWarnings.compactMap { w -> (Double, String)? in
                guard let c = w.coordinate else { return nil }
                let d = current.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                let label = restrictionBadgeLabel(for: w.type)
                return (d, "\(label) \(regionalSettings.formatDistance(d))")
            }.sorted { $0.0 < $1.0 }
            badges.append(contentsOf: restrictionPairs.prefix(3).map { $0.1 })
        }
        if badges.count < 3 {
            let cap = 3 - badges.count
            let alertDistances = mapAlerts.map {
                current.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
            }.sorted()
            badges.append(contentsOf: alertDistances.prefix(cap).map { regionalSettings.formatDistance($0) })
        }
        return badges
    }

    private func restrictionBadgeLabel(for type: TruckRestrictionWarning.WarningType) -> String {
        switch type {
        case .lowBridge, .heightLimit: return "Bridge"
        case .weightLimit: return "Weight"
        case .hazmat: return "Hazmat"
        case .tunnel: return "Tunnel"
        case .narrowRoad: return "Narrow"
        case .general: return "Alert"
        }
    }

    private func formatArrivalClock() -> String {
        let arrival = Date().addingTimeInterval(activeDurationSeconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a z"
        formatter.timeZone = .current
        return formatter.string(from: arrival)
    }

    // MARK: - Route Easy (compare truck routes)

    private func selectRouteEasyOption(_ option: RouteEasyOption) {
        guard let coord = routeEasyPendingCoordinate else {
            routeError = lang.horizonRouteErrorCouldNotCalculate
            showingRouteError = true
            return
        }
        let address = routeEasyPendingAddress
        showingRouteEasyPicker = false
        // Aplica a rota DEPOIS do sheet fechar. Aplicar no mesmo ciclo da dismissão fazia o
        // SwiftUI engolir a navegação — por isso a seleção dos 3 modos "não funcionava" e só o
        // caminho da seta (sem sheet em voo) pegava. Mesmo padrão do presentRouteEasyUpgrade.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            commitSelectedRoute(option, coordinate: coord, address: address)
        }
    }

    private func presentRouteEasyUpgrade(for kind: RouteEasyKind) {
        routeEasyUpsellKind = kind
        showingRouteEasyPicker = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            showingRouteEasyUpgrade = true
        }
    }

    private func runRouteEasyPlanning(
        from origin: CLLocation,
        to coordinate: CLLocationCoordinate2D,
        address: String
    ) {
        isCalculatingRoute = true
        bottomSheetExpanded = false
        let diesel = publicDieselPrice?.dieselPrice ?? 3.85
        let mpg: Double = (truckProfile.truckType == .straight) ? 10.0 : 6.5
        let fuelStop = cheapestDieselStop
        let usesTruck = subscriptionPlan.hasTruckRoutes || AppAccessPolicy.unlockAllFeaturesForTesting

        Task { @MainActor in
            do {
                let routing = RoutingService.shared
                let fast = try await routing.calculateTruckRoute(
                    from: origin,
                    to: coordinate,
                    destinationName: address,
                    profile: truckProfile,
                    avoidTolls: false,
                    accessMode: routingAccessMode
                )
                let provider = routing.lastProvider
                routeEasyPendingCoordinate = coordinate
                routeEasyPendingAddress = address

                // "Mostrar os 3 na hora": monta Rápida + Sem Pedágio + Easy/AI e ABRE o seletor —
                // o motorista escolhe ANTES de navegar (não aplica a Rápida sozinho).
                do {
                    let options = try await RouteEasyEngine.buildOptions(
                        from: origin,
                        to: coordinate,
                        destinationName: address,
                        profile: truckProfile,
                        dieselPricePerGallon: diesel,
                        mpg: mpg,
                        cheapestFuelStop: fuelStop,
                        effectivePlan: subscriptionPlan,
                        includeFuelSmart: routeEasyIncludesFuelSmart,
                        prefetchedFastest: fast,
                        prefetchedFastProvider: provider
                    )
                    isCalculatingRoute = false
                    routeEasyOptions = options
                    showingRouteEasyPicker = true
                    #if DEBUG
                    print("[RouteEasy] Picker apresentado — \(options.count) opções")
                    #endif
                } catch {
                    // Fallback: se a comparação falhar, não deixa o motorista preso — aplica a Rápida.
                    isCalculatingRoute = false
                    let fastest = RouteEasyEngine.fastestOption(
                        route: fast,
                        provider: provider,
                        dieselPricePerGallon: diesel,
                        mpg: mpg,
                        usesTruckForFreeTier: usesTruck
                    )
                    routeEasyOptions = [fastest]
                    commitSelectedRoute(fastest, coordinate: coordinate, address: address)
                    #if DEBUG
                    print("[RouteEasy] comparação falhou → aplicou Rápida: \(error.localizedDescription)")
                    #endif
                }
            } catch {
                isCalculatingRoute = false
                bottomSheetExpanded = false
                routeError = lang.horizonRoutingFailureMessage(error)
                showingRouteError = true
                print("[RouteEasy] failed: \(error.localizedDescription)")
            }
        }
    }

    /// Shared step filter for turn-by-turn UI + `NavigationEngine` (same indices).
    private static func filteredNavigationSteps(
        from result: TruckRoute,
        lang: AppLanguage
    ) -> ([DisplayRouteStep], [RouteStep]) {
        var raw = result.steps
            .filter { !$0.instruction.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { $0.maneuver.lowercased() != "depart" }

        if raw.isEmpty, !result.steps.isEmpty {
            raw = result.steps.filter { !$0.instruction.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        if raw.isEmpty {
            raw = [RouteStep(
                instruction: lang.horizonNavigateToDestination(result.destinationName),
                distanceMeters: result.distanceMeters,
                durationSeconds: result.durationSeconds,
                maneuver: "continue"
            )]
        }
        return (raw.map { DisplayRouteStep($0) }, raw)
    }

    private func runSingleTruckRoute(
        from origin: CLLocation,
        to coordinate: CLLocationCoordinate2D,
        address: String,
        isReroute: Bool
    ) {
        if !isReroute {
            isCalculatingRoute = true
            bottomSheetExpanded = false
        }
        Task { @MainActor in
            do {
                let routing = RoutingService.shared
                let result = try await routing.calculateTruckRoute(
                    from: origin,
                    to: coordinate,
                    destinationName: address,
                    profile: truckProfile,
                    avoidTolls: false,
                    accessMode: routingAccessMode
                )
                #if DEBUG
                print("[TRACE-NAV] 7 · rota chegou ao runSingleTruckRoute")
                #endif
                if !isReroute { isCalculatingRoute = false }
                routeEasyPendingCoordinate = coordinate
                routeEasyPendingAddress = address
                destinationAddress = address
                #if DEBUG
                print("[TRACE-NAV] 8 · chamando applyRoute")
                #endif
                applyRoute(result, suppressUIErrors: isReroute, destinationCoordinate: coordinate)
                print("[Route] ✅ NAV START · \(routing.lastProvider.rawValue) · \(Int(result.distanceMeters / 1609)) mi · \(address)")
            } catch {
                if !isReroute { isCalculatingRoute = false }
                if isReroute {
                    // Reroute falhou: RE-ARMA a detecção pra TENTAR DE NOVO. Sem isto, o engine
                    // ficava preso em .rerouting e o motorista seguia perdido sem recálculo. A rota
                    // antiga reaparece (não fica em branco) e retentamos no cooldown normal (30s) —
                    // não na antiga penalidade de 2.5min que deixava o driver sem rota.
                    lastRerouteAt = Date()
                    navigationEngine.cancelPendingReroute()
                    print("[Route] reroute failed (vai retentar em ~30s): \(error.localizedDescription)")
                } else {
                    bottomSheetExpanded = false
                    routeError = lang.horizonRoutingFailureMessage(error)
                    showingRouteError = true
                    print("[Route] failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func commitSelectedRoute(
        _ option: RouteEasyOption,
        coordinate: CLLocationCoordinate2D,
        address: String,
        isReroute: Bool = false
    ) {
        let routing = RoutingService.shared
        lastRoutingProvider = option.provider
        let result = option.route

        if option.kind != .fastest,
           !AppAccessPolicy.unlockAllFeaturesForTesting,
           !option.isAccessible(for: subscriptionPlan) {
            presentRouteEasyUpgrade(for: option.kind)
            return
        }

        if AppAccessPolicy.enforceTruckOnlyRouting, !option.provider.isTruckAware {
            if isReroute { return }
            bottomSheetExpanded = false
            routeError = lang.horizonRouteErrorValhallaUnavailable
            showingRouteError = true
            return
        }
        destinationAddress = address
        applyRoute(result, suppressUIErrors: isReroute, destinationCoordinate: coordinate)
        print("[RouteEasy] Applied \(option.kind.rawValue) via \(routing.lastProvider.rawValue) · \(Int(result.distanceMeters / 1609)) mi")
    }

    private func handleAIRouteIntent(_ text: String) -> Bool {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let lower = raw.lowercased()

        let prefixes = [
            "route to ", "navigate to ", "go to ",
            "rota para ", "navegar para ", "direcao para ", "direção para "
        ]
        guard let match = prefixes.first(where: { lower.hasPrefix($0) }) else { return false }
        let destination = String(raw.dropFirst(match.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard destination.count >= 3 else { return false }
        destinationAddress = destination
        calculateRoute(to: destination)
        return true
    }

    private func buildAINavigationContext() -> String {
        var ctx: [String] = []
        ctx.append("Truck: \(truckProfile.truckType.rawValue), \(String(format: "%.1fm", truckProfile.heightMeters)) tall, \(String(format: "%.1ft", truckProfile.weightTonnes)) GVW, hazmat=\(truckProfile.hasHazmat)")
        if let loc = locationManager.currentLocation {
            ctx.append(String(format: "Current GPS: %.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
            if loc.speed >= 0 { ctx.append(String(format: "Speed: %.0f mph", loc.speed * 2.23694)) }
        }
        if isNavigating {
            ctx.append("NAVIGATING to: \(destinationAddress)")
            ctx.append("Distance: \(regionalSettings.formatDistance(activeDistanceMeters))")
            let mins = Int(activeDurationSeconds / 60); ctx.append("ETA: \(mins / 60)h \(mins % 60)m")
            ctx.append("Route provider: \(lastRoutingProvider.rawValue)")
            if let toll = currentTollResult, toll.hasTolls { ctx.append("Tolls: \(toll.formattedTotal)") }
        } else { ctx.append("NOT navigating — idle on map") }
        if let weather = weatherService.currentWeather { ctx.append("Weather: \(weather.condition), \(weather.temperatureText)") }
        if let diesel = publicDieselPrice { ctx.append(String(format: "Diesel: $%.2f/%@", diesel.dieselPrice, diesel.unitLabel)) }
        return ctx.joined(separator: "\n")
    }
}

#if DEBUG
private enum HorizonViewFirstGpsFixLogged {
    static var didLog = false
}
#endif
