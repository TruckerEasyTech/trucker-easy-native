#if canImport(MapboxMaps)
import SwiftUI
import MapKit
import CoreLocation
import MapboxMaps
import UIKit
import Combine

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

    // Publishers que alimentam o `LocationDataModel` (API NÃO-deprecated da v11 — substitui o
    // `override(provider:)`). O `emit()` envia aqui; o puck nativo consome via dataModel.
    let locationPublisher = PassthroughSubject<[MapboxMaps.Location], Never>()
    let headingPublisher = PassthroughSubject<MapboxMaps.Heading, Never>()

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

        // Caminho ATUAL (não-deprecated): alimenta o LocationDataModel via publishers.
        locationPublisher.send([loc])
        headingPublisher.send(newHeading)

        // Observers mantidos por conformidade do protocolo (o dataModel não os usa).
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
        // Anti-TELA-PRETA: ao voltar do 2º plano / desbloquear a tela, o Mapbox/Metal pode perder o
        // drawable e ficar preto. Forçamos repaint + re-escala no didBecomeActive pra recuperar.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func appDidBecomeActive() {
        applySafeContentScale()
        kickRepaint()
    }

    /// ANTI-TELA-PRETA (device): o CAMetalLayer do Mapbox às vezes recebe drawableSize 0×0 durante a
    /// transição splash→mapa e NÃO se recupera sozinho no device (log: "CAMetalLayer ignoring invalid
    /// setDrawableSize width=0 height=0") → mapa preto mesmo com o app rodando. Forçar frame válido +
    /// triggerRepaint algumas vezes, DEPOIS do layout assentar, faz o Metal reconfigurar o drawable.
    private func kickRepaint() {
        guard let mapView else { return }
        if bounds.width > 1, bounds.height > 1 { mapView.frame = bounds }
        applySafeContentScale()
        mapView.mapboxMap.triggerRepaint()
        // Re-tenta nos próximos frames (a transição de opacidade do SwiftUI ainda pode estar rodando).
        for delay in [0.1, 0.35, 0.8, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let mv = self.mapView else { return }
                if self.bounds.width > 1, self.bounds.height > 1, mv.frame.size != self.bounds.size {
                    mv.frame = self.bounds
                }
                self.applySafeContentScale()
                mv.mapboxMap.triggerRepaint()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Mantém o mapa preenchendo o host SEMPRE que o host ganha tamanho válido (evita drawable 0×0).
        if let mv = mapView, bounds.width > 1, bounds.height > 1, mv.frame.size != bounds.size {
            mv.frame = bounds
            mv.mapboxMap.triggerRepaint()
        }
        if mapView == nil, bounds.width > 100, bounds.height > 100, let opts = pendingInitOptions {
            // ANTI-TELA-PRETA no launch: a init do MapboxMaps.MapView (Metal + style + tile store) é
            // pesada e SÍNCRONA. Criá-la aqui, no mesmo ciclo, congelava o frame da transição
            // splash→mapa = tela preta travada. Deferimos pro próximo runloop: o fundo branco + chrome
            // já desenham, então o mapa entra. UI nunca fica num preto congelado.
            pendingInitOptions = nil
            LaunchTrace.mark("mapview.layoutSubviews scheduling create")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.mapView == nil, self.bounds.width > 100, self.bounds.height > 100 else { return }
                LaunchTrace.mark("mapview.creating")
                let mv = MapboxMaps.MapView(frame: self.bounds, mapInitOptions: opts)
                LaunchTrace.mark("mapview.created")
                mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                self.addSubview(mv)
                self.mapView = mv
                self.onMapViewReady?(mv)
                self.applySafeContentScale()
                self.kickRepaint()   // garante drawable válido após criar (anti-preto no device)
                LaunchTrace.mark("mapview.ready")
            }
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
    /// Altura da chrome de baixo (vinda da View) p/ os ornamentos do Mapbox ficarem ACIMA dela.
    var mapboxBottomInset: CGFloat = 96
    var truckStops: [TruckStopItem] = []
    /// Sinalização viária no corredor da rota (semáforos + PARE) — só durante a navegação na cidade.
    var routeSignage: [RouteSignageItem] = []
    var cameras: [TrafficCamera] = []
    var onTruckStopTapped: ((TruckStopItem) -> Void)? = nil
    var onCameraTapped: ((TrafficCamera) -> Void)? = nil
    /// Marcador de manobra NA rota: seta no ponto EXATO da curva/saída (do NavigationEngine).
    var maneuverMarkerCoordinate: CLLocationCoordinate2D? = nil
    var maneuverMarkerDirection: String? = nil
    /// Trecho da polilinha ±80m na curva — desenhado como SETA BRANCA sobre a rota (estilo TP).
    var maneuverSegment: [CLLocationCoordinate2D] = []

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
    /// Posiciona o logo + atribuição do Mapbox (obrigatórios, visíveis) ACIMA da chrome de baixo —
    /// sem isso a "faixa de baixo" do mapa sobrepunha o sheet/painel. O inset vem da View (altura
    /// real da chrome idle / barra de navegação).
    private static func tuckMapboxOrnaments(_ mapView: MapboxMaps.MapView, bottomInset: CGFloat) {
        var options = mapView.ornaments.options
        let inset = max(bottomInset, 16) + 14   // folga extra acima do sheet (sem encostar)
        options.logo.position = .bottomLeading
        options.logo.margins = CGPoint(x: 8, y: inset)
        options.attributionButton.position = .bottomLeading
        options.attributionButton.margins = CGPoint(x: 56, y: inset)
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
        mapView.location.options.puckBearing = .course   // lê location.bearing (corredor), não a bússola — consistente c/ a câmera no iPad
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
        Self.tuckMapboxOrnaments(mapView, bottomInset: mapboxBottomInset)
        var g = mapView.gestures.options
        g.pitchEnabled = true
        g.rotateEnabled = false
        mapView.gestures.options = g
        coordinator.mapView = mapView
        coordinator.installManagers(on: mapView)
        coordinator.onTruckStopTapped = onTruckStopTapped
        coordinator.onCameraTapped = onCameraTapped
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
        coordinator.refreshPoints(mapView: mapView, truckStops: truckStops, alerts: mapAlerts, cameras: cameras)
        if let fullLoc = locationManager.currentLocation {
            coordinator.lastKnownCoordinate = fullLoc.coordinate
            mapView.mapboxMap.setCamera(to: CameraOptions(center: fullLoc.coordinate, zoom: 14, bearing: 0, pitch: 0))
        }

        // FIX LINHA DE ROTA: makePolylineAnnotationManager chama addSource+addPersistentLayer
        // internamente. Se o estilo ainda não carregou (caso comum — MapView é criado async e o
        // estilo demora ~200-600ms), essas chamadas falham silenciosamente → a linha nunca aparece.
        // Quando o estilo carrega, reinstalamos os managers e redesenhamos.
        // IMPORTANTE: o AnyCancelable DEVE ser mantido vivo no Coordinator — descartá-lo com
        // `_ =` cancela a subscrição imediatamente antes de disparar.
        // `observeNext` dispara UMA vez; trocas de estilo explícitas já são cobertas por loadMapStyle.
        coordinator.styleLoadedToken = mapView.mapboxMap.onStyleLoaded.observeNext { [weak coordinator] _ in
            coordinator?.styleLoadedToken = nil   // libera o token após disparar
            guard let coordinator else { return }
            // O estilo carregou: reinstala os managers (addSource+addPersistentLayer precisam do
            // estilo carregado). NÃO redesenhamos a rota aqui com `self` capturado (struct stale
            // da criação do MapView — pode ter rota nil mesmo com rota ativa). Em vez disso,
            // invalidamos o fingerprint → o próximo updateUIView redesenha com dados ATUAIS.
            coordinator.installManagers(on: mapView)
            coordinator.lastRouteFingerprint = ""   // força redesenho da rota no próximo update
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
        Self.tuckMapboxOrnaments(mapView, bottomInset: mapboxBottomInset)
        let coord = context.coordinator
        coord.isNavigatingMode = isNavigating
        coord.syncDeadReckoning(isNavigating: isNavigating)
        coord.syncWeatherRadar(enabled: weatherRadarEnabled, on: mapView)
        coord.onTruckStopTapped = onTruckStopTapped
        coord.onCameraTapped = onCameraTapped
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

        // WATCHDOG DA LINHA DE ROTA (chão-da-verdade, roda a cada tick de GPS ≈1s):
        // no device o estilo pode recarregar / o Metal resetar / o addLayer falhar SEM nenhum
        // evento que a gente escute — o sintoma era "linha some e nunca volta" mesmo com a rota
        // ativa. Aqui checamos o estado REAL do mapa: camada "horizon-route" existe E o manager
        // tem annotations. Qualquer falha → reinstala managers e redesenha JÁ, com os dados
        // ATUAIS deste updateUIView (struct fresco — sem o bug de captura stale dos callbacks).
        // Converge em ≤2s para linha visível, qualquer que seja a causa da perda.
        if let coords = activeRouteCoordinates(), coords.count >= 2,
           !coord.routeLineIsAlive(on: mapView) {
            coord.installManagers(on: mapView)
            coord.refreshRoute(
                mapView: mapView,
                coords: coords,
                fingerprint: fp,
                quantumAccent: routeQuantumLineAccent,
                fitCameraToRoute: false,
                dimmed: dimRoute
            )
        }

        coord.refreshPoints(mapView: mapView, truckStops: truckStops, alerts: mapAlerts,
                            signage: isNavigating ? routeSignage : [], cameras: cameras)
        // Seta de manobra NA rota: marcador no ponto exato da próxima curva/saída (o motorista
        // vê NO MAPA onde vai virar, não só no banner). nil (idle/sem manobra) limpa.
        coord.updateManeuverMarker(
            coordinate: isNavigating ? maneuverMarkerCoordinate : nil,
            direction: maneuverMarkerDirection,
            segment: isNavigating ? maneuverSegment : []
        )
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
        LaunchTrace.mark("mapstyle.loadStyle called")
        mapView.mapboxMap.loadStyle(style.mapboxStyleURI) { error in
            LaunchTrace.mark("mapstyle.loaded err=\(error == nil ? "none" : "\(error!)")")
            DispatchQueue.main.async {
                self.applyUserLocationPuck(on: mapView, navigating: coordinator.isNavigatingMode)
                coordinator.installManagers(on: mapView)
                coordinator.resetLeadArrowAnchor()
                // Redesenho imediato (caminho rápido — normalmente os dados estão atuais)...
                coordinator.refreshRoute(
                    mapView: mapView,
                    coords: self.activeRouteCoordinates(),
                    fingerprint: self.routeFingerprint(),
                    quantumAccent: self.routeQuantumLineAccent,
                    fitCameraToRoute: !coordinator.isNavigatingMode
                )
                coordinator.refreshPoints(mapView: mapView, truckStops: self.truckStops, alerts: self.mapAlerts, cameras: self.cameras)
                // ...mas `self` aqui é o struct capturado na TROCA de estilo. Se a rota mudou
                // durante o load (~300ms — ex: reroute), desenhamos a rota VELHA acima. Invalidar
                // o fingerprint garante que o próximo updateUIView (todo tick de GPS) redesenhe
                // com os dados ATUAIS — mesma proteção do onStyleLoaded no bootstrapMap.
                coordinator.lastRouteFingerprint = ""
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
        /// Mantém o token do observer de estilo carregado vivo até disparar (AnyCancelable
        /// cancela a subscrição ao ser desalocado — não pode ser descartado com `_ =`).
        var styleLoadedToken: AnyCancelable?

        // MARK: - Tráfego ao vivo (Mapbox Traffic v1) + declutter por zoom
        private let trafficSourceId = "mapbox-traffic-src"
        private let trafficLayerId = "mapbox-traffic-layer"

        /// Camada de tráfego ao vivo do Mapbox (congestão colorida do dado real `mapbox-traffic-v1`).
        /// Hierarquia: entra ABAIXO da linha de rota ("horizon-route") → a rota laranja e o puck
        /// ficam por cima, com o maior contraste. Opacidade 0.55 (visível sem competir) e minZoom 14
        /// (só aparece no zoom de rua; na rodovia não polui). Defensivo: guarda por layerExists.
        private func addTrafficLayer(on mapView: MapboxMaps.MapView) {
            guard let map = mapView.mapboxMap else { return }
            guard !map.layerExists(withId: trafficLayerId) else { return }
            do {
                if !map.sourceExists(withId: trafficSourceId) {
                    var source = VectorSource(id: trafficSourceId)
                    source.url = "mapbox://mapbox.mapbox-traffic-v1"
                    try map.addSource(source)
                }
                var layer = LineLayer(id: trafficLayerId, source: trafficSourceId)
                layer.sourceLayer = "traffic"
                layer.lineWidth = .constant(2.5)
                layer.lineOpacity = .constant(0.55)
                layer.minZoom = 14
                // Cor por nível de congestão (campo `congestion` do tile do Mapbox).
                layer.lineColor = .expression(
                    Exp(.match) {
                        Exp(.get) { "congestion" }
                        "low";      UIColor.systemGreen
                        "moderate"; UIColor.systemYellow
                        "heavy";    UIColor.systemOrange
                        "severe";   UIColor.systemRed
                        UIColor.clear   // default (sem dado) → invisível
                    }
                )
                if map.layerExists(withId: "horizon-route") {
                    try map.addLayer(layer, layerPosition: .below("horizon-route"))
                } else {
                    try map.addLayer(layer)
                }
            } catch {
                #if DEBUG
                print("[Traffic] addLayer falhou: \(error.localizedDescription)")
                #endif
            }
        }

        /// Declutter por zoom: ícones de serviço/sinalização só a partir do zoom 14 (rua) — limpo na
        /// rodovia, detalhado na cidade. Alertas de SEGURANÇA (pesagem etc.) ficam de fora: sempre visíveis.
        private func applyIconZoomFilters(on mapView: MapboxMaps.MapView) {
            guard let map = mapView.mapboxMap else { return }
            // Detalhe de rua (câmeras): só a partir do zoom 14 — limpo na rodovia.
            // ("horizon-signage" NÃO entra: ponte baixa é SEGURANÇA e fica visível em todo zoom;
            //  semáforo/PARE são filtrados por item no refreshSignage a partir do zoom 13.5.)
            if map.layerExists(withId: "horizon-cameras") {
                try? map.setLayerProperty(for: "horizon-cameras", property: "minzoom", value: 14)
            }
            // Truck stops/postos: a partir do zoom 10 — quando o motorista AFASTA o zoom para se
            // orientar ("onde estou?"), os postos do corredor continuam visíveis como referência.
            // (O clamp do zoom de navegação vai até 11; com minzoom 14 o mapa ficava VAZIO.)
            if map.layerExists(withId: "horizon-stops") {
                try? map.setLayerProperty(for: "horizon-stops", property: "minzoom", value: 10)
            }
        }

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
        /// Zoom manual (+/−) tem prioridade sobre o auto-zoom por 45s.
        private var lastManualNavZoomAt: Date = .distantPast

        /// LOOK-AHEAD: puck ancorado no TERÇO INFERIOR da tela (padding top pesado) — a maior
        /// parte da tela mostra a estrada À FRENTE (course-up = frente é pra cima). O motorista
        /// vê as saídas chegando com muito mais antecedência (pedido do road test 01/07).
        private var navPadding: UIEdgeInsets {
            // top 460: puck a ~70% da altura (referência Trucker Path do road test) — quase a
            // tela toda vira estrada à frente; bottom 120 limpa a barra de trip.
            UIEdgeInsets(top: 460, left: 0, bottom: 120, right: 0)
        }

        /// Auto-zoom por velocidade REAL do GPS: rodovia (≥52mph) afasta pra ver saídas/contexto
        /// a quilômetros; cidade aproxima pro detalhe de cruzamento. Zoom manual pausa por 45s.
        private func autoNavZoomTarget() -> CGFloat {
            if lastRealSpeed >= 23.5 { return 15.0 }    // ≥ ~52 mph: rodovia — visão ampla
            if lastRealSpeed >= 16.5 { return 15.75 }   // ~37-52 mph: via expressa
            return 16.5                                  // cidade — detalhe de cruzamento
        }

        private func makeFollowOptions() -> FollowPuckViewportStateOptions {
            var opts = FollowPuckViewportStateOptions()
            opts.zoom = navigationZoom
            opts.padding = navPadding      // puck embaixo → estrada à frente ocupa a tela
            opts.pitch = 50                // visão inclinada pra frente (GPS de verdade)
            // `.course` lê `location.bearing` (o rumo do corredor que emitimos), NÃO o heading da
            // bússola. iPad sem bússola / sem sinal de heading não gira com `.heading`, mas o
            // `location.bearing` flui igual (o puck anda) → câmera gira course-up em qualquer device.
            opts.bearing = .course
            return opts
        }

        func setNavigationZoom(_ zoom: CGFloat, on mapView: MapboxMaps.MapView) {
            navigationZoom = min(max(zoom, 11), 20)
            lastManualNavZoomAt = Date()   // respeita o zoom manual: auto-zoom pausa 45s
            guard followPuckActive else { return }
            let state = mapView.viewport.makeFollowPuckViewportState(options: makeFollowOptions())
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
                // AUTO-ZOOM por velocidade: alvo muda de classe (cidade↔rodovia) → recria o
                // viewport com o novo zoom. Zoom manual (+/−) tem prioridade por 45s.
                if followPuckActive {
                    let target = autoNavZoomTarget()
                    if abs(target - navigationZoom) >= 0.7,
                       Date().timeIntervalSince(lastManualNavZoomAt) > 45 {
                        navigationZoom = target
                        let state = mapView.viewport.makeFollowPuckViewportState(options: makeFollowOptions())
                        followPuckState = state
                        mapView.viewport.transition(to: state)
                    }
                    return
                }
                let state = mapView.viewport.makeFollowPuckViewportState(options: makeFollowOptions())
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
        /// Seta branca da manobra (trecho ±80m sobre a linha) — camada acima da rota.
        private var maneuverLineManager: PolylineAnnotationManager?
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
        // Câmeras de trânsito 511 (mesmo padrão dos truck stops).
        private var cameraManager: PointAnnotationManager?
        private var lastCamerasFingerprint: Int?
        private var cachedCameraImage: PointAnnotation.Image?
        var onCameraTapped: ((TrafficCamera) -> Void)?

        /// Incremental polyline anchor for route chevron (reset when route geometry changes).
        private var lastLeadArrowPolyIndex: Int = 0
        private var lastRouteArrowUpdateAt: Date = .distantPast
        private var lastRouteArrowUserLoc: CLLocation?

        private var smoothedRouteCoord: CLLocationCoordinate2D?
        private var smoothedRouteBearing: Double = 0
        /// Last bearing emitted to the puck — reused when GPS course is invalid (stationary).
        private var lastEmittedBearing: CLLocationDirection = 0

        var hasRouteNavigationAnchor: Bool { smoothedRouteCoord != nil }

        // MARK: - Dead-reckoning (P0 #2 da auditoria de segurança): continuidade em túnel/cânion.
        // Quando o GPS para de chegar (3s…35s) e o último fix REAL estava NA ROTA em velocidade de
        // via (≥5 m/s), o puck continua avançando pela polilinha na última velocidade conhecida —
        // igual CoPilot/Google em túnel. ESCOPO VISUAL APENAS: o NavigationEngine NÃO recebe posição
        // sintética (sem avanço de passo, sem reroute em dado estimado — zero falso positivo).
        // Parado no túnel (speed<5) NÃO deriva. GPS volta → snap real reassume no próximo fix.
        private var deadReckonTimer: Timer?
        private var lastRealFixAt: Date?
        private var lastRealSpeed: Double = 0
        private var lastEmitWasSnap = false
        private var lastRouteCoordsForDR: [CLLocationCoordinate2D] = []

        deinit {
            deadReckonTimer?.invalidate()
            weatherRadarTimer?.invalidate()
        }

        /// Liga/desliga o timer de dead-reckoning conforme o modo de navegação (idempotente por tick).
        func syncDeadReckoning(isNavigating: Bool) {
            if isNavigating {
                guard deadReckonTimer == nil else { return }
                deadReckonTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.deadReckonTick()
                }
            } else {
                deadReckonTimer?.invalidate()
                deadReckonTimer = nil
            }
        }

        private func deadReckonTick() {
            guard isNavigatingMode, lastEmitWasSnap,
                  let fixAt = lastRealFixAt,
                  let cur = smoothedRouteCoord,
                  lastRouteCoordsForDR.count >= 2 else { return }
            let age = Date().timeIntervalSince(fixAt)
            // Janela: começa após 3s sem fix (interpolação do Mapbox cobre até aí) e para em 35s
            // (além disso a estimativa vira chute — o puck congela e a UI mostra "SEM GPS").
            guard age >= 3, age <= 35 else { return }
            // Só com velocidade de via plausível (5…42 m/s ≈ 11…94 mph); parado não deriva.
            guard lastRealSpeed >= 5, lastRealSpeed <= 42 else { return }

            var anchor = lastLeadArrowPolyIndex
            guard let ahead = PolylineLeadArrow.lookaheadPoint(
                coords: lastRouteCoordsForDR,
                user: CLLocation(latitude: cur.latitude, longitude: cur.longitude),
                lookaheadMeters: lastRealSpeed * 1.0,   // 1 tick = 1s na última velocidade real
                anchorIndex: &anchor
            ) else { return }
            lastLeadArrowPolyIndex = anchor
            smoothedRouteCoord = ahead.coordinate
            smoothedRouteBearing = ahead.bearingDegrees
            lastEmittedBearing = ahead.bearingDegrees
            snapProvider.emit(coordinate: ahead.coordinate, bearing: ahead.bearingDegrees, speed: lastRealSpeed)
        }

        func resetLeadArrowAnchor() {
            lastLeadArrowPolyIndex = 0
            lastRouteArrowUserLoc = nil
            lastRouteArrowUpdateAt = .distantPast
            smoothedRouteCoord = nil
            smoothedRouteBearing = 0
            // Rota nova = estado de dead-reckoning zerado (âncora/coords antigos não podem
            // projetar o puck na geometria errada durante a troca).
            lastEmitWasSnap = false
            lastRouteCoordsForDR = []
        }

        /// Watchdog: GROUND TRUTH da linha de rota no mapa real — a camada "horizon-route"
        /// existe E o manager tem annotations. false = linha perdida (qualquer causa) →
        /// o updateUIView reinstala e redesenha com dados atuais.
        func routeLineIsAlive(on mapView: MapboxMaps.MapView) -> Bool {
            guard let mgr = routeLineManager, !mgr.annotations.isEmpty else { return false }
            return mapView.mapboxMap.layerExists(withId: "horizon-route")
        }

        func clearRouteNavigationArrow() {
            routeArrowManager?.annotations = []
            lastRouteArrowUserLoc = nil
            smoothedRouteCoord = nil
        }

        func clearLeadNavigationArrow() { clearRouteNavigationArrow() }

        /// Seta de manobra NA rota (ponto exato da curva/saída, do NavigationEngine).
        /// Idempotente por (direção, coordenada) — não recria annotation a cada tick.
        private var lastManeuverMarkerKey: String?
        func updateManeuverMarker(coordinate: CLLocationCoordinate2D?, direction: String?,
                                  segment: [CLLocationCoordinate2D] = []) {
            guard let mgr = routeArrowManager else { return }
            guard let coordinate, let direction else {
                if lastManeuverMarkerKey != nil {
                    mgr.annotations = []
                    maneuverLineManager?.annotations = []
                    lastManeuverMarkerKey = nil
                }
                return
            }
            let key = String(format: "%@:%.5f,%.5f:%d", direction, coordinate.latitude, coordinate.longitude, segment.count)
            guard key != lastManeuverMarkerKey else { return }
            lastManeuverMarkerKey = key

            // SETA BRANCA sobre a rota (estilo Trucker Path): o trecho REAL da polilinha
            // atravessando a curva, com contorno escuro p/ contraste em qualquer estilo de mapa.
            if segment.count >= 2, let lineMgr = maneuverLineManager {
                var casing = PolylineAnnotation(lineCoordinates: segment)
                casing.lineColor = StyleColor(UIColor.black.withAlphaComponent(0.55))
                casing.lineWidth = 13
                casing.lineJoin = LineJoin.round
                casing.lineSortKey = 0
                var arrowLine = PolylineAnnotation(lineCoordinates: segment)
                arrowLine.lineColor = StyleColor(UIColor.white)
                arrowLine.lineWidth = 9
                arrowLine.lineJoin = LineJoin.round
                arrowLine.lineSortKey = 1
                lineMgr.annotations = [casing, arrowLine]
            } else {
                maneuverLineManager?.annotations = []
            }

            var ann = PointAnnotation(id: "maneuver-marker", coordinate: coordinate)
            ann.iconAnchor = .center
            if let img = HorizonMapboxPinImages.maneuverArrowImage(direction: direction) {
                ann.image = img
            }
            mgr.annotations = [ann]
        }

        func installManagers(on mapView: MapboxMaps.MapView) {
            // Drive the native puck from our route-snapped provider (once — persists across style
            // reloads). Mapbox interpolates between the samples we emit at 60fps. API NÃO-deprecated
            // da v11: `dataModel` (publishers) em vez do antigo `override(provider:)`. Equivalente —
            // o override fazia exatamente isto por dentro (montava um LocationDataModel dos signals).
            if !snapProviderInstalled {
                mapView.location.dataModel = LocationDataModel(
                    location: snapProvider.locationPublisher.eraseToAnyPublisher(),
                    heading: snapProvider.headingPublisher.eraseToAnyPublisher()
                )
                snapProviderInstalled = true
            }
            routeLineManager = mapView.annotations.makePolylineAnnotationManager(id: "horizon-route")
            maneuverLineManager = mapView.annotations.makePolylineAnnotationManager(id: "horizon-maneuver-line")
            routeArrowManager = mapView.annotations.makePointAnnotationManager(id: "horizon-route-lead-arrow")
            truckStopManager = mapView.annotations.makePointAnnotationManager(id: "horizon-stops")
            cameraManager = mapView.annotations.makePointAnnotationManager(id: "horizon-cameras")
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
            mapView.location.options.puckBearing = .course   // lê location.bearing (corredor), não a bússola — consistente c/ a câmera no iPad
            mapView.location.options.puckBearingEnabled = true
            // Managers recriados começam vazios → força refreshPoints a re-adicionar os pins.
            lastStopsFingerprint = nil
            lastCamerasFingerprint = nil
            lastAlertsFingerprint = nil
            lastSignageFingerprint = nil

            // Contexto pro motorista: tráfego ao vivo (abaixo da rota) + declutter por zoom dos ícones.
            // Aqui, no fim do install, a linha de rota "horizon-route" já existe → o tráfego entra abaixo dela.
            addTrafficLayer(on: mapView)
            applyIconZoomFilters(on: mapView)
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
            // ⚠️ VANISHING LINE (lineTrimOffset) REMOVIDA — CAUSA-RAIZ da linha invisível no DEVICE.
            // A spec do Mapbox exige `lineMetrics: true` na fonte GeoJSON para `line-trim-offset`
            // funcionar; a fonte dos annotation managers NUNCA habilita lineMetrics (verificado no
            // SDK v11.23: AnnotationManagerImpl não seta) → comportamento INDEFINIDO: o simulador
            // degrada benigno (linha aparece), o Metal do device renderia a linha INTEIRA invisível.
            // Timeline confirma: linha funcionava na era da seta (sem trim); morreu quando o trim
            // entrou junto com o puck de caminhão (20/06). NUNCA reintroduzir lineTrimOffset em
            // PolylineAnnotationManager — só com camada própria (addSource lineMetrics:true).
            // LOCK DE COEXISTÊNCIA (linha + seta): ao (re)desenhar a linha, garante que a camada do
            // puck (seta/caminhão, id nativo "puck" do LocationIndicatorLayer v11) fica ACIMA da linha
            // de rota ("horizon-route"). NÃO recria o puck (sem flicker) e NÃO mexe na linha. `try?` =
            // no-op seguro se alguma camada ainda não existir. Assim a linha NUNCA cobre a seta.
            try? mapView.mapboxMap.moveLayer(withId: "puck", to: .above("horizon-route"))
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

            // CONSISTÊNCIA linha+seta+posição (igual Google/Apple): durante a navegação a SETA anda
            // SOBRE a linha da rota (snap), não no GPS cru deslocado na faixa. A linha segue a via,
            // a seta segue a linha -> tudo bate. Mostra GPS REAL só quando o motorista está DE FATO
            // fora da rota (>35m: cobre faixa ~3m + ruído de GPS), aí o auto-reroute religa. Rumo =
            // corredor (suave), sem o tremor do course.
            guard let snap = PolylineLeadArrow.snappedPosition(
                coords: coords,
                user: user,
                anchorIndex: &lastLeadArrowPolyIndex
            ) else {
                emitRawLocation(user: user)
                return
            }
            let snapped = CLLocation(latitude: snap.coordinate.latitude, longitude: snap.coordinate.longitude)
            // Alimenta o dead-reckoning com o estado REAL deste fix (timestamp/velocidade/na-rota).
            lastRealFixAt = Date()
            lastRealSpeed = max(0, user.speed)
            lastRouteCoordsForDR = coords
            if snapped.distance(from: user) <= 35 {
                // (Trim da "vanishing line" removido daqui — ver comentário no refreshRoute:
                // line-trim-offset sem lineMetrics na fonte = linha invisível no device.)
                // Na rota: a seta GRUDA na linha (consistente).
                lastEmitWasSnap = true
                lastEmittedBearing = snap.bearingDegrees
                smoothedRouteCoord = snap.coordinate
                smoothedRouteBearing = snap.bearingDegrees
                snapProvider.emit(coordinate: snap.coordinate, bearing: snap.bearingDegrees, speed: max(0, user.speed))
            } else {
                // Fora da rota de verdade: GPS real honesto (o reroute religa a linha).
                // Dead-reckoning DESLIGADO fora da rota — projetar pela polilinha seria mentira.
                lastEmitWasSnap = false
                let bearing = user.course >= 0 ? user.course : lastEmittedBearing
                lastEmittedBearing = bearing
                smoothedRouteCoord = user.coordinate
                smoothedRouteBearing = bearing
                snapProvider.emit(coordinate: user.coordinate, bearing: bearing, speed: max(0, user.speed))
            }
        }

        /// Feeds the native puck with raw GPS while idle (no route). Mapbox still interpolates
        /// between fixes, so the idle puck stays smooth. Uses the last known bearing when the
        /// GPS course is invalid (course < 0 when stationary).
        func emitRawLocation(user: CLLocation) {
            lastEmitWasSnap = false   // idle/sem rota: dead-reckoning não se aplica
            lastRealFixAt = Date()
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

        /// Pins de câmera 511 — mesma estratégia (fingerprint p/ não reconstruir por frame, 1 ícone
        /// em cache pra todas, tap → onCameraTapped). Lista vazia = sem pins (nada fabricado).
        private func refreshCameras(cameras: [TrafficCamera]) {
            guard let camMgr = cameraManager else { return }
            var hasher = Hasher()
            for c in cameras { hasher.combine(c.id) }
            let fp = hasher.finalize()
            guard fp != lastCamerasFingerprint else { return }
            lastCamerasFingerprint = fp
            let img = cachedCameraImage ?? HorizonMapboxPinImages.trafficCameraImage()
            cachedCameraImage = img
            var anns: [PointAnnotation] = []
            anns.reserveCapacity(cameras.count)
            for c in cameras {
                var ann = PointAnnotation(id: "cam-\(c.id)", coordinate: c.coordinate)
                ann.iconAnchor = .bottom
                if let img { ann.image = img }
                let captured = c
                ann.tapHandler = { [weak self] _ in
                    self?.onCameraTapped?(captured)
                    return true
                }
                anns.append(ann)
            }
            camMgr.annotations = anns
        }

        func refreshPoints(mapView: MapboxMaps.MapView, truckStops: [TruckStopItem], alerts: [MapAlert],
                           signage: [RouteSignageItem] = [], cameras: [TrafficCamera] = []) {
            refreshSignage(mapView: mapView, signage: signage)
            refreshCameras(cameras: cameras)
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
                    // Cache por TIPO+rede (rest area não pode reusar o ícone de bomba da rede).
                    let key = "\(stop.poiType)-\(stop.network)"
                    if let img = stopImageCache[key] ?? HorizonMapboxPinImages.truckStopImage(for: stop) {
                        stopImageCache[key] = img
                        ann.image = img
                    }
                    // NOME no pin (pedido do road test): motorista identifica o posto/parada
                    // sem tocar — nome REAL do banco, truncado p/ não poluir.
                    let label = stop.name.count > 16 ? String(stop.name.prefix(15)) + "…" : stop.name
                    ann.textField = label
                    ann.textSize = 10
                    ann.textAnchor = .top
                    ann.textOffset = [0, 1.4]
                    ann.textColor = StyleColor(UIColor.white)
                    ann.textHaloColor = StyleColor(UIColor.black.withAlphaComponent(0.85))
                    ann.textHaloWidth = 1.2
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
            // Semáforo/PARE só no zoom de rua; PONTE BAIXA sempre visível (segurança).
            let visible = signage.filter { $0.kind == .lowBridge || zoom >= 13.5 }

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
                // Ponte baixa: a ALTURA REAL (NBI) vai como texto no pin — "12'4\"".
                if s.kind == .lowBridge, let clr = s.clearanceText {
                    ann.textField = clr
                    ann.textSize = 11
                    ann.textAnchor = .top
                    ann.textOffset = [0, 1.1]
                    ann.textColor = StyleColor(UIColor.black)
                    ann.textHaloColor = StyleColor(UIColor.systemYellow)
                    ann.textHaloWidth = 1.6
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
            case .railCrossing:
                // Passagem de nível — sinal rodoviário US: círculo amarelo de aviso + "X" preto (crossbuck).
                let cxp = size / 2, cyp = size / 2, rad = size * 0.46
                c.setFillColor(UIColor.systemYellow.cgColor)
                c.fillEllipse(in: CGRect(x: cxp - rad, y: cyp - rad, width: rad * 2, height: rad * 2))
                c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(1.4)
                c.strokeEllipse(in: CGRect(x: cxp - rad, y: cyp - rad, width: rad * 2, height: rad * 2))
                c.setStrokeColor(UIColor.black.cgColor); c.setLineWidth(size * 0.11); c.setLineCap(.round)
                let inset = size * 0.30
                c.move(to: CGPoint(x: inset, y: inset)); c.addLine(to: CGPoint(x: size - inset, y: size - inset))
                c.move(to: CGPoint(x: size - inset, y: inset)); c.addLine(to: CGPoint(x: inset, y: size - inset))
                c.strokePath()
            case .lowBridge:
                // Ponte baixa — losango amarelo MUTCD (sinal de aviso US) com arco de ponte e
                // linha de "teto"; a ALTURA em texto vai no textField do pin (dado real do NBI).
                let cxp = size / 2, cyp = size / 2, rad = size * 0.48
                let diamond = UIBezierPath()
                diamond.move(to: CGPoint(x: cxp, y: cyp - rad))
                diamond.addLine(to: CGPoint(x: cxp + rad, y: cyp))
                diamond.addLine(to: CGPoint(x: cxp, y: cyp + rad))
                diamond.addLine(to: CGPoint(x: cxp - rad, y: cyp))
                diamond.close()
                c.setFillColor(UIColor.systemYellow.cgColor); c.addPath(diamond.cgPath); c.fillPath()
                c.setStrokeColor(UIColor.black.cgColor); c.setLineWidth(1.4); c.addPath(diamond.cgPath); c.strokePath()
                // teto + seta pra baixo (altura limitada)
                c.setStrokeColor(UIColor.black.cgColor); c.setLineWidth(size * 0.09); c.setLineCap(.round)
                c.move(to: CGPoint(x: cxp - rad * 0.5, y: cyp - rad * 0.28))
                c.addLine(to: CGPoint(x: cxp + rad * 0.5, y: cyp - rad * 0.28))
                c.strokePath()
                c.move(to: CGPoint(x: cxp, y: cyp - rad * 0.18)); c.addLine(to: CGPoint(x: cxp, y: cyp + rad * 0.38))
                c.move(to: CGPoint(x: cxp - rad * 0.18, y: cyp + rad * 0.18)); c.addLine(to: CGPoint(x: cxp, y: cyp + rad * 0.38))
                c.move(to: CGPoint(x: cxp + rad * 0.18, y: cyp + rad * 0.18)); c.addLine(to: CGPoint(x: cxp, y: cyp + rad * 0.38))
                c.strokePath()
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
        // Ícone segue o TIPO REAL do POI (road test 01/07: rest areas/marcos históricos
        // apareciam com bomba de combustível — informação FALSA pro motorista).
        let size: CGFloat = 38
        let fill: UIColor
        let iconName: String
        switch stop.poiType {
        case "rest_area":
            fill = UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)   // verde rest area
            iconName = "bed.double.fill"
        case "weigh_station":
            fill = UIColor(red: 0.55, green: 0.35, blue: 0.12, alpha: 1)   // âmbar balança
            iconName = "scalemass.fill"
        default:   // truck_stop / fuel — ícone da rede
            fill = UIColor(stop.network.brandColor)
            switch stop.network {
            case .pilotFlyingJ: iconName = "airplane.departure"
            case .loves: iconName = "heart.fill"
            case .taPetro: iconName = "car.side.fill"
            case .kwikTrip: iconName = "bolt.fill"
            default: iconName = "fuelpump.fill"
            }
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let uiImage = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            ctx.cgContext.setFillColor(fill.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
            ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            if let img = UIImage(systemName: iconName, withConfiguration: cfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: (size - img.size.width) / 2, y: (size - img.size.height) / 2)
                img.draw(at: origin)
            }
        }
        let name = "ts-\(stop.poiType)-\(stop.network)"
        return PointAnnotation.Image(image: uiImage, name: name, sdf: false)
    }

    /// Seta de manobra sobre a rota — disco branco com chevron DIAGONAL (arrow.up.left/right:
    /// aponta frente+lado; as setas "turn.up.*" liam como "responder" — lição do road test 22/06).
    static func maneuverArrowImage(direction: String) -> PointAnnotation.Image? {
        let icon: String
        switch direction {
        case "left":  icon = "arrow.up.left"
        case "right": icon = "arrow.up.right"
        default:      icon = "arrow.up"
        }
        let size: CGFloat = 34
        let orange = UIColor(red: 0.96, green: 0.49, blue: 0.09, alpha: 1)
        let ui = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3,
                                    color: UIColor.black.withAlphaComponent(0.4).cgColor)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: rect.insetBy(dx: 1, dy: 1))
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.cgContext.setStrokeColor(orange.cgColor)
            ctx.cgContext.setLineWidth(2.5)
            ctx.cgContext.strokeEllipse(in: rect.insetBy(dx: 2.5, dy: 2.5))
            let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .black)
            if let img = UIImage(systemName: icon, withConfiguration: cfg)?
                .withTintColor(.black, renderingMode: .alwaysOriginal) {
                img.draw(at: CGPoint(x: (size - img.size.width) / 2, y: (size - img.size.height) / 2))
            }
        }
        return PointAnnotation.Image(image: ui, name: "mn-\(direction)", sdf: false)
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

    /// Pin de câmera de trânsito 511 — ícone de vídeo num pin teal. Todas usam o mesmo (cache).
    static func trafficCameraImage() -> PointAnnotation.Image? {
        let size: CGFloat = 30
        let fill = UIColor(red: 0.10, green: 0.65, blue: 0.66, alpha: 1)
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerRadius: 8)
            fill.setFill(); path.fill()
            UIColor.white.withAlphaComponent(0.9).setStroke(); path.lineWidth = 1.5; path.stroke()
            if let sym = UIImage(systemName: "video.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                sym.draw(in: CGRect(x: 7, y: 8, width: 16, height: 14))
            }
        }
        return PointAnnotation.Image(image: img, name: "traffic-camera-pin", sdf: false)
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

    /// Cursor de navegação = CAMINHÃO top-down preto-e-laranja (marca Trucker Easy),
    /// desenhado apontando pra FRENTE = topo (0° = norte). O Puck2D do Mapbox rotaciona
    /// pro rumo do corredor com interpolação, então ele sempre aponta no sentido da viagem.
    ///
    /// O road test anterior reclamou que o caminhão "lia de cabeça pra baixo". A causa era
    /// silhueta ambígua (frente/trás indistinguíveis). Aqui a DIANTEIRA é inequívoca:
    /// cabine LARANJA + para-brisa claro no topo, baú PRETO atrás, nariz arredondado e
    /// traseira reta. Contorno branco + sombra p/ destacar em qualquer estilo de mapa.
    static func userNavigationArrowPuckImage() -> UIImage {
        let size = CGSize(width: 46, height: 46)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: size.width / 2, y: size.height / 2)

            let orange = UIColor(red: 0.96, green: 0.49, blue: 0.09, alpha: 1)   // laranja da marca
            let bodyBlack = UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1) // baú preto
            let glass = UIColor(red: 0.66, green: 0.81, blue: 0.96, alpha: 1)     // para-brisa

            // Silhueta do corpo (frente=topo): nariz arredondado, traseira menos arredondada.
            let bodyRect = CGRect(x: -9, y: -16, width: 18, height: 32)
            let body = UIBezierPath(roundedRect: bodyRect, cornerRadius: 5)

            // Contorno branco (corpo inflado) + sombra → destaca em mapa claro/escuro/satélite.
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 4,
                        color: UIColor.black.withAlphaComponent(0.45).cgColor)
            c.setFillColor(UIColor.white.cgColor)
            let outline = UIBezierPath(roundedRect: bodyRect.insetBy(dx: -2.5, dy: -2.5), cornerRadius: 7)
            c.addPath(outline.cgPath); c.fillPath()
            c.setShadow(offset: .zero, blur: 0, color: nil)

            // Baú (traseira) preto — corpo inteiro como base.
            c.setFillColor(bodyBlack.cgColor)
            c.addPath(body.cgPath); c.fillPath()

            // Cabine (terço dianteiro) laranja.
            let cab = UIBezierPath(roundedRect: CGRect(x: -9, y: -16, width: 18, height: 13), cornerRadius: 5)
            c.setFillColor(orange.cgColor)
            c.addPath(cab.cgPath); c.fillPath()

            // Para-brisa: faixa clara colada na frente = marca a DIANTEIRA sem ambiguidade.
            let windshield = UIBezierPath(roundedRect: CGRect(x: -6, y: -14, width: 12, height: 4.5), cornerRadius: 2)
            c.setFillColor(glass.cgColor)
            c.addPath(windshield.cgPath); c.fillPath()

            // Costura cabine/baú (engate) — linha fina escura.
            c.setStrokeColor(bodyBlack.withAlphaComponent(0.6).cgColor)
            c.setLineWidth(1)
            c.move(to: CGPoint(x: -9, y: -3)); c.addLine(to: CGPoint(x: 9, y: -3)); c.strokePath()
        }
    }

    /// Fully transparent — hides puck while navigating (lead arrow on route is enough).
    static func invisiblePuckImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    }
}

#endif
