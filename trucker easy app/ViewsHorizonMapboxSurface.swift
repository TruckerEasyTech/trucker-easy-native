#if canImport(MapboxMaps)
import SwiftUI
import MapKit
import CoreLocation
import MapboxMaps
import UIKit

// MARK: - Map style → Mapbox StyleURI

extension MapStyleOption {
    fileprivate var mapboxStyleURI: StyleURI {
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
    var onStyleChange: ((MapStyleOption) -> Void)? = nil
    var onControlsReady: (((zoomIn: () -> Void, zoomOut: () -> Void, recenter: () -> Void)) -> Void)? = nil
    var mapControls: MapControlActions? = nil
    var truckStops: [TruckStopItem] = []
    var onTruckStopTapped: ((TruckStopItem) -> Void)? = nil

    private func activeRouteCoordinates() -> [CLLocationCoordinate2D]? {
        if let tr = truckRoute, tr.coordinates.count >= 2 { return tr.coordinates }
        guard let poly = route?.polyline, poly.pointCount >= 2 else { return nil }
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: poly.pointCount)
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: poly.pointCount))
        return coords
    }

    private func routeFingerprint() -> String {
        if let tr = truckRoute {
            return "tr:\(tr.coordinates.count):\(Int(tr.distanceMeters)):q\(routeQuantumLineAccent ? 1 : 0)"
        }
        if let r = route {
            return "mk:\(r.polyline.pointCount):\(Int(r.distance))"
        }
        return "none"
    }

    /// Idle map shows truck puck; during navigation only the lead chevron on the route is shown.
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

    /// Custom truck puck (red cab) — replaces Mapbox default blue dot.
    private func applyUserLocationPuck(on mapView: MapboxMaps.MapView, navigating: Bool) {
        var puckConfig = Puck2DConfiguration()
        puckConfig.showsAccuracyRing = false
        puckConfig.topImage = HorizonMapboxPinImages.userTruckPuckImage()
        puckConfig.scale = .constant(navigating ? 1.08 : 1.0)
        mapView.location.options.puckType = .puck2D(puckConfig)
        mapView.location.options.puckBearing = .course
        mapView.location.options.puckBearingEnabled = true
    }

    private func bootstrapMap(_ mapView: MapboxMaps.MapView, coordinator: Coordinator) {
        mapView.overrideUserInterfaceStyle = isNavigating ? .dark : .light
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
            fitCameraToRoute: !isNavigating
        )
        coordinator.refreshPoints(mapView: mapView, truckStops: truckStops, alerts: mapAlerts)
        if let fullLoc = locationManager.currentLocation {
            coordinator.lastKnownCoordinate = fullLoc.coordinate
            mapView.mapboxMap.setCamera(to: CameraOptions(center: fullLoc.coordinate, zoom: 14, bearing: 0, pitch: 0))
        }
    }

    func makeUIView(context: Context) -> HorizonMapboxMapHostView {
        let initOptions = MapInitOptions(styleURI: selectedMapStyle.mapboxStyleURI)
        let host = HorizonMapboxMapHostView(mapInitOptions: initOptions)
        let coordinator = context.coordinator
        host.onMapViewReady = { [self] mapView in
            bootstrapMap(mapView, coordinator: coordinator)
            onControlsReady?((
                zoomIn: {
                    guard let map = coordinator.mapView else { return }
                    let z = map.mapboxMap.cameraState.zoom
                    map.mapboxMap.setCamera(to: CameraOptions(zoom: min(z + 1, 22)))
                },
                zoomOut: {
                    guard let map = coordinator.mapView else { return }
                    let z = map.mapboxMap.cameraState.zoom
                    map.mapboxMap.setCamera(to: CameraOptions(zoom: max(z - 1, 2)))
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
        mapView.overrideUserInterfaceStyle = isNavigating ? .dark : .light
        applyUserLocationPuck(on: mapView, navigating: isNavigating)
        Self.tuckMapboxOrnaments(mapView, navigating: isNavigating)
        let coord = context.coordinator
        coord.isNavigatingMode = isNavigating
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
            if isNavigating {
                coord.deferredStyle = selectedMapStyle
            } else {
                coord.lastStyle = selectedMapStyle
                coord.deferredStyle = nil
                loadMapStyle(selectedMapStyle, on: mapView, coordinator: coord)
            }
        }

        let fp = routeFingerprint()
        let routeGeometryChanged = coord.lastRouteFingerprint != fp
        if routeGeometryChanged {
            coord.lastRouteFingerprint = fp
            coord.resetCameraFollowThrottle()
            coord.resetLeadArrowAnchor()
            if isNavigating {
                coord.requestInitialRouteCameraFit()
            }
            coord.refreshRoute(
                mapView: mapView,
                coords: activeRouteCoordinates(),
                fingerprint: fp,
                quantumAccent: routeQuantumLineAccent,
                fitCameraToRoute: !isNavigating
            )
        }

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

        if !isNavigating, let deferred = coord.deferredStyle {
            coord.lastStyle = deferred
            coord.deferredStyle = nil
            loadMapStyle(deferred, on: mapView, coordinator: coord)
        }

        coord.refreshPoints(mapView: mapView, truckStops: truckStops, alerts: mapAlerts)
        if isNavigating, let coords = activeRouteCoordinates(), coords.count >= 2,
           let user = locationManager.currentLocation {
            coord.refreshRouteNavigationArrow(
                mapView: mapView,
                coords: coords,
                user: user,
                quantumAccent: routeQuantumLineAccent
            )
        } else {
            coord.clearRouteNavigationArrow()
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
        var onTruckStopTapped: ((TruckStopItem) -> Void)?
        var onStyleChange: ((MapStyleOption) -> Void)?
        var lastRouteFingerprint: String = ""
        var lastStyle: MapStyleOption = .standard
        var deferredStyle: MapStyleOption?
        var lastKnownCoordinate: CLLocationCoordinate2D?
        var isNavigatingMode = false
        var wasNavigatingMode = false
        private var needsInitialRouteCameraFit = false
        private var followPuckAllowedAfter: Date = .distantPast

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
                    zoom: 16.5,
                    bearing: smoothedRouteBearing,
                    pitch: 45
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
                opts.zoom = 16.5
                opts.pitch = 45
                opts.bearing = .course
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

        /// Incremental polyline anchor for route chevron (reset when route geometry changes).
        private var lastLeadArrowPolyIndex: Int = 0
        private var lastRouteArrowUpdateAt: Date = .distantPast
        private var lastRouteArrowUserLoc: CLLocation?

        private var smoothedRouteCoord: CLLocationCoordinate2D?
        private var smoothedRouteBearing: Double = 0

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
            routeLineManager = mapView.annotations.makePolylineAnnotationManager(id: "horizon-route")
            routeArrowManager = mapView.annotations.makePointAnnotationManager(id: "horizon-route-lead-arrow")
            truckStopManager = mapView.annotations.makePointAnnotationManager(id: "horizon-stops")
            alertManager = mapView.annotations.makePointAnnotationManager(id: "horizon-alerts")
        }

        func refreshRoute(
            mapView: MapboxMaps.MapView,
            coords: [CLLocationCoordinate2D]?,
            fingerprint _: String,
            quantumAccent: Bool,
            fitCameraToRoute: Bool
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
            var casing = PolylineAnnotation(lineCoordinates: coords)
            casing.lineColor = StyleColor(HorizonRouteColors.routeCasingUI)
            casing.lineWidth = 18
            casing.lineJoin = LineJoin.round
            casing.lineSortKey = 0

            var main = PolylineAnnotation(lineCoordinates: coords)
            let mainUIColor: UIColor = quantumAccent
                ? HorizonRouteColors.quantumPurpleUI
                : HorizonRouteColors.routeOrangeUI
            main.lineColor = StyleColor(mainUIColor)
            main.lineWidth = quantumAccent ? 15 : 14
            main.lineJoin = LineJoin.round
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

        /// Single chevron snapped to the route polyline — camera follows it smoothly (no GPS puck).
        func refreshRouteNavigationArrow(
            mapView: MapboxMaps.MapView,
            coords: [CLLocationCoordinate2D],
            user: CLLocation,
            quantumAccent: Bool
        ) {
            guard let arrowMgr = routeArrowManager else { return }
            guard coords.count >= 2 else {
                arrowMgr.annotations = []
                return
            }

            let now = Date()
            if let prev = lastRouteArrowUserLoc {
                let dt = now.timeIntervalSince(lastRouteArrowUpdateAt)
                if dt < 0.08 && user.distance(from: prev) < 1.5 { return }
            }
            lastRouteArrowUserLoc = user
            lastRouteArrowUpdateAt = now

            guard let snap = PolylineLeadArrow.snappedPosition(
                coords: coords,
                user: user,
                anchorIndex: &lastLeadArrowPolyIndex
            ) else {
                arrowMgr.annotations = []
                return
            }

            let alpha = 0.42
            if let prev = smoothedRouteCoord {
                smoothedRouteCoord = lerpCoordinate(prev, snap.coordinate, alpha: alpha)
                smoothedRouteBearing = lerpAngle(smoothedRouteBearing, snap.bearingDegrees, alpha: alpha)
            } else {
                smoothedRouteCoord = snap.coordinate
                smoothedRouteBearing = snap.bearingDegrees
            }

            guard let display = smoothedRouteCoord else { return }

            let img = HorizonMapboxPinImages.routeDirectionArrowImage(quantumAccent: quantumAccent)
            var ann = PointAnnotation(id: "horizon-route-nav-arrow", coordinate: display)
            ann.image = img
            ann.iconAnchor = .center
            ann.iconRotate = smoothedRouteBearing
            ann.iconSize = 1.55
            ann.symbolSortKey = 20
            arrowMgr.annotations = [ann]

            // Camera follow is handled by FollowPuck viewport during navigation.
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

        func refreshPoints(mapView: MapboxMaps.MapView, truckStops: [TruckStopItem], alerts: [MapAlert]) {
            guard let stopsMgr = truckStopManager, let alertMgr = alertManager else { return }

            var stopAnnotations: [PointAnnotation] = []
            stopAnnotations.reserveCapacity(truckStops.count)
            for stop in truckStops {
                var ann = PointAnnotation(id: stop.id.uuidString, coordinate: stop.coordinate)
                ann.iconAnchor = .center
                if let img = HorizonMapboxPinImages.truckStopImage(for: stop) {
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

            var alertAnns: [PointAnnotation] = []
            alertAnns.reserveCapacity(alerts.count)
            for alert in alerts {
                var ann = PointAnnotation(id: alert.id.uuidString, coordinate: alert.coordinate)
                ann.iconAnchor = .center
                if let img = HorizonMapboxPinImages.alertImage(for: alert) {
                    ann.image = img
                }
                alertAnns.append(ann)
            }
            alertMgr.annotations = alertAnns
        }
    }
}

// MARK: - Raster images for point annotations

private enum HorizonMapboxPinImages {
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

    /// Red cab + white trailer puck (competitor-style); replaces default blue dot.
    static func userTruckPuckImage() -> UIImage {
        let size = CGSize(width: 44, height: 44)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            c.setFillColor(UIColor.white.cgColor)
            c.fill(CGRect(x: 8, y: 14, width: 18, height: 14))
            c.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
            c.setLineWidth(1)
            c.stroke(CGRect(x: 8, y: 14, width: 18, height: 14))
            c.setFillColor(UIColor(red: 0.86, green: 0.15, blue: 0.12, alpha: 1).cgColor)
            c.fill(CGRect(x: 24, y: 16, width: 14, height: 12))
            c.setShadow(offset: .zero, blur: 0, color: nil)
        }
    }

    /// Fully transparent — hides puck while navigating (lead arrow on route is enough).
    static func invisiblePuckImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    }
}

#endif
