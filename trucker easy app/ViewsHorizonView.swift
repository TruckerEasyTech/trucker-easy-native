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

private func agentLogHorizon(
    runId: String,
    hypothesisId: String,
    location: String,
    message: String,
    data: [String: Any] = [:]
) {
    let payload: [String: Any] = [
        "sessionId": "ff95f6",
        "runId": runId,
        "hypothesisId": hypothesisId,
        "location": location,
        "message": message,
        "data": data,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          var line = String(data: json, encoding: .utf8) else { return }
    line.append("\n")
    let path = "/Users/thaiskeller/Desktop/trucker easy app/.cursor/debug-ff95f6.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Horizon View (Tab 1) — Map + Load Management
struct HorizonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var dispatchService = DispatchService.shared
    @Query private var trips: [Trip]
    @Query private var geofences: [GeofenceRegion]

    @State private var locationManager = LocationManager()
    @State private var selectedMapStyle: MapStyleOption = .standard
    @State private var mapAlerts: [MapAlert] = []
    @State private var route: MKRoute?
    @State private var truckRoute: TruckRoute?
    @State private var lastRoutingProvider: RoutingService.RoutingProvider = .unknown
    @State private var routeSteps: [DisplayRouteStep] = []
    @State private var currentStepIndex = 0
    @State private var showingSteps = false

    @State private var navigationEngine = NavigationEngine()
    @State private var restrictionWarningManager = TruckRestrictionWarningManager()
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
    @State private var showingTruckStops = false
    @State private var selectedTruckStop: TruckStopItem? = nil
    @State private var showingTruckStopDetail = false
    @State private var showingHOSSettings = false

    @State private var currentTruckStop: TruckStopItem? = nil
    @State private var parkingPromptShownFor: String = ""
    @State private var showingParkingPrompt = false
    @State private var lastTruckStopForReview: TruckStopItem? = nil
    @State private var showingTruckStopReview = false

    @State private var locationHistory: [CLLocation] = []
    @State private var showingGradeAlert = false
    @State private var gradeAlertMessage = ""
    @State private var gradeIsDescending = false
    @State private var showingCurveAlert = false
    @State private var showingWindAlert = false
    @State private var windAlertMph: Int = 0
    @State private var windAlertIsGust = false
    @State private var lastGradeCheckAt: Date = .distantPast
    @State private var lastCurveCheckAt: Date = .distantPast
    @State private var lastWindCheckAt: Date = .distantPast

    @State private var showingDockFinder = false
    @State private var dockResults: [NearbyStopItem] = []
    @State private var dockCheckDone = false

    @State private var foodSuggestion: FoodSuggestion? = nil
    @State private var showingFoodSuggestion = true
    @State private var lastFoodSuggestionLocation: CLLocation? = nil

    @State private var showingLoadSheet = false
    @State private var showingTripLog = false

    @State private var destinationAddress = ""
    @State private var activeRouteDestination: CLLocationCoordinate2D? = nil
    @State private var isCalculatingRoute = false
    @State private var routeError: String?
    @State private var showingRouteError = false
    @State private var routingNotice: String?
    @State private var showingRoutingNotice = false
    @AppStorage("truckSafeOnlyMode") private var truckSafeOnlyMode = false
    @State private var pendingFallbackRoute: TruckRoute?
    @State private var pendingFallbackProvider: RoutingService.RoutingProvider = .unknown
    @State private var showingFallbackConfirmation = false
    @State private var hasAcceptedFallbackThisSession = false

    @State private var bottomSheetExpanded = false
    @State private var launchSafeScreenHeight: CGFloat = UIScreen.main.bounds.height
    @State private var isIdleBottomSheetReady = false

    private var idleBottomSheetHeight: CGFloat {
        bottomSheetExpanded ? launchSafeScreenHeight * 0.70 : 120
    }

    private var navigationTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 52
    }

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
    @State private var nearbyWeighStationName = "Nearby Weigh Station"

    @State private var showingScaleAlert = false
    @State private var scaleAlertName = "Weigh Station"
    @State private var scaleAlertDistanceMiles: Double = 5.0
    @State private var scaleAlertStatus: ScaleAlertBanner.ScaleStatus = .unknown
    @State private var lastScaleCheckLocation: CLLocation? = nil

    @State private var showingCheapestDiesel = false
    @State private var cheapestDieselStop: TruckStopItem? = nil
    @State private var publicDieselPrice: FuelPricePoint? = nil

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

    @State private var logisticsNewsService = LogisticsNewsService.shared

    @State private var reviewTargetStop: TruckStopItem? = nil
    @State private var showingStopReview = false

    @State private var showingFacilityReview = false
    @State private var facilityReviewType: FacilityReviewType = .pickup
    @State private var loadPickedUp = false
    @State private var pendingDeliveryAction: (() -> Void)? = nil

    @State private var showingArrival = false
    @State private var arrivalDestinationName = ""
    @State private var lastRerouteAt: Date = .distantPast

    private var gpsIsLive: Bool {
        guard let loc = locationManager.currentLocation else { return false }
        let age = abs(loc.timestamp.timeIntervalSinceNow)
        return age <= 8 && loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 80
    }

    private var gpsStatusText: String {
        guard let loc = locationManager.currentLocation else {
            return locationManager.lastLocationError ?? "GPS searching"
        }
        let age = Int(abs(loc.timestamp.timeIntervalSinceNow))
        if gpsIsLive { return "GPS live · ±\(Int(loc.horizontalAccuracy))m" }
        if age <= 8, loc.horizontalAccuracy >= 0 {
            return "GPS weak · ±\(Int(loc.horizontalAccuracy))m"
        }
        return "GPS stale · \(age)s"
    }
    @State private var lastOpsRefreshAt: Date = .distantPast
    @State private var lastOpsRefreshLocation: CLLocation? = nil
    @State private var lastExternalRefreshAt: Date = .distantPast
    @State private var lastExternalRefreshLocation: CLLocation? = nil

    @State private var voiceManager = VoiceNavigationManager.shared
    @State private var countryCompliance = CountryComplianceManager.shared
    @State private var fleetTelemetryService = FleetTelemetryService.shared
    @State private var jurisdictionPolicyService = JurisdictionPolicyService.shared
    @State private var operationalFeedService = OperationalFeedService.shared
    @State private var showingSpeedComplianceAlert = false
    @State private var speedComplianceMessage = ""
    @State private var lastSpeedComplianceAlertAt: Date = .distantPast
    @State private var geofenceInsideState: [UUID: Bool] = [:]
    @State private var showDataDiagnostics = false

    var activeTrip: Trip? { trips.first(where: { $0.isActive }) }
    var lang: AppLanguage { regionalSettings.currentLanguage }
    private var isNavigating: Bool { truckRoute != nil || route != nil }
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
            .toolbar(isNavigating ? .hidden : .visible, for: .tabBar)
            // ━━━ NUCLEAR FIX: white background behind EVERYTHING ━━━
            .background(Color.white.ignoresSafeArea())
    }

    // MARK: - Lifecycle + onChange modifiers
    @ViewBuilder private var withLifecycleModifiers: some View {
        mainStack
            .onAppear {
                isIdleBottomSheetReady = false
                launchSafeScreenHeight = UIScreen.main.bounds.height
                DispatchQueue.main.async {
                    self.isIdleBottomSheetReady = true
                }
                // #region agent log
                agentLogHorizon(
                    runId: "baseline",
                    hypothesisId: "H1",
                    location: "ViewsHorizonView.swift:onAppear",
                    message: "HorizonView appeared",
                    data: [
                        "isNavigating": isNavigating,
                        "hasTruckRoute": truckRoute != nil,
                        "hasMapKitRoute": route != nil,
                        "launchSafeScreenHeight": launchSafeScreenHeight,
                        "isIdleBottomSheetReady": isIdleBottomSheetReady
                    ]
                )
                // #endregion
                // Clear ALL old route caches to prevent stale data from causing issues
                for key in ["offlineRouteCache_v1", "offlineRouteCache_v2"] {
                    UserDefaults.standard.removeObject(forKey: key)
                }
                locationManager.requestPermission()
                locationManager.startTracking()
                #if canImport(HealthKit)
                if let hk = HealthKitManager.shared { hk.requestAuthorization() }
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    loadFoodSuggestion()
                    if let loc = locationManager.currentLocation {
                        if truckStopService.nearbyStops.isEmpty {
                            lastScaleCheckLocation = loc
                            Task {
                                await truckStopService.searchNearby(location: loc)
                                await MainActor.run {
                                    truckStopService.applyOperationalSignals(operationalFeedService.parkingSignals)
                                    updateCheapestDiesel(); checkForNearbyScales(from: loc); refreshNearestParking(from: loc)
                                }
                            }
                        }
                        Task {
                            await fleetTelemetryService.refreshIfNeeded()
                            await countryCompliance.refreshIfNeeded(for: loc)
                            await jurisdictionPolicyService.refreshIfNeeded(for: loc)
                            await operationalFeedService.refreshIfNeeded(for: loc.coordinate)
                            await MainActor.run {
                                syncRegionalPolicyFromLocation()
                                operationalFeedService.applyWeighSignals()
                                truckStopService.applyOperationalSignals(operationalFeedService.parkingSignals)
                                refreshNearestParking(from: loc)
                            }
                        }
                        Task { await weatherService.refresh(for: loc.coordinate) }
                    }
                    loadRemoteAlerts()
                }
                let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
                let todayISO = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
                if lastMoodCheckDateString != todayStr && lastCheckInDateStr == todayISO {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        showingMoodCheck = true; lastMoodCheckDateString = todayStr
                    }
                }
                startSpeedMonitoringForDusk()
                Task { await fetchPendingDispatchLoads() }
                let hos = regionalSettings.hosRules
                hosContext.updateRules(maxDriving: hos.maxDrivingHours, serviceWindow: hos.serviceWindowHours,
                                       breakAfter: hos.mandatoryBreakAfterHours, breakMinutes: hos.mandatoryBreakMinutes)
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
            .dotSpeedFeeder(locationManager: locationManager, hosContext: hosContext)
            .onChange(of: truckProfile) { _, newProfile in newProfile.save() }
            .onChange(of: selectedNearbyCategory) { _, cat in
                nearbyItems = []; if let cat = cat { searchNearby(category: cat) }
            }
            .onChange(of: route) { _, newRoute in
                if newRoute == nil && truckRoute == nil { routeSteps = []; currentStepIndex = 0; showingSteps = false }
            }
            .onChange(of: truckRoute) { _, newHere in
                if newHere == nil && route == nil {
                    routeSteps = []; currentStepIndex = 0; showingSteps = false
                    currentTollResult = nil; currentProfitability = nil
                }
            }
            .onChange(of: isNavigating) { _, navigating in
                UIApplication.shared.isIdleTimerDisabled = navigating
                locationManager.setNavigationMode(navigating)
                if navigating {
                    bottomSheetExpanded = false; showingAIChat = false; showingSteps = false
                    showingTruckStops = false; selectedNearbyCategory = nil; showingDispatchAlert = false
                    showingRouteError = false; routeError = nil
                }
            }
            .onChange(of: dispatchService.pendingLoad) { _, newLoad in
                if let load = newLoad { pendingDispatchLoad = load; withAnimation { showingDispatchAlert = true } }
            }
            .onChange(of: regionalSettings.currentRegion) { _, _ in
                let hos = regionalSettings.hosRules
                hosContext.updateRules(maxDriving: hos.maxDrivingHours, serviceWindow: hos.serviceWindowHours,
                                       breakAfter: hos.mandatoryBreakAfterHours, breakMinutes: hos.mandatoryBreakMinutes)
            }
            .onChange(of: regionalSettings.currentLanguage) { _, newLang in
                navigationEngine.language = newLang; VoiceNavigationManager.shared.resetForNewRoute()
            }
            .onChange(of: locationManager.currentLocation?.timestamp) { _, _ in handleLocationUpdate() }
            .onChange(of: locationManager.currentLocation?.timestamp) { _, _ in
                print("[DBG][H16] gps status update='\(gpsStatusText)' live=\(gpsIsLive)")
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
                HorizonTruckSettingsSheet(profile: $truckProfile, lang: lang)
                    .presentationDetents([.medium]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingHOSSettings) {
                HOSSettingsSheet(hos: $truckStopService.hos)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(item: $selectedTruckStop) { stop in
                TruckStopDetailSheet(stop: stop, hos: truckStopService.hos, onNavigate: { truckStop in
                    calculateRoute(to: truckStop.coordinate, address: truckStop.name); showingTruckStops = false
                })
                .presentationDetents([.large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingStopReview) {
                if let stop = reviewTargetStop {
                    StopReviewSheet(stop: stop) { review in
                        print("StopReview submitted for \(review.stopName): service=\(review.serviceRating) shower=\(review.showerRating) overall=\(review.overallRating)")
                    }
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showingTruckStopReview) {
                if let stop = lastTruckStopForReview {
                    HorizonTruckStopReviewSheet(stop: stop) { showingTruckStopReview = false; lastTruckStopForReview = nil }
                        .presentationDetents([.large]).presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showingFacilityReview) {
                if let load = activeLoad {
                    FacilityReviewSheet(load: load, type: facilityReviewType,
                        onSubmit: { review in
                            print("FacilityReview: \(review.type) at \(review.companyName ?? load.loadNumber)")
                            pendingDeliveryAction?(); pendingDeliveryAction = nil
                        },
                        onSkip: { pendingDeliveryAction?(); pendingDeliveryAction = nil })
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
                HorizonMoodCheckSheet(lang: lang, onSubmit: { _ in showingMoodCheck = false }, onSkip: { showingMoodCheck = false })
                    .presentationDetents([.medium]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingShareTrip) {
                ShareTripProgressSheet(trip: activeTrip, route: route, locationManager: locationManager, isPresented: $showingShareTrip)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingWeighStation) {
                WeighStationStatusSheet(stationName: nearbyWeighStationName, isPresented: $showingWeighStation)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingHosDetail) {
                DotHosDetailSheet(hosContext: hosContext)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingFuelReport) {
                if let load = activeLoad {
                    HorizonFuelReportSheet(load: load) { gallons, price, station in
                        print("FuelReport: \(gallons) gal @ $\(price) at \(station ?? "unknown")")
                    }
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
                }
            }
            .alert("Route Error", isPresented: $showingRouteError) { Button("OK") {} }
                message: { Text(routeError ?? "Could not calculate route") }
            .alert("Routing Notice", isPresented: $showingRoutingNotice) { Button("OK") {} }
                message: { Text(routingNotice ?? "Route provider changed.") }
            .confirmationDialog("Truck-safe route unavailable", isPresented: $showingFallbackConfirmation, titleVisibility: .visible) {
                Button("Continue with fallback GPS") { applyPendingFallbackRoute() }
                Button("Cancel", role: .cancel) { pendingFallbackRoute = nil; pendingFallbackProvider = .unknown; bottomSheetExpanded = false }
            } message: {
                Text("No truck-safe provider responded. Continue with \(pendingFallbackProvider.rawValue) for basic navigation while restrictions may be limited.")
            }
    }

    // MARK: - Main Map ZStack

    @ViewBuilder private var mainStack: some View {
        ZStack(alignment: .top) {
            // Layer 0: SOLID WHITE base — kills any dark bleed from TabView/dark mode
            Color.white.ignoresSafeArea(.all)

            Group {
                #if canImport(MapboxMaps)
                if MapProviderConfig.isMapboxHorizonRendererEnabled {
                    HorizonMapboxSurface(
                        selectedMapStyle: selectedMapStyle,
                        locationManager: locationManager,
                        mapAlerts: mapAlerts,
                        route: route,
                        truckRoute: truckRoute,
                        isNavigating: isNavigating,
                        onStyleChange: { selectedMapStyle = $0 },
                        onControlsReady: { zoomIn, zoomOut, recenter in
                            mapZoomIn = zoomIn; mapZoomOut = zoomOut; mapRecenter = recenter
                        },
                        truckStops: truckStopService.nearbyStops,
                        onTruckStopTapped: { stop in selectedTruckStop = stop }
                    )
                } else {
                    HorizonMapSurface(
                        selectedMapStyle: selectedMapStyle,
                        locationManager: locationManager,
                        mapAlerts: mapAlerts,
                        route: route,
                        truckRoute: truckRoute,
                        isNavigating: isNavigating,
                        onStyleChange: { selectedMapStyle = $0 },
                        onControlsReady: { zoomIn, zoomOut, recenter in
                            mapZoomIn = zoomIn; mapZoomOut = zoomOut; mapRecenter = recenter
                        },
                        truckStops: truckStopService.nearbyStops,
                        onTruckStopTapped: { stop in selectedTruckStop = stop }
                    )
                }
                #else
                HorizonMapSurface(
                    selectedMapStyle: selectedMapStyle,
                    locationManager: locationManager,
                    mapAlerts: mapAlerts,
                    route: route,
                    truckRoute: truckRoute,
                    isNavigating: isNavigating,
                    onStyleChange: { selectedMapStyle = $0 },
                    onControlsReady: { zoomIn, zoomOut, recenter in
                        mapZoomIn = zoomIn; mapZoomOut = zoomOut; mapRecenter = recenter
                    },
                    truckStops: truckStopService.nearbyStops,
                    onTruckStopTapped: { stop in selectedTruckStop = stop }
                )
                #endif
            }
            .ignoresSafeArea()
            .environment(\.colorScheme, .light) // Force light — prevents dark mode from affecting map container

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

            // Idle map chrome: keep only a compact GPS chip on trailing side.
            // Removes duplicated icon rails and matches cleaner professional layouts.
            if !isNavigating {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Spacer().frame(height: 56)
                        idleTrailingGpsPill
                        Spacer()
                    }
                    .padding(.trailing, 10)
                }
                .onAppear {
                    // #region agent log
                    agentLogHorizon(
                        runId: "post-repro-2",
                        hypothesisId: "H-ui-8",
                        location: "ViewsHorizonView.swift:idleMapChrome",
                        message: "idle chrome simplified (single rail)",
                        data: [
                            "hasLeadingIconRail": false,
                            "hasTopHUD": true,
                            "hasTrailingGpsPill": true
                        ]
                    )
                    // #endregion
                    print("[DBG][H-ui-8] idle chrome simplified: no leading rail, trailing GPS pill only")
                }
            }

            navigationOverlays
            alertOverlays
            mapControlsOverlay
            warningsDispatchAndBottomOverlays
            topInstructionLane
        }
    }

    // MARK: - Navigation Overlays

    /// Left column: icon-only quick actions + HOS (same gestures as before; avoids overlapping TopHUD and bottom parking pill).
    @ViewBuilder private var idleLeadingToolColumn: some View {
        VStack(spacing: 8) {
            idleQuickToolIcon(icon: "mappin.and.ellipse", label: "Places") {
                print("[DBG][H14] quick tool tapped=Places")
                showingGlobalSearch = true
            }
            idleQuickToolIcon(icon: "fuelpump.fill", label: "Fuel") {
                print("[DBG][H14] quick tool tapped=Fuel")
                selectedNearbyCategory = .fuel
                searchNearby(category: .fuel)
            }
            idleQuickToolIcon(icon: "scalemass.fill", label: "DOT / Weigh") {
                print("[DBG][H14] quick tool tapped=DOT/Weigh")
                selectedNearbyCategory = .weigh
                searchNearby(category: .weigh)
            }
            idleQuickToolIcon(icon: "moon.zzz.fill", label: "Rest") {
                print("[DBG][H14] quick tool tapped=Rest")
                selectedNearbyCategory = .rest
                searchNearby(category: .rest)
            }
            Menu {
                Button { showingHosDetail = true } label: {
                    Label("HOS detail", systemImage: "doc.text.fill")
                }
                Button { showingHOSSettings = true } label: {
                    Label("HOS settings", systemImage: "gearshape.fill")
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "#c9a84c"))
                    Text("HOS")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .frame(width: 44, height: 52)
                .background(Color(hex: "#1a1d23"))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            }
            .accessibilityLabel("HOS menu")
        }
        .onAppear {
            print("[DBG][H15] idle leading tools shown gps='\(gpsStatusText)' live=\(gpsIsLive)")
        }
    }

    /// Top-trailing GPS status — TopHUD is leading-only, so this stays clear of those buttons.
    @ViewBuilder private var idleTrailingGpsPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gpsIsLive ? Color(hex: "#10b981") : Color(hex: "#f59e0b"))
                .frame(width: 7, height: 7)
            Text(gpsStatusText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 148, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(hex: "#0d1117").opacity(0.88))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func idleQuickToolIcon(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color(hex: "#1a1d23"))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var navigationOverlays: some View {
        if isNavigating {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("N")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#151922").opacity(0.96))
                    .clipShape(Capsule())

                    ForEach(Array(navigationAlertDistanceBadges.enumerated()), id: \.offset) { _, badge in
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(badge)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#b91c1c"))
                        .clipShape(Capsule())
                    }

                    Button(action: { showingTruckStops = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            Text("More")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(hex: "#232833"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 1) {
                        Text(navSpeedLimitText)
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white)
                        Text(navCurrentSpeedText)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(navOverspeeding ? Color(hex: "#ef4444") : Color(hex: "#22d474"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#11151d").opacity(0.97))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .padding(.leading, 10)
                .onAppear {
                    // #region agent log
                    agentLogHorizon(
                        runId: "ui-integration-1",
                        hypothesisId: "H-ui-left-rail",
                        location: "ViewsHorizonView.swift:navigationOverlays",
                        message: "left rail visible",
                        data: [
                            "alertsShown": navigationAlertDistanceBadges.count,
                            "speedLimitText": navSpeedLimitText,
                            "speedText": navCurrentSpeedText
                        ]
                    )
                    // #endregion
                }

                Spacer()
                HorizonNavigationInfoStrip(
                    stops: truckStopService.nearbyStops,
                    scaleAlertName: scaleAlertName,
                    scaleAlertDistanceMiles: scaleAlertDistanceMiles,
                    scaleAlertStatus: scaleAlertStatus,
                    hasScaleAhead: showingScaleAlert,
                    onSelectStop: { stop in selectedTruckStop = stop },
                    useMiles: regionalSettings.currentRegion.distanceUnit == "mi"
                )
                .padding(.trailing, 8)
                .onAppear {
                    // #region agent log
                    agentLogHorizon(
                        runId: "ui-integration-1",
                        hypothesisId: "H-ui-right-rail",
                        location: "ViewsHorizonView.swift:navigationOverlays",
                        message: "right rail visible",
                        data: [
                            "hasScaleAhead": showingScaleAlert,
                            "scaleDistanceMi": scaleAlertDistanceMiles,
                            "stopsCount": truckStopService.nearbyStops.count
                        ]
                    )
                    // #endregion
                }
            }
            .padding(.top, max(118, navigationTopInset + 66))
            .transition(.opacity)
        }

        if showingSteps, isNavigating, !routeSteps.isEmpty {
            VStack {
                Spacer().frame(height: 160)
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
                    Text("You have arrived!")
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
                        Text("Done").font(.system(size: 16, weight: .bold)).foregroundColor(.black)
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
    }

    @ViewBuilder private var topInstructionLane: some View {
        if isNavigating, !routeSteps.isEmpty, currentStepIndex < routeSteps.count {
            VStack(spacing: 4) {
                HorizonNavigationStepBanner(
                    step: routeSteps[currentStepIndex],
                    stepIndex: currentStepIndex,
                    totalSteps: routeSteps.count,
                    formatDistance: { m in regionalSettings.formatDistance(m) },
                    nextStepInstruction: routeSteps.indices.contains(currentStepIndex + 1)
                        ? routeSteps[currentStepIndex + 1].instructions
                        : nil,
                    onPrevStep: {
                        guard currentStepIndex > 0 else { return }
                        syncNavigationStepIndexFromUI(currentStepIndex - 1)
                    },
                    onNextStep: {
                        guard currentStepIndex < routeSteps.count - 1 else { return }
                        syncNavigationStepIndexFromUI(currentStepIndex + 1)
                    },
                    onToggleList: { showingSteps.toggle() },
                    onMicTap: {
                        withAnimation(.spring(response: 0.28)) { showingAIChat = true }
                        // #region agent log
                        print("[DBG][H-ui-10] nav mic tapped, AI panel requested")
                        // #endregion
                    },
                    speedText: {
                        guard let speed = locationManager.currentLocation?.speed, speed > 0 else { return nil }
                        return regionalSettings.currentRegion.distanceUnit == "mi"
                            ? "\(Int(speed * 2.23694)) mph" : "\(Int(speed * 3.6)) km/h"
                    }()
                )
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, max(2, navigationTopInset - 2))
                .onAppear {
                    // #region agent log
                    agentLogHorizon(
                        runId: "post-repro-5",
                        hypothesisId: "H-ui-top-lane",
                        location: "ViewsHorizonView.swift:topInstructionLane",
                        message: "top lane rendered via safeAreaInset",
                        data: [
                            "safeAreaTop": navigationTopInset,
                            "showingSteps": showingSteps
                        ]
                    )
                    // #endregion
                }

                if let nextInstruction = routeSteps.indices.contains(currentStepIndex + 1)
                    ? routeSteps[currentStepIndex + 1].instructions
                    : nil {
                    HStack {
                        HStack(spacing: 6) {
                            Text("Then")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(Color(hex: "#0d1117"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#facc15"))
                                .clipShape(Capsule())
                            Image(systemName: "arrow.turn.up.left")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Text(nextInstruction)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#111827").opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .padding(.leading, AppTheme.Spacing.md)
                        Spacer()
                    }
                }
            }
            .zIndex(900)
            .allowsHitTesting(true)
        }
    }

    // MARK: - Alert Overlays

    @ViewBuilder private var alertOverlays: some View {
        if showingScaleAlert {
            VStack {
                Spacer().frame(height: isNavigating ? 170 : 110)
                HStack {
                    ScaleAlertBanner(stationName: scaleAlertName, distanceMiles: scaleAlertDistanceMiles,
                                     status: scaleAlertStatus, lang: lang,
                                     onDismiss: { withAnimation { showingScaleAlert = false } })
                        .frame(maxWidth: 320).padding(.leading, AppTheme.Spacing.md)
                    Spacer()
                }
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: showingScaleAlert)
        }

        if showingSpeedComplianceAlert {
            VStack {
                Spacer().frame(height: isNavigating ? 230 : 160)
                HStack {
                    SpeedComplianceBanner(message: speedComplianceMessage,
                                          onDismiss: { withAnimation { showingSpeedComplianceAlert = false } })
                        .frame(maxWidth: 340).padding(.leading, AppTheme.Spacing.md)
                    Spacer()
                }
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35), value: showingSpeedComplianceAlert)
        }

        if showingGradeAlert {
            VStack {
                Spacer().frame(height: isNavigating ? 230 : 160)
                HStack {
                    GradeAlertBanner(message: gradeAlertMessage, isDescending: gradeIsDescending,
                                     onDismiss: { withAnimation { showingGradeAlert = false } })
                        .frame(maxWidth: 320).padding(.leading, AppTheme.Spacing.md)
                    Spacer()
                }
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35), value: showingGradeAlert)
        }

        if showingCurveAlert {
            VStack {
                Spacer().frame(height: isNavigating ? 230 : 160)
                HStack {
                    SharpCurveAlertBanner(onDismiss: { withAnimation { showingCurveAlert = false } })
                        .frame(maxWidth: 300).padding(.leading, AppTheme.Spacing.md)
                    Spacer()
                }
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: showingCurveAlert)
        }

        if showingWindAlert {
            VStack {
                Spacer().frame(height: isNavigating ? 290 : 220)
                HStack {
                    WindAlertBanner(mph: windAlertMph, isGust: windAlertIsGust,
                                    onDismiss: { withAnimation { showingWindAlert = false } })
                        .frame(maxWidth: 300).padding(.leading, AppTheme.Spacing.md)
                    Spacer()
                }
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35), value: showingWindAlert)
        }

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
                TruckStopsPanel(stops: truckStopService.nearbyStops, hos: truckStopService.hos,
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
                if isNavigating && showParkingPill {
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
                    .padding(.leading, 12).padding(.bottom, 140)
                    .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                // Idle: stack parking above zoom on the right so it never sits under the leading tool column.
                VStack(spacing: 10) {
                    if !isNavigating && showParkingPill {
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
                        .transition(.scale.combined(with: .opacity))
                    }
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
                .padding(.trailing, 12).padding(.bottom, isNavigating ? 140 : 180)
            }
        }
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

        // Dispatch Load Alert
        if showingDispatchAlert, let load = pendingDispatchLoad, !isNavigating {
            VStack {
                Spacer()
                HorizonDispatchLoadBanner(load: load, lang: lang) {
                    dispatchService.acknowledgeLoad(load) { _ in }
                    dispatchService.startRoute(for: load)
                    activeLoad = load; pendingDispatchLoad = nil; showingDispatchAlert = false
                    calculateRoute(to: load.destinationCoordinate, address: load.destinationAddress)
                } onDecline: {
                    pendingDispatchLoad = nil; showingDispatchAlert = false
                }
                .padding(.horizontal, AppTheme.Spacing.md).padding(.bottom, 120)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: showingDispatchAlert)
        }

        // Active Load Bar
        if let load = activeLoad, !showingDispatchAlert {
            VStack {
                Spacer()
                HorizonActiveLoadBar(load: load, isPickedUp: loadPickedUp,
                    onFuelReport: { showingFuelReport = true },
                    onMarkPickedUp: {
                        facilityReviewType = .pickup
                        pendingDeliveryAction = { loadPickedUp = true }
                        showingFacilityReview = true
                    },
                    onMarkDelivered: {
                        facilityReviewType = .delivery
                        pendingDeliveryAction = {
                            dispatchService.markDelivered(load) { _ in }
                            activeLoad = nil; loadPickedUp = false
                        }
                        showingFacilityReview = true
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
                } onDismiss: {
                    withAnimation { showingParkingPrompt = false }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: showingParkingPrompt)
        }

        // Wellness Food Suggestion
        if showingFoodSuggestion, let suggestion = foodSuggestion, !isNavigating {
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

        // Share Trip FAB
        if isNavigating {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showingShareTrip = true }) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white).frame(width: 44, height: 44)
                            .background(AppTheme.Colors.accent).cornerRadius(12)
                            .shadow(color: AppTheme.Colors.accent.opacity(0.5), radius: 8)
                    }
                    .padding(.trailing, AppTheme.Spacing.md).padding(.bottom, 100)
                }
            }
        }

        // ━━━ Bottom Sheet / ETA Bar ━━━
        VStack(spacing: 0) {
            Spacer().allowsHitTesting(false)
            if isNavigating {
                // Navigation mode: do not build idle bottom sheet in hierarchy.
                // This prevents stale expanded sheet surfaces from overlaying the map.
                etaBar
                    .zIndex(2)
                    .allowsHitTesting(true)
                    .id("nav-eta-bar")
                    .onAppear {
                        // #region agent log
                        print("[DBG][OVR][H-ovr-1] bottom overlay branch=navigating etaBar hitTest=true")
                        // #endregion
                    }
            } else {
                Group {
                    if isIdleBottomSheetReady {
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
                            }
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(hex: "#0d1117"))
                    }
                }
                .frame(height: idleBottomSheetHeight)
                .clipped()
                .shadow(color: .black.opacity(0.25), radius: 8, y: -2)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: bottomSheetExpanded)
                .id("idle-bottom-sheet")
                .allowsHitTesting(true)
                .onAppear {
                    // #region agent log
                    print("[DBG][OVR][H-ovr-1] bottom overlay branch=idle bottomSheet ready=\(isIdleBottomSheetReady) h=\(Int(idleBottomSheetHeight)) hitTest=true")
                    // #endregion
                }
            }
        }
        .id(isNavigating ? "nav-mode-overlay" : "idle-mode-overlay")
    }

    // MARK: - ETA Bar (navigation, OPAQUE solid background)

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
            // #region agent log
            agentLogHorizon(
                runId: "ui-integration-1",
                hypothesisId: "H-ui-bottom-bar",
                location: "ViewsHorizonView.swift:etaBar",
                message: "bottom telemetry bar visible",
                data: [
                    "durationSec": activeDurationSeconds,
                    "distanceMeters": activeDistanceMeters,
                    "arrivalClock": formatArrivalClock()
                ]
            )
            // #endregion
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
                            onClose: { showDataDiagnostics = false })
                            .frame(maxWidth: 300)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                        DieselMarketBanner(pricePoint: publicDieselPrice) { showingTruckStops = true }
                            .frame(maxWidth: 300)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.leading, AppTheme.Spacing.md).padding(.bottom, 150)
                Spacer()
            }
        }
    }

    // MARK: - Location Update Handler

    private func handleLocationUpdate() {
        guard let loc = locationManager.currentLocation else { return }
        let gpsSpeedMph = max(0, loc.speed * 2.23694)

        navigationEngine.updateLocation(loc)
        restrictionWarningManager.updateLocation(loc)
        evaluateTruckSpeedCompliance(using: loc)
        evaluateGeofenceEvents(using: loc)
        hosContext.feedSpeed(fleetTelemetryService.preferredSpeedMph(gpsSpeedMph: gpsSpeedMph))

        #if DEBUG
        if !HorizonViewFirstGpsFixLogged.didLog,
           loc.horizontalAccuracy > 0, loc.horizontalAccuracy < 80 {
            HorizonViewFirstGpsFixLogged.didLog = true
            print("[HorizonGPS] firstFix acc=\(Int(loc.horizontalAccuracy))m speedMph=\(Int(gpsSpeedMph)) bearing=\(Int(locationManager.bestBearing))°")
        }
        #endif

        let now = Date()
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
                    truckStopService.applyOperationalSignals(operationalFeedService.parkingSignals)
                    refreshNearestParking(from: loc)
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
                await MainActor.run {
                    publicDieselPrice = publicPrice
                    if weatherService.currentWeather != nil && !weatherShownThisLaunch {
                        weatherShownThisLaunch = true
                        showingWeather = true
                    }
                }
            }
        }

        let shouldRefresh: Bool
        if truckStopService.nearbyStops.isEmpty { shouldRefresh = true }
        else if let last = lastScaleCheckLocation, loc.distance(from: last) > (isNavigating ? 5_000 : 16_000) { shouldRefresh = true }
        else { shouldRefresh = false }
        if shouldRefresh {
            lastScaleCheckLocation = loc
            Task {
                await truckStopService.searchNearby(location: loc)
                await MainActor.run {
                    truckStopService.applyOperationalSignals(operationalFeedService.parkingSignals)
                    updateCheapestDiesel(); checkForNearbyScales(from: loc); refreshNearestParking(from: loc)
                }
            }
        }

        let speed = max(0, loc.speed)
        checkTruckStopProximity(from: loc, speed: speed)
        locationHistory.append(loc)
        if locationHistory.count > 20 { locationHistory.removeFirst() }
        checkGradeAlert(from: loc); checkSharpCurveAlert(at: loc); checkWindAlert()
        if isNavigating { checkDestinationDock(from: loc) }
        if speed <= 1.0 && !showingFoodSuggestion && !isNavigating && currentTruckStop == nil {
            loadFoodSuggestion()
        }
    }

    // MARK: - Route Calculation

    private func calculateRoute(to coordinate: CLLocationCoordinate2D, address: String) {
        let isReroute = isNavigating // If already navigating, this is a reroute
        guard let origin = locationManager.currentLocation else {
            if !isReroute { routeError = "Location unavailable. Check GPS."; showingRouteError = true }
            return
        }
        // #region agent log
        agentLogHorizon(
            runId: "baseline",
            hypothesisId: "H10",
            location: "ViewsHorizonView.swift:calculateRoute(to:coordinate,address)",
            message: "Coordinate route request started",
            data: [
                "address": address,
                "originLat": origin.coordinate.latitude,
                "originLon": origin.coordinate.longitude,
                "destLat": coordinate.latitude,
                "destLon": coordinate.longitude,
                "straightLineMeters": Int(origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)))
            ]
        )
        // #endregion
        if !isReroute { isCalculatingRoute = true; bottomSheetExpanded = false }
        print("[Route] \(isReroute ? "REROUTE" : "NEW") → \(address) from \(String(format: "%.5f,%.5f", origin.coordinate.latitude, origin.coordinate.longitude))")
        Task {
            defer {
                Task { @MainActor in
                    if !isReroute { isCalculatingRoute = false }
                }
            }
            do {
                let routing = RoutingService.shared
                let result = try await routing.calculateTruckRoute(from: origin, to: coordinate, destinationName: address, profile: truckProfile)
                await MainActor.run {
                    if truckSafeOnlyMode && !routing.lastProvider.isTruckAware {
                        if isReroute {
                            print("[Route] Reroute: truck-safe unavailable, keeping current route")
                            return // Don't disrupt active navigation
                        }
                        prepareFallbackRoute(result, provider: routing.lastProvider)
                        return
                    }
                    if !routing.lastProvider.isTruckAware && !isReroute { prepareFallbackRoute(result, provider: routing.lastProvider); return }
                    applyRoute(result, suppressUIErrors: isReroute, destinationCoordinate: coordinate)
                }
            } catch {
                await MainActor.run {
                    if isReroute {
                        // SILENT: don't show error during active navigation — keep current route
                        print("[Route] ⚠️ Reroute failed (keeping current route): \(error.localizedDescription)")
                        if case RoutingServiceError.allProvidersFailed = error {
                            // Back off reroute spam when providers are unavailable.
                            lastRerouteAt = Date().addingTimeInterval(150)
                        }
                    } else {
                        bottomSheetExpanded = false
                        routeError = "Unable to calculate a safe route right now. Check signal and try again."
                        showingRouteError = true
                    }
                }
            }
        }
    }

    private func calculateRoute(to address: String) {
        let isReroute = isNavigating
        guard let origin = locationManager.currentLocation else {
            if !isReroute { routeError = "Location unavailable. Check GPS."; showingRouteError = true }
            return
        }
        if !isReroute { isCalculatingRoute = true; bottomSheetExpanded = false }
        print("[Route] \(isReroute ? "REROUTE" : "NEW") → '\(address)'")
        Task {
            defer {
                Task { @MainActor in
                    if !isReroute { isCalculatingRoute = false }
                }
            }
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
                    origin.distance(from: $0.location) < origin.distance(from: $1.location)
                }
                // #region agent log
                agentLogHorizon(
                    runId: "baseline",
                    hypothesisId: "H10",
                    location: "ViewsHorizonView.swift:calculateRoute(to:address)",
                    message: "Address geocode candidates ranked by proximity",
                    data: [
                        "query": address,
                        "candidateCount": sortedByDistance.count,
                        "nearestMeters": Int(sortedByDistance.first.map { origin.distance(from: $0.location) } ?? -1),
                        "farthestMeters": Int(sortedByDistance.last.map { origin.distance(from: $0.location) } ?? -1)
                    ]
                )
                // #endregion
                guard let first = sortedByDistance.first else {
                    throw RoutingServiceError.geocodeFailed(address)
                }
                let destinationName = first.name ?? address
                let destinationDistance = origin.distance(from: first.location)
                guard destinationDistance < 1_500_000 else {
                    throw RoutingServiceError.geocodeFailed("Destination too far from current location (\(Int(destinationDistance/1000)) km)")
                }
                // #region agent log
                agentLogHorizon(
                    runId: "baseline",
                    hypothesisId: "H10",
                    location: "ViewsHorizonView.swift:calculateRoute(to:address)",
                    message: "Selected geocode candidate for routing",
                    data: [
                        "selectedName": destinationName,
                        "selectedLat": first.location.coordinate.latitude,
                        "selectedLon": first.location.coordinate.longitude,
                        "selectedDistanceMeters": Int(destinationDistance)
                    ]
                )
                // #endregion
                let routing = RoutingService.shared
                let result = try await routing.calculateTruckRoute(
                    from: origin,
                    to: first.location.coordinate,
                    destinationName: destinationName,
                    profile: truckProfile
                )
                await MainActor.run {
                    if truckSafeOnlyMode && !routing.lastProvider.isTruckAware {
                        if isReroute {
                            print("[Route] Reroute: truck-safe unavailable, keeping current route")
                            return
                        }
                        prepareFallbackRoute(result, provider: routing.lastProvider)
                        return
                    }
                    if !routing.lastProvider.isTruckAware && !isReroute { prepareFallbackRoute(result, provider: routing.lastProvider); return }
                    applyRoute(result, suppressUIErrors: isReroute, destinationCoordinate: first.location.coordinate)
                }
            } catch {
                await MainActor.run {
                    if isReroute {
                        print("[Route] ⚠️ Reroute failed (keeping current route): \(error.localizedDescription)")
                        if case RoutingServiceError.allProvidersFailed = error {
                            // Back off reroute spam when providers are unavailable.
                            lastRerouteAt = Date().addingTimeInterval(150)
                        }
                    } else {
                        bottomSheetExpanded = false
                        if let parsed = parseCoordinateAddress(address) {
                            routeError = "Address resolved to coordinates, but safe route is unavailable. Try again."
                            showingRouteError = true
                            print("[Route] Parsed coordinate route blocked for safety: \(parsed.latitude),\(parsed.longitude)")
                        } else {
                            routeError = "Could not resolve destination address. Please pick a destination from Search."
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
                instruction: "Navigate to \(destinationName)",
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
            truckNotices: [TruckRouteNotice(code: "EMERGENCY", title: "Emergency route mode", details: "Road graph unavailable; using direct guidance line.")]
        )
    }

    @MainActor
    private func syncNavigationStepIndexFromUI(_ newIndex: Int) {
        currentStepIndex = newIndex
        navigationEngine.syncStepIndexFromUI(newIndex)
        // #region agent log
        agentLogHorizon(
            runId: "post-fix",
            hypothesisId: "H5",
            location: "ViewsHorizonView.swift:syncNavigationStepIndexFromUI",
            message: "UI step change synced to NavigationEngine",
            data: [
                "newIndex": newIndex,
                "stepsCount": routeSteps.count
            ]
        )
        // #endregion
    }

    // MARK: - Apply Route (FIX #3: validates before applying)

    @MainActor
    private func applyRoute(
        _ result: TruckRoute,
        suppressUIErrors: Bool = false,
        destinationCoordinate: CLLocationCoordinate2D? = nil
    ) {
        // #region agent log
        agentLogHorizon(
            runId: "baseline",
            hypothesisId: "H2",
            location: "ViewsHorizonView.swift:applyRoute",
            message: "Horizon applyRoute called",
            data: [
                "provider": RoutingService.shared.lastProvider.rawValue,
                "coordinatesCount": result.coordinates.count,
                "stepsCount": result.steps.count,
                "distanceMeters": Int(result.distanceMeters),
                "suppressUIErrors": suppressUIErrors
            ]
        )
        // #endregion
        print("[ApplyRoute] ✅ coords=\(result.coordinates.count), steps=\(result.steps.count), dist=\(Int(result.distanceMeters))m, name='\(result.destinationName)'")
        for (i, s) in result.steps.prefix(5).enumerated() {
            print("[ApplyRoute]   step[\(i)]: '\(s.instruction)' maneuver='\(s.maneuver)' dist=\(Int(s.distanceMeters))m")
        }

        if !suppressUIErrors {
            routeError = nil
            showingRouteError = false
        }

        guard !result.coordinates.isEmpty else {
            if suppressUIErrors {
                print("[ApplyRoute] ⚠️ Suppressed error: route has no coordinates")
                return
            }
            routeError = "Route has no coordinates"; showingRouteError = true; return
        }
        guard result.distanceMeters > 0 else {
            if suppressUIErrors {
                print("[ApplyRoute] ⚠️ Suppressed error: route distance is zero")
                return
            }
            routeError = "Route distance is zero"; showingRouteError = true; return
        }

        // Bulletproof: if route has steps, use them; filter only truly empty instructions
        var steps = result.steps
            .filter { !$0.instruction.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { $0.maneuver != "depart" }
            .map { DisplayRouteStep($0) }

        // If filtering removed ALL steps, try without the depart filter
        if steps.isEmpty && !result.steps.isEmpty {
            print("[ApplyRoute] ⚠️ depart filter removed all steps, retrying without filter")
            steps = result.steps
                .filter { !$0.instruction.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { DisplayRouteStep($0) }
        }

        // Last resort: if still 0 steps, create a single "navigate to destination" step
        if steps.isEmpty {
            print("[ApplyRoute] ⚠️ STILL 0 steps after all filters — creating fallback step")
            steps = [DisplayRouteStep(RouteStep(
                instruction: "Navigate to \(result.destinationName)",
                distanceMeters: result.distanceMeters,
                durationSeconds: result.durationSeconds,
                maneuver: "continue"
            ))]
        }

        print("[ApplyRoute] final steps=\(steps.count)")

        var t = Transaction(animation: nil); t.disablesAnimations = true
        withTransaction(t) {
            bottomSheetExpanded = false; showingSteps = false
            truckRoute = result; route = nil
            routeSteps = steps; currentStepIndex = 0
        }
        activeRouteDestination = destinationCoordinate ?? result.coordinates.last
        showingFallbackConfirmation = false
        pendingFallbackRoute = nil
        pendingFallbackProvider = .unknown

        let provider = RoutingService.shared.lastProvider
        lastRoutingProvider = provider; dockCheckDone = false
        navigationEngine.language = lang
        navigationEngine.startNavigation(route: result)
        VoiceNavigationManager.shared.resetForNewRoute()

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
            // Cooldown: don't reroute more than once per 30 seconds (prevents API rate limiting)
            guard Date().timeIntervalSince(lastRerouteAt) > 30 else {
                print("[Route] Reroute skipped — cooldown active (\(Int(30 - Date().timeIntervalSince(lastRerouteAt)))s remaining)")
                return
            }
            lastRerouteAt = Date()
            guard let dest = activeRouteDestination else {
                print("[Route] Reroute skipped — destination coordinate unavailable")
                return
            }
            // #region agent log
            agentLogHorizon(
                runId: "baseline",
                hypothesisId: "H12",
                location: "ViewsHorizonView.swift:onNeedsReroute",
                message: "Reroute using authoritative destination coordinate",
                data: [
                    "destLat": dest.latitude,
                    "destLon": dest.longitude,
                    "destinationName": result.destinationName
                ]
            )
            // #endregion
            calculateRoute(to: dest, address: result.destinationName)
        }
        navigationEngine.onArrival = {
            let dest = result.destinationName.isEmpty ? "your destination" : result.destinationName
            arrivalDestinationName = dest
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
    private func prepareFallbackRoute(_ route: TruckRoute, provider: RoutingService.RoutingProvider) {
        bottomSheetExpanded = false
        let isFirstFallback = !hasAcceptedFallbackThisSession
        hasAcceptedFallbackThisSession = true
        if isFirstFallback {
            routingNotice = "Route via \(provider.rawValue) — truck restrictions may be limited."
            showingRoutingNotice = true
        }
        applyRoute(route)
    }

    @MainActor
    private func applyPendingFallbackRoute() {
        guard let pending = pendingFallbackRoute else { return }
        pendingFallbackRoute = nil; pendingFallbackProvider = .unknown
        hasAcceptedFallbackThisSession = true
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
                    let loc = item.location; let dist = location.distance(from: loc)
                    let addrText = item.address?.shortAddress ?? item.addressRepresentations?.cityWithContext ?? item.name ?? ""
                    return NearbyStopItem(name: item.name ?? "Unknown", address: addrText,
                        coordinate: loc.coordinate, distanceMeters: dist, phone: item.phoneNumber, category: category)
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
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "truck parking"
            request.region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
            guard let items = try? await MKLocalSearch(request: request).start() else { return }
            let nearest = items.mapItems.compactMap { item -> (String, Double)? in
                guard let name = item.name else { return nil }
                let coord: CLLocationCoordinate2D
                if #available(iOS 26.0, *) { coord = item.location.coordinate } else { coord = item.placemark.coordinate }
                let dist = location.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) / 1609.34
                return (name, dist)
            }.sorted { $0.1 < $1.1 }.first
            guard let (name, miles) = nearest, miles < 15 else {
                await MainActor.run { showParkingPill = false }; return
            }
            let reports = (try? await SupabaseClient.shared.fetchRecentRoadReports(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, radiusKm: 25)) ?? []
            let cutoff = Date().addingTimeInterval(-3600 * 4)
            let isFull = reports.contains { $0.report_type == "parkingFull" && $0.location_name == name && (ISO8601DateFormatter().date(from: $0.reported_at) ?? .distantPast) > cutoff }
            await MainActor.run {
                nearestParkingName = name; nearestParkingMiles = miles; nearestParkingFull = isFull
                withAnimation { showParkingPill = true }
            }
        }
    }

    // MARK: - Scale (Weigh Station) Detection

    private func checkForNearbyScales(from location: CLLocation) {
        let queries = countryCompliance.weighQueries
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        Task {
            var allItems: [MKMapItem] = []
            for query in queries {
                let req = MKLocalSearch.Request(); req.naturalLanguageQuery = query; req.region = region
                let items = (try? await MKLocalSearch(request: req).start())?.mapItems ?? []
                allItems.append(contentsOf: items)
            }
            var deduped: [MKMapItem] = []
            for item in allItems {
                let loc = item.location
                if !deduped.contains(where: { $0.location.distance(from: loc) < 500 }) { deduped.append(item) }
            }
            let heading = locationManager.currentHeading?.trueHeading
            let nearest = deduped.map { item in
                let itemLoc = item.location; let dist = location.distance(from: itemLoc)
                let isAhead: Bool
                if let heading { let diff = abs(angleDeltaDegrees(heading, location.coordinate.bearing(to: itemLoc.coordinate))); isAhead = diff <= 70 }
                else { isAhead = true }
                return (item, dist, isAhead)
            }.filter { $0.2 }.filter { $0.1 < 24_140 }.sorted { $0.1 < $1.1 }.first
            guard let (nearestItem, distMeters, _) = nearest else {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) { showingScaleAlert = false }
                }
                return
            }
            guard distMeters <= 5_000 else {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) { showingScaleAlert = false }
                }
                return
            }
            let distMiles = distMeters / 1609.34; let stationName = nearestItem.name ?? "Weigh Station"
            let weighService = WeighStationStatusService.shared
            await weighService.fetchRemoteReports()
            let liveStatus = weighService.latestStatus(for: stationName, near: nearestItem.location.coordinate)
            await MainActor.run {
                scaleAlertName = stationName; scaleAlertDistanceMiles = distMiles
                switch liveStatus {
                case .open: scaleAlertStatus = .open; case .closed: scaleAlertStatus = .closed
                case .monitoring: scaleAlertStatus = .unknown; case nil: scaleAlertStatus = .unknown
                }
                let alertTier: String
                if distMeters <= 500 {
                    alertTier = "500m"
                } else if distMeters <= 2_000 {
                    alertTier = "2km"
                } else {
                    alertTier = "5km"
                }
                // #region agent log
                agentLogHorizon(
                    runId: "post-repro-6",
                    hypothesisId: "H-scale-distance-tiers",
                    location: "ViewsHorizonView.swift:checkForNearbyScales",
                    message: "scale alert distance tier selected",
                    data: [
                        "distanceMeters": Int(distMeters),
                        "tier": alertTier,
                        "stationName": stationName
                    ]
                )
                // #endregion
                withAnimation(.spring(response: 0.4)) { showingScaleAlert = true }
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
            do { try await SupabaseClient.shared.submitRoadReport(payload) }
            catch { print("MapAlert: sync failed — \(error.localizedDescription)") }
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
            } catch { print("MapAlerts: remote fetch failed — \(error.localizedDescription)") }
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
        } catch { print("HorizonView: fetchPendingDispatchLoads failed — \(error.localizedDescription)") }
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
        let legalLimit = jurisdictionPolicyService.effectiveSpeedLimitKmh(fallback: countryCompliance.truckSpeedLimitKmh)
        guard speedKmh > legalLimit + 3 else { return }
        let now = Date(); guard now.timeIntervalSince(lastSpeedComplianceAlertAt) > 45 else { return }
        lastSpeedComplianceAlertAt = now
        let currentSpeed = regionalSettings.formatSpeed(speedKmh)
        let limitText = regionalSettings.formatSpeed(legalLimit)
        speedComplianceMessage = "Truck speed \(currentSpeed) is above local heavy-vehicle guidance (\(limitText)). Reduce speed."
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
        let title = type == "entry" ? "Entered geofence" : "Exited geofence"
        speedComplianceMessage = "\(title): \(geofenceName)"
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
        let arrivalThreshold: Double = 350; let departureThreshold: Double = 600
        guard let nearest = truckStopService.nearbyStops.min(by: {
            location.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) <
            location.distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
        }) else { return }
        let distToNearest = location.distance(from: CLLocation(latitude: nearest.coordinate.latitude, longitude: nearest.coordinate.longitude))
        if distToNearest < arrivalThreshold && speed < 3.0 {
            if currentTruckStop?.name != nearest.name {
                currentTruckStop = nearest
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
                    guard currentTruckStop?.name == nearest.name else { return }
                    showingFoodSuggestion = false; lastFoodSuggestionLocation = nil; loadFoodSuggestion()
                }
                if parkingPromptShownFor != nearest.name {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [self] in
                        guard currentTruckStop?.name == nearest.name else { return }
                        parkingPromptShownFor = nearest.name
                        withAnimation(.spring(response: 0.4)) { showingParkingPrompt = true }
                    }
                }
            }
        } else if distToNearest > departureThreshold {
            if let prevStop = currentTruckStop {
                currentTruckStop = nil; showingParkingPrompt = false; lastTruckStopForReview = prevStop
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [self] in
                    guard !showingTruckStopReview, lastTruckStopForReview?.name == prevStop.name else { return }
                    withAnimation(.spring(response: 0.4)) { showingTruckStopReview = true }
                }
            }
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
                    let dist = location.distance(from: item.location)
                    let addr = item.address?.shortAddress ?? item.addressRepresentations?.cityWithContext ?? item.name ?? ""
                    return NearbyStopItem(name: item.name ?? "Loading Dock", address: addr,
                        coordinate: item.location.coordinate, distanceMeters: dist, phone: item.phoneNumber, category: .rest)
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
        guard let location = locationManager.currentLocation else { return }
        if let last = lastFoodSuggestionLocation, location.distance(from: last) < 500 { return }
        let profile = HealthProfile.loadSaved()
        let isMetric = lang != .english
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = profile.foodSearchQuery
            request.region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
            let results = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
            await MainActor.run {
                if let item = results.first {
                    let itemLoc = item.location; let dist = location.distance(from: itemLoc)
                    let addrText = item.address?.shortAddress ?? item.addressRepresentations?.cityWithContext ?? item.name ?? ""
                    foodSuggestion = FoodSuggestion(name: item.name ?? "Nearby Restaurant", address: addrText,
                        coordinate: itemLoc.coordinate, distanceMeters: dist, reason: profile.suggestionReason, useMetric: isMetric)
                    showingFoodSuggestion = true; lastFoodSuggestionLocation = location
                }
            }
        }
    }

    // MARK: - Utility Functions

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
            let now = Date(); guard now.timeIntervalSince(lastSpeedCheckDate) > 25 else { return }
            lastSpeedCheckDate = now
            if isDuskNow(at: now) && isVehicleStopped() && !hasShownMoodAtDuskToday {
                showingMoodCheck = true; hasShownMoodAtDuskToday = true
            }
            if Calendar.current.isDateInToday(now) == false { hasShownMoodAtDuskToday = false }
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
        let sorted = mapAlerts
            .map { CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude).distance(from: current) }
            .sorted()
            .prefix(3)
        return sorted.map { regionalSettings.formatDistance($0) }
    }

    private func formatArrivalClock() -> String {
        let arrival = Date().addingTimeInterval(activeDurationSeconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a z"
        formatter.timeZone = .current
        return formatter.string(from: arrival)
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
