#if canImport(MapboxMaps)
import SwiftUI
import MapKit
import CoreLocation
import MapboxMaps
import UIKit

// MARK: - Map style → Mapbox StyleURI

extension MapStyleOption {
    var mapboxStyleURI: StyleURI {
        switch self {
        case .standard:
            return .streets           // clean flat road map
        case .globe:
            return .standard          // Mapbox Standard 3D globe view (was duplicating .hybrid → toggle looked broken)
        case .hybrid:
            return .satelliteStreets  // satellite imagery + street labels
        case .satellite:
            return .satellite         // pure aerial imagery, no labels
        }
    }
}

// MARK: - Route-snapped location provider (native interpolated puck)

/// Custom location/heading provider that feeds Mapbox v11's native puck with map-matched
/// (route-snapped) positions. Mapbox then interpolates position + heading at frame rate
/// (60fps) between our emits, so the puck glides instead of jumping once per GPS fix.
/// We emit the route corridor bearing (not raw GPS course) so rotation stays stable at low speed.
final class RouteSnapLocationProvider: NSObject, LocationProvider, HeadingProvider {
    // Observers are retained by the SDK's signal adapters elsewhere; hold them weakly here
    // so we never keep the map/location stack alive.
    private let locationObservers = NSHashTable<AnyObject>.weakObjects()
    private let headingObservers = NSHashTable<AnyObject>.weakObjects()

    private var lastLocation: MapboxMaps.Location?
    private var heading: MapboxMaps.Heading?

    // MARK: LocationProvider

    func getLastObservedLocation() -> MapboxMaps.Location? {
        lastLocation
    }

    func addLocationObserver(for observer: LocationObserver) {
        locationObservers.add(observer)
    }

    func removeLocationObserver(for observer: LocationObserver) {
        locationObservers.remove(observer)
    }

    // MARK: HeadingProvider

    var latestHeading: MapboxMaps.Heading? {
        heading
    }

    func add(headingObserver: HeadingObserver) {
        headingObservers.add(headingObserver)
    }

    func remove(headingObserver: HeadingObserver) {
        headingObservers.remove(headingObserver)
    }

    // MARK: Feed

    /// Push a new target sample. Mapbox interpolates between consecutive emits, so we only
    /// emit once per GPS fix and the renderer produces the smooth in-between frames.
    func emit(coordinate: CLLocationCoordinate2D, bearing: CLLocationDirection, speed: CLLocationSpeed) {
        // `makeExtra` is internal to MapboxMaps; omitting `extra` makes the SDK default the
        // accuracy authorization to `.fullAccuracy` (see Location.accuracyAuthorization),
        // which is what we want for a real-GPS driven puck.
        let loc = MapboxMaps.Location(
            coordinate: coordinate,
            speed: max(0, speed),
            bearing: bearing
        )
        let newHeading = MapboxMaps.Heading(direction: bearing, accuracy: 5)
        lastLocation = loc
        heading = newHeading

        for observer in locationObservers.allObjects {
            (observer as? LocationObserver)?.onLocationUpdateReceived(for: [loc])
        }
        for observer in headingObservers.allObjects {
            (observer as? HeadingObserver)?.onHeadingUpdate(newHeading)
        }
    }
}

// MARK: - Horizon Mapbox surface (MapboxMaps v11)

/// Hosts `MapboxMaps.MapView` after SwiftUI assigns real bounds (avoids Metal {64×64} / width=0 glitches).
final class HorizonMapboxMapHostView: UIView {
    private var pendingInitOptions: MapInitOptions?
    private(set) var mapView: MapboxMaps.MapView?
    var onMapViewReady: ((MapboxMaps.MapView) -> Void)?

    init(mapInitOptions: MapInitOptions) {
        pendingInitOptions = mapInitOptions
        super.init(frame: .zero)
        backgroundColor = .white
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if mapView == nil, bounds.width > 100, bounds.height > 100, let opts = pendingInitOptions {
            let mv = MapboxMaps.MapView(frame: bounds, mapInitOptions: opts)
            mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(mv)
            mapView = mv
            pendingInitOptions = nil
            onMapViewReady?(mv)
        }
        applySafeContentScale()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySafeContentScale()
    }

    private func applySafeContentScale() {
        guard let mapView else { return }
        let raw = window?.screen.scale ?? UIScreen.main.scale
        let scale: CGFloat = (raw.isFinite && raw > 0) ? raw : 3.0
        if mapView.contentScaleFactor != scale {
            mapView.contentScaleFactor = scale
        }
    }

    /// SwiftUI may invoke `updateUIView` before the next `layoutSubviews`; keep Metal scale finite.
    func syncContentScaleWithScreen() {
        applySafeContentScale()
    }
}

/// Mapbox-backed Horizon map: route polylines, truck stops, alerts, zoom/recenter, north-up, light chrome.
struct HorizonMapboxSurface: UIViewRepresentable {
    var selectedMapStyle: MapStyleOption
    let locationManager: LocationManager
    let mapAlerts: [MapAlert]
    let route: MKRoute?
    var truckRoute: TruckRoute? = nil
    var routeQuantumLineAccent: Bool = false
    var isNavigating: Bool = false
    /// When true (reroute in flight) the old route line is faded so the real GPS position is never
    /// shown alongside an incompatible polyline.
    var dimRoute: Bool = false
    var onStyleChange: ((MapStyleOption) -> Void)? = nil
    var onControlsReady: (((zoomIn: () -> Void, zoomOut: () -> Void, recenter: () -> Void)) -> Void)? = nil
    var mapControls: MapControlActions? = nil
    /// Radar de chuva REAL (NEXRAD via IEM/NOAA) sobreposto no mapa — dado de governo, grátis,
    /// auto-atualizado (o endpoint serve sempre o mosaico mais recente). Toggle do motorista.
    var weatherRadarEnabled: Bool = false
    var truckStops: [TruckStopItem] = []
    /// Sinalização viária no corredor da rota (semáforos + PARE) — só durante a navegação na cidade.
    var routeSignage: [RouteSignageItem] = []
    var onTruckStopTapped: ((TruckStopItem) -> Void)? = nil

    private func activeRouteCoordinates() -> [CLLocationCoordinate2D]? {
        if let tr = truckRoute, tr.coordinates.count >= 2 { return tr.coordinates }
        guard let poly = route?.polyline, poly.pointCount >= 2 else { return nil }
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: poly.pointCount)
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: poly.pointCount))
        return coords
    }

    private func routeFingerprint() -> String {
        let dim = dimRoute ? 1 : 0
        if let tr = truckRoute {
            return "tr:\(tr.coordinates.count):\(Int(tr.distanceMeters)):q\(routeQuantumLineAccent ? 1 : 0):d\(dim)"
        }
        if let r = route {
            return "mk:\(r.polyline.pointCount):\(Int(r.distance)):d\(dim)"
        }
        return "none"
    }

    /// Idle map shows the navigation-arrow puck; during navigation only the lead chevron on the route is shown.
    /// Mapbox requires attribution when their renderer is used; keep logo off the driving HUD (bottom-left, under chrome).
    private static func tuckMapboxOrnaments(_ mapView: MapboxMaps.MapView, navigating: Bool) {
        var options = mapView.ornaments.options
        let bottomInset: CGFloat = navigating ? 88 : 72
        options.logo.position = .bottomLeading
        options.logo.margins = CGPoint(x: 8, y: bottomInset)
        options.attributionButton.position = .bottomLeading
        options.attributionButton.margins = CGPoint(x: 56, y: bottomInset)
        options.compass.visibility = .hidden
        options.scaleBar.visibility = .hidden
        mapView.ornaments.options = options
    }

    /// Conventional navigation-arrow puck (Google Maps/Waze style) — replaces Mapbox default blue dot.
    /// The puck is now the navigation cursor in BOTH states: during navigation it is fed
    /// route-snapped locations by `RouteSnapLocationProvider`, so Mapbox interpolates it at 60fps
    /// (no custom annotation needed). `.heading` bearing rotates the puck to the stable route
    /// corridor heading we emit (not the jittery raw GPS course).
    private func applyUserLocationPuck(on mapView: MapboxMaps.MapView, navigating _: Bool) {
        var puckConfig = Puck2DConfiguration()
        puckConfig.showsAccuracyRing = false
        puckConfig.topImage = HorizonMapboxPinImages.userNavigationArrowPuckImage()
        puckConfig.scale = .constant(1.0)
        mapView.location.options.puckType = .puck2D(puckConfig)
        mapView.location.options.puckBearing = .heading
        mapView.location.options.puckBearingEnabled = true
    }

    /// Modo conforto noturno: das 19h às 7h o globo/mapa fica escuro para não ofuscar na cabine.
    private static var isNightComfortHours: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 || hour < 7
    }

    private func bootstrapMap(_ mapView: MapboxMaps.MapView, coordinator: Coordinator) {
        mapView.overrideUserInterfaceStyle = (isNavigating || Self.isNightComfortHours) ? .dark : .light
        applyUserLocationPuck(on: mapView, navigating: isNavigating)
        Self.tuckMapboxOrnaments(mapView, navigating: isNavigating)
        var g = mapView.gestures.options
        g.pitchEnabled = true
        g.rotateEnabled = false
        mapView.gestures.options = g
        coordinator.mapView = mapView
        coordinator.installManagers(on: mapView)
        coordinator.onTruckStopTapped = onTruckStopTapped
        coordinator.onStyleChange = onStyleChange
        coordinator.lastRouteFingerprint = routeFingerprint()
        coordinator.lastStyle = selectedMapStyle
        if isNavigating {
            coordinator.requestInitialRouteCameraFit()
        }
        coordinator.refreshRoute(
            mapView: mapView,
            coords: activeRouteCoordinates(),
            fingerprint: routeFingerprint(),
            quantumAccent: routeQuantumLineAccent,
            fitCameraToRoute: !isNavigating,
            dimmed: dimRoute
        )
        coordinator.refreshPoints(mapView: mapView, truckStops: truckStops, alerts: mapAlerts)
        if let fullLoc = locationManager.currentLocation {
            coordinator.lastKnownCoordinate = fullLoc.coordinate
            mapView.mapboxMap.setCamera(to: CameraOptions(center: fullLoc.coordinate, zoom: 14, bearing: 0, pitch: 0))
        }
    }

    func makeUIView(context: Context) -> HorizonMapboxMapHostView {
        // NUNCA iniciar no globo (zoom 0 / [0,0]) — era a causa da "tela global" travada quando o
        // GPS demorava. Centra JÁ na posição conhecida (incl. a cached/A-GPS do iOS) em zoom de rua.
        // Sem nenhuma localização ainda, cai num centro continental razoável (não o planeta inteiro).
        let initialCamera: CameraOptions
        if let coord = locationManager.currentLocation?.coordinate {
            initialCamera = CameraOptions(center: coord, zoom: 14, bearing: 0, pitch: 0)
        } else {
            initialCamera = CameraOptions(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35), // centro dos EUA
                zoom: 3.5, bearing: 0, pitch: 0
            )
        }
        let initOptions = MapInitOptions(cameraOptions: initialCamera, styleURI: selectedMapStyle.mapboxStyleURI)
        let host = HorizonMapboxMapHostView(mapInitOptions: initOptions)
        let coordinator = context.coordinator
        host.onMapViewReady = { [self] mapView in
            bootstrapMap(mapView, coordinator: coordinator)
            onControlsReady?((
                zoomIn: {
                    guard let map = coordinator.mapView else { return }
                    if coordinator.isNavigatingMode {
                        // Navegando o FollowPuck é dono da câmera — ajusta o zoom do viewport.
                        coordinator.setNavigationZoom(coordinator.navigationZoom + 1, on: map)
                    } else {
                        let z = map.mapboxMap.cameraState.zoom
                        map.mapboxMap.setCamera(to: CameraOptions(zoom: min(z + 1, 22)))
                    }
                },
                zoomOut: {
                    guard let map = coordinator.mapView else { return }
                    if coordinator.isNavigatingMode {
                        coordinator.setNavigationZoom(coordinator.navigationZoom - 1, on: map)
                    } else {
                        let z = map.mapboxMap.cameraState.zoom
                        map.mapboxMap.setCamera(to: CameraOptions(zoom: max(z - 1, 2)))
                    }
                },
                recenter: {
                    guard let map = coordinator.mapView else { return }
                    coordinator.recenterCamera(on: map)
                }
            ))
        }
        if let mapView = host.mapView {
            bootstrapMap(mapView, coordinator: coordinator)
        }
        return host
    }

    func updateUIView(_ host: HorizonMapboxMapHostView, context: Context) {
        guard let mapView = host.mapView else {
            host.setNeedsLayout()
            return
        }
        host.syncContentScaleWithScreen()
        mapView.overrideUserInterfaceStyle = (isNavigating || Self.isNightComfortHours) ? .dark : .light
        applyUserLocationPuck(on: mapView, navigating: isNavigating)
        Self.tuckMapboxOrnaments(mapView, navigating: isNavigating)
        let coord = context.coordinator
        coord.isNavigatingMode = isNavigating
        coord.syncWeatherRadar(enabled: weatherRadarEnabled, on: mapView)
        coord.onTruckStopTapped = onTruckStopTapped
        coord.onStyleChange = onStyleChange

        let targetMargins: UIEdgeInsets = isNavigating
            ? UIEdgeInsets(top: 128, left: 12, bottom: 96, right: 56)
            : UIEdgeInsets(top: 110, left: 58, bottom: 120, right: 64)
        let uiMap = mapView as UIView
        if uiMap.layoutMargins != targetMargins {
            uiMap.layoutMargins = targetMargins
        }

        if coord.lastStyle != selectedMapStyle {
            // Troca de estilo AO VIVO, inclusive navegando — o completion do loadMapStyle
            // re-instala managers, rota e pins, então nada se perde no reload do estilo.
            coord.lastStyle = selectedMapStyle
            loadMapStyle(selectedMapStyle, on: mapView, coordinator: coord)
        }

        let fp = routeFingerprint()
        let routeGeometryChanged = coord.lastRouteFingerprint != fp
        if routeGeometryChanged {
            coord.lastRouteFingerprint = fp
            // O anchor da polyline precisa reiniciar na nova geometria para o puck "grudar" na nova linha.
            coord.resetLeadArrowAnchor()
            if isNavigating {
                // Navegando, a rota pode mudar (reroute, ou só o flag `dimRoute` ligando/desligando).
                // Apenas redesenha a linha — NÃO reseta o FollowPuck nem dá fit-to-bounds. Qualquer um
                // dos dois arranca a câmera para uma visão geral da rota inteira e parece "reiniciar".
                coord.refreshRoute(
                    mapView: mapView,
                    coords: activeRouteCoordinates(),
                    fingerprint: fp,
                    quantumAccent: routeQuantumLineAccent,
                    fitCameraToRoute: false,
                    dimmed: dimRoute
                )
            } else {
                // Parado (preview da rota): recentraliza na rota inteira, como antes.
                coord.resetCameraFollowThrottle()
                coord.refreshRoute(
                    mapView: mapView,
                    coords: activeRouteCoordinates(),
                    fingerprint: fp,
                    quantumAccent: routeQuantumLineAccent,
                    fitCameraToRoute: true,
                    dimmed: dimRoute
                )
            }
        }

        // Fit único só quando a navegação COMEÇA (pedido no bootstrap) — nunca em reroute mid-trip.
        if isNavigating, coord.consumeInitialRouteCameraFit(),
           let coords = activeRouteCoordinates(), coords.count >= 2 {
            coord.fitCameraToRouteBounds(mapView: mapView, coords: coords)
        }

        let navigationJustStarted = isNavigating && !coord.wasNavigatingMode
        coord.wasNavigatingMode = isNavigating
        if navigationJustStarted, let coords = activeRouteCoordinates(), coords.count >= 2 {
            coord.refreshRoute(
                mapView: mapView,
                coords: coords,
                fingerprint: fp,
                quantumAccent: routeQuantumLineAccent,
                fitCameraToRoute: false
            )
        }


        coord.refreshPoints(mapView: mapView, truckStops: truckStops, alerts: mapAlerts,
                            signage: isNavigating ? routeSignage : [])
        // Feed the native interpolated puck. During navigation it gets route-snapped samples
        // (stable corridor bearing); idle it gets raw GPS. The custom lead-arrow annotation is
        // gone — the puck IS the cursor now, so make sure it stays cleared.
        coord.clearRouteNavigationArrow()
        if isNavigating, let coords = activeRouteCoordinates(), coords.count >= 2,
           let user = locationManager.currentLocation {
            coord.emitRouteSnappedLocation(coords: coords, user: user)
        } else if let user = locationManager.currentLocation {
            coord.emitRawLocation(user: user)
        }

        if let fullLoc = locationManager.currentLocation {
            coord.lastKnownCoordinate = fullLoc.coordinate
        }

        coord.updateNavigationViewport(mapView: mapView, isNavigating: isNavigating)

        if !isNavigating, let fullLoc = locationManager.currentLocation,
           coord.shouldUpdateIdleCamera(newLocation: fullLoc) {
            let z = mapView.mapboxMap.cameraState.zoom
            mapView.mapboxMap.setCamera(to: CameraOptions(center: fullLoc.coordinate, zoom: z, bearing: 0, pitch: 0))
        }
    }

    private func loadMapStyle(_ style: MapStyleOption, on mapView: MapboxMaps.MapView, coordinator: Coordinator) {
        mapView.mapboxMap.loadStyle(style.mapboxStyleURI) { _ in
            DispatchQueue.main.async {
                self.applyUserLocationPuck(on: mapView, navigating: coordinator.isNavigatingMode)
                coordinator.installManagers(on: mapView)
                coordinator.resetLeadArrowAnchor()
                coordinator.refreshRoute(
                    mapView: mapView,
                    coords: self.activeRouteCoordinates(),
                    fingerprint: self.routeFingerprint(),
                    quantumAccent: self.routeQuantumLineAccent,
                    fitCameraToRoute: !coordinator.isNavigatingMode
                )
                coordinator.refreshPoints(mapView: mapView, truckStops: self.truckStops, alerts: self.mapAlerts)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var mapView: MapboxMaps.MapView?
        /// Native interpolated puck data source — fed route-snapped (or raw-GPS, idle) samples.
        let snapProvider = RouteSnapLocationProvider()
        private var snapProviderInstalled = false
        var onTruckStopTapped: ((TruckStopItem) -> Void)?
        var onStyleChange: ((MapStyleOption) -> Void)?
        var lastRouteFingerprint: String = ""
        var lastStyle: MapStyleOption = .standard
        var lastKnownCoordinate: CLLocationCoordinate2D?
        var isNavigatingMode = false
        var wasNavigatingMode = false
        private var needsInitialRouteCameraFit = false
        private var followPuckAllowedAfter: Date = .distantPast
        private var weatherRadarEnabled = false
        private var weatherRadarTimer: Timer?

        // MARK: - Weather radar (NEXRAD real, NOAA via Iowa Mesonet — grátis, sem chave, auto-atualiza)
        private let weatherRadarSourceId = "weather-radar-src"
        private let weatherRadarLayerId = "weather-radar-layer"

        func syncWeatherRadar(enabled: Bool, on mapView: MapboxMaps.MapView) {
            guard enabled != weatherRadarEnabled else { return }
            weatherRadarEnabled = enabled
            if enabled {
                addWeatherRadar(on: mapView)
                // Auto-atualização: re-carrega o mosaico mais recente a cada 5 min enquanto ligado.
                weatherRadarTimer?.invalidate()
                weatherRadarTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self, weak mapView] _ in
                    guard let self, let mapView, self.weatherRadarEnabled else { return }
                    self.refreshWeatherRadar(on: mapView)
                }
            } else {
                weatherRadarTimer?.invalidate(); weatherRadarTimer = nil
                removeWeatherRadar(on: mapView)
            }
        }

        private func addWeatherRadar(on mapView: MapboxMaps.MapView) {
            guard let map = mapView.mapboxMap else { return }
            guard !map.layerExists(withId: weatherRadarLayerId) else { return }
            do {
                if !map.sourceExists(withId: weatherRadarSourceId) {
                    var source = RasterSource(id: weatherRadarSourceId)
                    // NEXRAD (EUA) — radar NOAA via Iowa Environmental Mesonet. XYZ, grátis, sem chave,
                    // serve SEMPRE o mosaico mais recente (dado real, nunca fabricado).
                    source.tiles = ["https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png"]
                    source.tileSize = 256
                    source.attribution = "NOAA / Iowa Environmental Mesonet"
                    try map.addSource(source)
                }
                var layer = RasterLayer(id: weatherRadarLayerId, source: weatherRadarSourceId)
                layer.rasterOpacity = .constant(0.55)
                try map.addLayer(layer)
            } catch {
                #if DEBUG
                print("[WeatherRadar] addLayer falhou: \(error.localizedDescription)")
                #endif
            }
        }

        private func removeWeatherRadar(on mapView: MapboxMaps.MapView) {
            guard let map = mapView.mapboxMap else { return }
            if map.layerExists(withId: weatherRadarLayerId) { try? map.removeLayer(withId: weatherRadarLayerId) }
            if map.sourceExists(withId: weatherRadarSourceId) { try? map.removeSource(withId: weatherRadarSourceId) }
        }

        private func refreshWeatherRadar(on mapView: MapboxMaps.MapView) {
            // Remove + re-adiciona força o Mapbox a buscar os tiles atuais (mosaico mais recente).
            removeWeatherRadar(on: mapView)
            addWeatherRadar(on: mapView)
        }

        func requestInitialRouteCameraFit() {
            needsInitialRouteCameraFit = true
            followPuckAllowedAfter = Date().addingTimeInterval(2.0)
        }

        func consumeInitialRouteCameraFit() -> Bool {
            guard needsInitialRouteCameraFit else { return false }
            needsInitialRouteCameraFit = false
            return true
        }

        /// Mapbox FollowPuck — smooth 60fps camera + puck (no manual setCamera jumps).
        private var followPuckState: FollowPuckViewportState?
        private var followPuckActive = false
        /// Zoom da câmera navegando — ajustável pelos botões +/− (o FollowPuck é dono da câmera,
        /// então setCamera manual era sobrescrito; o ajuste tem que ser no próprio viewport).
        var navigationZoom: CGFloat = 16.5

        func setNavigationZoom(_ zoom: CGFloat, on mapView: MapboxMaps.MapView) {
            navigationZoom = min(max(zoom, 11), 20)
            guard followPuckActive else { return }
            var opts = FollowPuckViewportStateOptions()
            opts.zoom = navigationZoom
            opts.pitch = 50                // visão inclinada pra frente (GPS de verdade)
            opts.bearing = .heading        // mapa GIRA pro sentido da viagem (course-up)
            let state = mapView.viewport.makeFollowPuckViewportState(options: opts)
            followPuckState = state
            mapView.viewport.transition(to: state)
        }

        private var lastIdleCameraUpdateAt: Date = .distantPast
        private var lastIdleCameraCenter: CLLocation?

        func resetCameraFollowThrottle() {
            lastIdleCameraCenter = nil
            lastIdleCameraUpdateAt = .distantPast
            followPuckState = nil
            followPuckActive = false
        }

        func recenterCamera(on mapView: MapboxMaps.MapView) {
            resetCameraFollowThrottle()
            if isNavigatingMode, let c = smoothedRouteCoord {
                mapView.mapboxMap.setCamera(to: CameraOptions(
                    center: c,
                    zoom: navigationZoom,
                    bearing: smoothedRouteBearing,   // course-up: aponta pro sentido da viagem
                    pitch: 50
                ))
            } else if let c = lastKnownCoordinate {
                let z: CGFloat = mapView.mapboxMap.cameraState.zoom
                mapView.mapboxMap.setCamera(to: CameraOptions(center: c, zoom: z, bearing: 0, pitch: 0))
            }
        }

        func updateNavigationViewport(mapView: MapboxMaps.MapView, isNavigating: Bool) {
            if isNavigating {
                guard !followPuckActive else { return }
                var opts = FollowPuckViewportStateOptions()
                opts.zoom = navigationZoom
                // Course-up: o mapa GIRA pro sentido da viagem e inclina pra frente (GPS de verdade).
                // O puck já emite um bearing de corredor ESTÁVEL, então gira suave (sem jitter).
                opts.pitch = 50
                opts.bearing = .heading
                let state = mapView.viewport.makeFollowPuckViewportState(options: opts)
                followPuckState = state
                followPuckActive = true
                mapView.viewport.transition(to: state)
            } else if followPuckActive {
                followPuckActive = false
                followPuckState = nil
                mapView.viewport.idle()
            }
        }

        func shouldUpdateIdleCamera(newLocation: CLLocation) -> Bool {
            guard let prev = lastIdleCameraCenter else {
                lastIdleCameraCenter = newLocation
                lastIdleCameraUpdateAt = Date()
                return true
            }
            let dist = newLocation.distance(from: prev)
            let dt = Date().timeIntervalSince(lastIdleCameraUpdateAt)
            if dist >= 48 || dt >= 6 {
                lastIdleCameraCenter = newLocation
                lastIdleCameraUpdateAt = Date()
                return true
            }
            return false
        }

        private var routeLineManager: PolylineAnnotationManager?
        private var routeArrowManager: PointAnnotationManager?
        private var truckStopManager: PointAnnotationManager?
        private var alertManager: PointAnnotationManager?
        private var signageManager: PointAnnotationManager?
        private var lastSignageFingerprint: Int?
        /// Cache do ícone por tipo (semáforo / PARE) — 2 variações, não uma render por ponto.
        private var signageImageCache: [String: PointAnnotation.Image] = [:]
        /// Evita reconstruir os pins quando a lista não mudou. `refreshPoints` roda a cada
        /// `updateUIView` (timer HOS 1Hz + GPS); sem isto, regenerava dezenas de imagens
        /// Core Graphics por frame e travava a main thread (UI/abas sem resposta).
        private var lastStopsFingerprint: Int?
        private var lastAlertsFingerprint: Int?
        /// Cache de imagem de pin por aparência (network / tipo de alerta) — ~5 variações,
        /// não uma renderização por POI.
        private var stopImageCache: [String: PointAnnotation.Image] = [:]
        private var alertImageCache: [String: PointAnnotation.Image] = [:]

        /// Incremental polyline anchor for route chevron (reset when route geometry changes).
        private var lastLeadArrowPolyIndex: Int = 0
        private var lastRouteArrowUpdateAt: Date = .distantPast
        private var lastRouteArrowUserLoc: CLLocation?

        private var smoothedRouteCoord: CLLocationCoordinate2D?
        private var smoothedRouteBearing: Double = 0
        /// Last bearing emitted to the puck — reused when GPS course is invalid (stationary).
        private var lastEmittedBearing: CLLocationDirection = 0

        var hasRouteNavigationAnchor: Bool { smoothedRouteCoord != nil }

        func resetLeadArrowAnchor() {
            lastLeadArrowPolyIndex = 0
            lastRouteArrowUserLoc = nil
            lastRouteArrowUpdateAt = .distantPast
            smoothedRouteCoord = nil
            smoothedRouteBearing = 0
        }

        func clearRouteNavigationArrow() {
            routeArrowManager?.annotations = []
            lastRouteArrowUserLoc = nil
            smoothedRouteCoord = nil
        }

        func clearLeadNavigationArrow() { clearRouteNavigationArrow() }

        func installManagers(on mapView: MapboxMaps.MapView) {
            // Drive the native puck from our route-snapped provider (once — the override persists
            // across style reloads). Mapbox interpolates between the samples we emit at 60fps.
            if !snapProviderInstalled {
                mapView.location.override(provider: snapProvider)
                snapProviderInstalled = true
            }
            routeLineManager = mapView.annotations.makePolylineAnnotationManager(id: "horizon-route")
            routeArrowManager = mapView.annotations.makePointAnnotationManager(id: "horizon-route-lead-arrow")
            truckStopManager = mapView.annotations.makePointAnnotationManager(id: "horizon-stops")
            alertManager = mapView.annotations.makePointAnnotationManager(id: "horizon-alerts")
            signageManager = mapView.annotations.makePointAnnotationManager(id: "horizon-signage")
            // Bug "seta por baixo da linha": os managers acima entram no TOPO da pilha e cobrem o
            // puck. Re-asserir o puckType só atualiza no lugar (não reordena) — por isso ele
            // continuava embaixo. Forçamos a RECRIAÇÃO (nil → puck2D): a camada do indicador é
            // removida e re-adicionada no topo, acima da linha da rota.
            mapView.location.options.puckType = nil
            var puckConfig = Puck2DConfiguration()
            puckConfig.showsAccuracyRing = false
            puckConfig.topImage = HorizonMapboxPinImages.userNavigationArrowPuckImage()
            puckConfig.scale = .constant(1.0)
            mapView.location.options.puckType = .puck2D(puckConfig)
            mapView.location.options.puckBearing = .heading
            mapView.location.options.puckBearingEnabled = true
            // Managers recriados começam vazios → força refreshPoints a re-adicionar os pins.
            lastStopsFingerprint = nil
            lastAlertsFingerprint = nil
            lastSignageFingerprint = nil
        }

        func refreshRoute(
            mapView: MapboxMaps.MapView,
            coords: [CLLocationCoordinate2D]?,
            fingerprint _: String,
            quantumAccent: Bool,
            fitCameraToRoute: Bool,
            dimmed: Bool = false
        ) {
            if routeLineManager == nil {
                installManagers(on: mapView)
            }
            guard let mgr = routeLineManager else { return }
            guard let coords, coords.count >= 2 else {
                mgr.annotations = []
                routeArrowManager?.annotations = []
                return
            }
            // During a reroute the old line is faded out so it never reads as the active route.
            let casingOpacity = dimmed ? 0.18 : 1.0
            let mainOpacity = dimmed ? 0.22 : 1.0

            var casing = PolylineAnnotation(lineCoordinates: coords)
            casing.lineColor = StyleColor(HorizonRouteColors.routeCasingUI)
            casing.lineWidth = 18
            casing.lineJoin = LineJoin.round
            casing.lineOpacity = casingOpacity
            casing.lineSortKey = 0

            var main = PolylineAnnotation(lineCoordinates: coords)
            let mainUIColor: UIColor = quantumAccent
                ? HorizonRouteColors.quantumPurpleUI
                : HorizonRouteColors.routeOrangeUI
            main.lineColor = StyleColor(mainUIColor)
            main.lineWidth = quantumAccent ? 15 : 14
            main.lineJoin = LineJoin.round
            main.lineOpacity = mainOpacity
            main.lineSortKey = 1

            mgr.annotations = [casing, main]
            if fitCameraToRoute {
                fitCameraToRouteBounds(mapView: mapView, coords: coords)
            }
        }

        func fitCameraToRouteBounds(mapView: MapboxMaps.MapView, coords: [CLLocationCoordinate2D]) {
            guard coords.count >= 2 else { return }
            var minLat = coords[0].latitude, maxLat = minLat
            var minLon = coords[0].longitude, maxLon = minLon
            for c in coords {
                minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
                minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
            }
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            let spanLat = max(0.02, (maxLat - minLat) * 1.35)
            let spanLon = max(0.02, (maxLon - minLon) * 1.35)
            let zoom = min(14.5, max(8.5, log2(360.0 / max(spanLon, spanLat * cos(center.latitude * .pi / 180)))))
            mapView.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: zoom, bearing: 0, pitch: 0))
        }

        /// Snaps GPS onto the route polyline and feeds the native puck provider with the
        /// route-snapped coordinate + stable corridor bearing. Mapbox interpolates between
        /// emits at 60fps, so the puck (now the cursor) glides smoothly along the road.
        /// `smoothedRouteCoord`/`smoothedRouteBearing` are still updated so `recenterCamera`
        /// and `hasRouteNavigationAnchor` keep working.
        func emitRouteSnappedLocation(
            coords: [CLLocationCoordinate2D],
            user: CLLocation
        ) {
            guard coords.count >= 2 else { return }

            // POSIÇÃO = GPS REAL (±2m) — precisão acima de tudo. A polyline do Valhalla é decimada
            // (pontos a 10-50m); projetar o GPS nela colocava o puck visivelmente torto (a causa de
            // "localização imprecisa"). Agora a bolinha fica EXATAMENTE onde o motorista está, e a
            // rota é usada só pra um RUMO suave (corredor), evitando o tremor do course do GPS.
            var bearing: CLLocationDirection = user.course >= 0 ? user.course : lastEmittedBearing
            if let snap = PolylineLeadArrow.snappedPosition(
                coords: coords,
                user: user,
                anchorIndex: &lastLeadArrowPolyIndex
            ) {
                bearing = snap.bearingDegrees
            }
            lastEmittedBearing = bearing
            smoothedRouteCoord = user.coordinate
            smoothedRouteBearing = bearing
            snapProvider.emit(
                coordinate: user.coordinate,
                bearing: bearing,
                speed: max(0, user.speed)
            )
        }

        /// Feeds the native puck with raw GPS while idle (no route). Mapbox still interpolates
        /// between fixes, so the idle puck stays smooth. Uses the last known bearing when the
        /// GPS course is invalid (course < 0 when stationary).
        func emitRawLocation(user: CLLocation) {
            let bearing: CLLocationDirection = user.course >= 0 ? user.course : lastEmittedBearing
            lastEmittedBearing = bearing
            snapProvider.emit(
                coordinate: user.coordinate,
                bearing: bearing,
                speed: max(0, user.speed)
            )
        }

        private func lerpCoordinate(
            _ a: CLLocationCoordinate2D,
            _ b: CLLocationCoordinate2D,
            alpha: Double
        ) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: a.latitude + (b.latitude - a.latitude) * alpha,
                longitude: a.longitude + (b.longitude - a.longitude) * alpha
            )
        }

        private func lerpAngle(_ a: Double, _ b: Double, alpha: Double) -> Double {
            var delta = (b - a).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            var out = a + delta * alpha
            if out < 0 { out += 360 }
            if out >= 360 { out -= 360 }
            return out
        }

        func refreshPoints(mapView: MapboxMaps.MapView, truckStops: [TruckStopItem], alerts: [MapAlert],
                           signage: [RouteSignageItem] = []) {
            refreshSignage(mapView: mapView, signage: signage)
            guard let stopsMgr = truckStopManager, let alertMgr = alertManager else { return }

            var stopsHasher = Hasher()
            for stop in truckStops { stopsHasher.combine(stop.id) }
            let stopsFp = stopsHasher.finalize()

            var alertsHasher = Hasher()
            for alert in alerts { alertsHasher.combine(alert.id) }
            let alertsFp = alertsHasher.finalize()

            // Reconstrói os pins SOMENTE quando a lista muda. Antes isto rodava a cada frame
            // (timer HOS / GPS), regenerando imagens Core Graphics e travando a main thread.
            if stopsFp != lastStopsFingerprint {
                lastStopsFingerprint = stopsFp
                var stopAnnotations: [PointAnnotation] = []
                stopAnnotations.reserveCapacity(truckStops.count)
                for stop in truckStops {
                    var ann = PointAnnotation(id: stop.id.uuidString, coordinate: stop.coordinate)
                    ann.iconAnchor = .center
                    let key = String(describing: stop.network)
                    if let img = stopImageCache[key] ?? HorizonMapboxPinImages.truckStopImage(for: stop) {
                        stopImageCache[key] = img
                        ann.image = img
                    }
                    let captured = stop
                    ann.tapHandler = { [weak self] _ in
                        self?.onTruckStopTapped?(captured)
                        return true
                    }
                    stopAnnotations.append(ann)
                }
                stopsMgr.annotations = stopAnnotations
            }

            if alertsFp != lastAlertsFingerprint {
                lastAlertsFingerprint = alertsFp
                var alertAnns: [PointAnnotation] = []
                alertAnns.reserveCapacity(alerts.count)
                for alert in alerts {
                    var ann = PointAnnotation(id: alert.id.uuidString, coordinate: alert.coordinate)
                    ann.iconAnchor = .center
                    let key = String(describing: alert.type)
                    if let img = alertImageCache[key] ?? HorizonMapboxPinImages.alertImage(for: alert) {
                        alertImageCache[key] = img
                        ann.image = img
                    }
                    alertAnns.append(ann)
                }
                alertMgr.annotations = alertAnns
            }
        }

        /// Renderiza a sinalização do corredor (semáforos + PARE). Some ao afastar o zoom (rodovia)
        /// para não poluir; navegando na cidade o zoom fica ~16.5, então aparece naturalmente.
        func refreshSignage(mapView: MapboxMaps.MapView, signage: [RouteSignageItem]) {
            guard let mgr = signageManager else { return }
            let zoom = mapView.mapboxMap.cameraState.zoom
            let visible = zoom >= 13.5 ? signage : []

            var hasher = Hasher()
            for s in visible { hasher.combine(s.id) }
            let fp = hasher.finalize()
            guard fp != lastSignageFingerprint else { return }
            lastSignageFingerprint = fp

            var anns: [PointAnnotation] = []
            anns.reserveCapacity(visible.count)
            for s in visible {
                var ann = PointAnnotation(id: s.id, coordinate: s.coordinate)
                ann.iconAnchor = .center
                let key = s.kind.rawValue
                if let img = signageImageCache[key] ?? HorizonMapboxPinImages.signageImage(for: s.kind) {
                    signageImageCache[key] = img
                    ann.image = img
                }
                anns.append(ann)
            }
            mgr.annotations = anns
        }
    }
}

// MARK: - Raster images for point annotations

private enum HorizonMapboxPinImages {
    /// Ícone de sinalização viária no corredor da rota: semáforo (3 luzes) ou PARE (octógono vermelho).
    static func signageImage(for kind: RouteSignageItem.Kind) -> PointAnnotation.Image? {
        let size: CGFloat = 26
        let uiImage = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let c = ctx.cgContext
            switch kind {
            case .trafficSignal:
                let body = CGRect(x: size * 0.32, y: size * 0.12, width: size * 0.36, height: size * 0.76)
                let path = UIBezierPath(roundedRect: body, cornerRadius: size * 0.10)
                c.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor); c.addPath(path.cgPath); c.fillPath()
                c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(1.2); c.addPath(path.cgPath); c.strokePath()
                let r = size * 0.085
                let cx = body.midX
                let colors: [UIColor] = [.systemRed, .systemYellow, .systemGreen]
                for (i, col) in colors.enumerated() {
                    let cy = body.minY + body.height * 0.24 + CGFloat(i) * body.height * 0.26
                    c.setFillColor(col.cgColor)
                    c.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                }
            case .stop:
                let cxp = size / 2, cyp = size / 2, rad = size * 0.46
                let oct = UIBezierPath()
                for i in 0..<8 {
                    let a = CGFloat.pi / 8 + CGFloat(i) * (.pi / 4)
                    let pt = CGPoint(x: cxp + rad * cos(a), y: cyp + rad * sin(a))
                    if i == 0 { oct.move(to: pt) } else { oct.addLine(to: pt) }
                }
                oct.close()
                c.setFillColor(UIColor.systemRed.cgColor); c.addPath(oct.cgPath); c.fillPath()
                c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(1.4); c.addPath(oct.cgPath); c.strokePath()
                let txt = "STOP" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: size * 0.26, weight: .heavy),
                    .foregroundColor: UIColor.white
                ]
                let ts = txt.size(withAttributes: attrs)
                txt.draw(at: CGPoint(x: cxp - ts.width / 2, y: cyp - ts.height / 2), withAttributes: attrs)
            }
        }
        return PointAnnotation.Image(image: uiImage, name: "signage-\(kind.rawValue)", sdf: false)
    }

    /// Up-facing chevron (north at 0° rotation) tinted to match the active route line.
    static func routeDirectionArrowImage(quantumAccent: Bool) -> PointAnnotation.Image {
        let fill: UIColor = quantumAccent
            ? HorizonRouteColors.quantumPurpleUI
            : HorizonRouteColors.routeOrangeUI
        let stroke = UIColor.white
        let name = quantumAccent ? "horizon-route-arrow-q" : "horizon-route-arrow"
        let size = CGSize(width: 40, height: 44)
        let uiImage = UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let w = size.width
            let h = size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            c.translateBy(x: center.x, y: center.y)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: -16))
            path.addLine(to: CGPoint(x: 13, y: 12))
            path.addLine(to: CGPoint(x: 0, y: 5))
            path.addLine(to: CGPoint(x: -13, y: 12))
            path.close()
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 3.5, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            c.setFillColor(fill.cgColor)
            c.addPath(path.cgPath)
            c.fillPath()
            c.setShadow(offset: .zero, blur: 0, color: nil)
            c.setStrokeColor(stroke.withAlphaComponent(0.85).cgColor)
            c.setLineWidth(2)
            c.addPath(path.cgPath)
            c.strokePath()
        }
        return PointAnnotation.Image(image: uiImage, name: name, sdf: false)
    }

    static func truckStopImage(for stop: TruckStopItem) -> PointAnnotation.Image? {
        let network = stop.network
        let brand = UIColor(network.brandColor)
        let size: CGFloat = 38
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let uiImage = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            ctx.cgContext.setFillColor(brand.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            let iconName: String
            switch network {
            case .pilotFlyingJ: iconName = "airplane.departure"
            case .loves: iconName = "heart.fill"
            case .taPetro: iconName = "car.side.fill"
            case .kwikTrip: iconName = "bolt.fill"
            default: iconName = "fuelpump.fill"
            }
            let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            if let img = UIImage(systemName: iconName, withConfiguration: cfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: (size - img.size.width) / 2, y: (size - img.size.height) / 2)
                img.draw(at: origin)
            }
        }
        let name = "ts-\(stop.id.uuidString)"
        return PointAnnotation.Image(image: uiImage, name: name, sdf: false)
    }

    static func alertImage(for alert: MapAlert) -> PointAnnotation.Image? {
        let fill = uiColor(for: alert.type)
        let size: CGFloat = 32
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerRadius: 16)
            fill.setFill()
            path.fill()
            if let sym = UIImage(systemName: alert.type.icon)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                sym.draw(in: CGRect(x: 9, y: 9, width: 14, height: 14))
            }
        }
        let name = "al-\(alert.id.uuidString)"
        return PointAnnotation.Image(image: img, name: name, sdf: false)
    }

    private static func uiColor(for type: MapAlert.AlertType) -> UIColor {
        switch type {
        case .police: return UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1)
        case .accident: return UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)
        case .scale: return UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1)
        case .weather: return UIColor(red: 0.39, green: 0.4, blue: 0.95, alpha: 1)
        case .hazmat: return UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)
        case .roadwork: return UIColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)
        }
    }

    /// Conventional navigation arrow (drawn pointing up = 0° rotation = north).
    /// Mapbox's Puck2D rotates it to the GPS course with built-in interpolation,
    /// so it always points along the direction of travel — never sideways.
    static func userNavigationArrowPuckImage() -> UIImage {
        let size = CGSize(width: 44, height: 44)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            // Outer white ring + shadow so the puck pops on any map style.
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            c.setFillColor(UIColor.white.cgColor)
            c.fillEllipse(in: CGRect(x: 3, y: 3, width: 38, height: 38))
            c.setShadow(offset: .zero, blur: 0, color: nil)
            // Inner BLUE disc — deliberately a different hue from the ORANGE route line so the cursor
            // reads as a distinct arrow and never blends into "a line of the same color" behind it.
            let puckBlue = UIColor(red: 0.13, green: 0.45, blue: 0.96, alpha: 1)
            c.setFillColor(puckBlue.cgColor)
            c.fillEllipse(in: CGRect(x: 6, y: 6, width: 32, height: 32))
            // White chevron pointing forward (up at 0° rotation; Mapbox rotates it to the heading).
            c.translateBy(x: size.width / 2, y: size.height / 2)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: -11))
            path.addLine(to: CGPoint(x: 8.5, y: 9))
            path.addLine(to: CGPoint(x: 0, y: 3.5))
            path.addLine(to: CGPoint(x: -8.5, y: 9))
            path.close()
            c.setFillColor(UIColor.white.cgColor)
            c.addPath(path.cgPath)
            c.fillPath()
        }
    }

    /// Fully transparent — hides puck while navigating (lead arrow on route is enough).
    static func invisiblePuckImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    }
}

#endif
