import SwiftUI
import MapKit
import CoreLocation


// MARK: - HorizonMapSurface
//
// Uses UIViewRepresentable wrapping MKMapView for complete, reliable camera control.
//
// Why UIViewRepresentable instead of SwiftUI Map:
// • SwiftUI Map's position binding resets followsUserLocation whenever SwiftUI
//   re-evaluates the view (on any state change). This causes the polyline and
//   the arrow to appear to vanish because the camera drifts away.
// • MKMapView.userTrackingMode = .followWithHeading is a UIKit-level latch —
//   it stays engaged through GPS updates, heading ticks, and state redraws.
//   It can only be broken by an explicit user pan, and we re-engage it automatically.
// • Route polylines are MKPolylineRenderer overlays — they persist independently
//   of camera movement and never flicker or disappear.
// • The driver arrow uses the built-in MKUserLocation annotation with a custom
//   MKAnnotationView tinted gold — rendered by MapKit at 60fps with smooth interpolation.

// MARK: - MapControlActions
// Observable reference object held by HorizonView.
// HorizonMapSurface stores a weak mapView reference inside it so
// zoom/recenter calls always reach the live MKMapView instance.
@Observable
final class MapControlActions {
    weak var mapView: MKMapView?

    func zoomIn() {
        guard let map = mapView else { return }
        var region = map.region
        region.span.latitudeDelta  = max(region.span.latitudeDelta  / 2.0, 0.0005)
        region.span.longitudeDelta = max(region.span.longitudeDelta / 2.0, 0.0005)
        map.setRegion(region, animated: true)
    }

    func zoomOut() {
        guard let map = mapView else { return }
        var region = map.region
        region.span.latitudeDelta  = min(region.span.latitudeDelta  * 2.0, 180)
        region.span.longitudeDelta = min(region.span.longitudeDelta * 2.0, 180)
        map.setRegion(region, animated: true)
    }

    func recenter() {
        guard let map = mapView else { return }
        map.setUserTrackingMode(.follow, animated: true)
    }
}

struct HorizonMapSurface: UIViewRepresentable {
    var selectedMapStyle: MapStyleOption
    let locationManager: LocationManager
    let mapAlerts: [MapAlert]
    let route: MKRoute?
    var truckRoute: TruckRoute? = nil     // truck-optimized route (preferred over MKRoute)
    /// Purple accent when middleware used Neal / Leap / Braket — polyline is still road geometry from `geometryProvider`.
    var routeQuantumLineAccent: Bool = false
    var isNavigating: Bool = false
    var onStyleChange: ((MapStyleOption) -> Void)? = nil
    /// Optional: provide callbacks for zoom in/out and recenter once MKMapView is ready
    var onControlsReady: (((zoomIn: () -> Void, zoomOut: () -> Void, recenter: () -> Void)) -> Void)? = nil
    /// Shared actions object — parent creates once, this view writes mapView into it
    var mapControls: MapControlActions? = nil
    /// Nearby truck stops to show as map pins
    var truckStops: [TruckStopItem] = []
    /// Called when user taps a truck stop pin
    var onTruckStopTapped: ((TruckStopItem) -> Void)? = nil

    /// The active polyline — `TruckRoute` / `MKRoute` coordinates rendered on MapKit.
    private var activePolyline: MKPolyline? {
        truckRoute?.polyline ?? route?.polyline
    }

    // MARK: - Make the MKMapView
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.overrideUserInterfaceStyle = .light  // Force light map so it's always visible
        map.delegate = context.coordinator
        map.showsUserLocation = true
        // North-up UI + SwiftUI chrome on the edges; built-in compass/scale sit on top of our pills/buttons.
        map.showsCompass = false
        map.showsScale = false
        map.isPitchEnabled = false   // NEVER allow 3D tilt — it creates a solid-black sky above the horizon
        map.isRotateEnabled = false  // North-up always — heading shown by the navigation arrow
        map.isScrollEnabled = true
        map.isZoomEnabled = true

        // Start following the user immediately — MapKit will center on GPS fix
        // as soon as the first location arrives, without waiting for updateUIView.
        map.setUserTrackingMode(.follow, animated: false)

        // Account for SwiftUI overlays so MapKit centers the GPS arrow in the
        // VISIBLE area of the map (between the top HUD and bottom search bar).
        // Top: ~56pt for TopHUD buttons + 54pt for DOT bar = ~110pt
        // Bottom: ~120pt for the compact search bar
        map.layoutMargins = UIEdgeInsets(top: 110, left: 58, bottom: 120, right: 64)

        // Store map reference in coordinator for later use
        context.coordinator.mapView = map

        mapControls?.mapView = map

        // Expose zoom/recenter actions to parent view
        onControlsReady?((
            zoomIn: { [weak map] in
                guard let map = map else { return }
                var region = map.region
                region.span.latitudeDelta  /= 2.0
                region.span.longitudeDelta /= 2.0
                map.setRegion(region, animated: true)
            },
            zoomOut: { [weak map] in
                guard let map = map else { return }
                var region = map.region
                region.span.latitudeDelta  = min(region.span.latitudeDelta  * 2.0, 180)
                region.span.longitudeDelta = min(region.span.longitudeDelta * 2.0, 180)
                map.setRegion(region, animated: true)
            },
            recenter: { [weak map] in
                guard let map = map else { return }
                map.setUserTrackingMode(.follow, animated: true)
            }
        ))


        return map
    }

    // MARK: - Update the MKMapView when SwiftUI state changes
    func updateUIView(_ map: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.onTruckStopTapped = onTruckStopTapped

        // ── Map type ────────────────────────────────────────────────────────
        let newType = selectedMapStyle.mkMapType
        if map.mapType != newType {
            map.mapType = newType
        }

        // Lead chevron on the route replaces the user arrow while navigating.
        let shouldShowUserLocation = !isNavigating
        if map.showsUserLocation != shouldShowUserLocation {
            map.showsUserLocation = shouldShowUserLocation
        }

        if map.showsCompass { map.showsCompass = false }
        if map.showsScale { map.showsScale = false }

        // ── Layout margins — keep GPS arrow in the unobscured visible area ──
        // Navigating: step banner (~190pt top) + compact ETA bar (~90pt bottom)
        // Idle:       TopHUD (~110pt top) + compact search bar (~120pt bottom)
        // Idle: reserve leading/trailing for vertical tool column + GPS / zoom stack (matches Horizon idle chrome).
        let targetMargins: UIEdgeInsets = isNavigating
            ? UIEdgeInsets(top: 188, left: 58, bottom: 118, right: 64)
            : UIEdgeInsets(top: 110, left: 58, bottom: 120, right: 64)
        if map.layoutMargins != targetMargins {
            map.layoutMargins = targetMargins
        }

        // ── Tracking mode ────────────────────────────────────────────────────
        // ALWAYS use .follow (flat 2D, north-up). The custom arrow annotation shows
        // the GPS heading direction. .followWithHeading causes 3D tilt that exposes
        // a solid-black "sky" region above the horizon — this is the cause of the
        // dark overlay that covers the map.
        // Re-engage if the user panned away — after 3 seconds of no touch.
        if isNavigating {
            if map.userTrackingMode != .follow {
                // H6: must not capture MKMapView strongly — if the representable is torn down before
                // the delay fires, calling setUserTrackingMode on a deallocated map → EXC_BAD_ACCESS.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak map] in
                    guard let map else { return }
                    if coord.shouldReEngage {
                        map.setUserTrackingMode(.follow, animated: true)
                        coord.shouldReEngage = false
                    }
                }
                coord.shouldReEngage = true
            }
        } else {
            coord.shouldReEngage = false
            if map.userTrackingMode != .follow {
                map.setUserTrackingMode(.follow, animated: true)
            }
        }

        // ── Route polyline overlay ────────────────────────────────────────────
        // Prefer truck route polyline; fall back to MKRoute polyline.
        // Only update overlays when the active polyline identity changes.
        let newPolyline = activePolyline
        if coord.currentRoutePolyline !== newPolyline {
            // Remove old route overlays
            let oldRouteOverlays = map.overlays.filter { $0 is RouteOverlay }
            map.removeOverlays(oldRouteOverlays)
            coord.currentRoutePolyline = nil

            if let ann = coord.routeLeadAnnotation {
                map.removeAnnotation(ann)
                coord.routeLeadAnnotation = nil
            }
            coord.lastLeadArrowPolyIndex = 0

            if let polyline = newPolyline {
                coord.currentRoutePolyline = polyline
                // Casing (shadow) — drawn first so it appears below
                let casing = RouteOverlay(polyline: polyline, isCasing: true, isQuantumAccent: routeQuantumLineAccent)
                // Main route line
                let main = RouteOverlay(polyline: polyline, isCasing: false, isQuantumAccent: routeQuantumLineAccent)
                map.addOverlays([casing, main], level: .aboveRoads)
            }
        }

        // ── Alert annotations ────────────────────────────────────────────────
        let existingAlertIds = Set(coord.alertAnnotations.keys)
        let newAlertIds = Set(mapAlerts.map { $0.id })

        // Add new ones
        for alert in mapAlerts where !existingAlertIds.contains(alert.id) {
            let ann = MapAlertAnnotation(alert: alert)
            coord.alertAnnotations[alert.id] = ann
            map.addAnnotation(ann)
        }
        // Remove stale ones
        for id in existingAlertIds where !newAlertIds.contains(id) {
            if let ann = coord.alertAnnotations.removeValue(forKey: id) {
                map.removeAnnotation(ann)
            }
        }

        // ── Truck stop annotations ────────────────────────────────────────────
        let existingStopIds = Set(coord.truckStopAnnotations.keys)
        let newStopIds = Set(truckStops.map { $0.id })

        for stop in truckStops where !existingStopIds.contains(stop.id) {
            let ann = TruckStopAnnotation(stop: stop)
            coord.truckStopAnnotations[stop.id] = ann
            map.addAnnotation(ann)
        }
        for id in existingStopIds where !newStopIds.contains(id) {
            if let ann = coord.truckStopAnnotations.removeValue(forKey: id) {
                map.removeAnnotation(ann)
            }
        }

        updateRouteLeadArrow(map: map, coord: coord)
    }

    /// Single chevron on the route polyline (GPS snapped to corridor).
    private func updateRouteLeadArrow(map: MKMapView, coord: Coordinator) {
        guard isNavigating,
              let userLoc = locationManager.currentLocation,
              let poly = coord.currentRoutePolyline,
              poly.pointCount >= 2 else {
            if let ann = coord.routeLeadAnnotation {
                map.removeAnnotation(ann)
                coord.routeLeadAnnotation = nil
            }
            coord.lastLeadArrowPolyIndex = 0
            coord.lastLeadArrowUserLoc = nil
            return
        }

        let now = Date()
        if let prev = coord.lastLeadArrowUserLoc {
            let dt = now.timeIntervalSince(coord.lastLeadArrowUpdateAt)
            if dt < 0.08 && userLoc.distance(from: prev) < 1.5 { return }
        }
        coord.lastLeadArrowUserLoc = userLoc
        coord.lastLeadArrowUpdateAt = now

        guard let snap = PolylineLeadArrow.snappedPosition(
            polyline: poly,
            user: userLoc,
            anchorIndex: &coord.lastLeadArrowPolyIndex
        ) else { return }

        if coord.routeLeadAnnotation == nil {
            let ann = RouteLeadArrowAnnotation(coordinate: snap.coordinate, bearingDegrees: snap.bearingDegrees)
            coord.routeLeadAnnotation = ann
            map.addAnnotation(ann)
        } else if let ann = coord.routeLeadAnnotation {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                ann.coordinate = snap.coordinate
                ann.bearingDegrees = snap.bearingDegrees
                if let v = map.view(for: ann) {
                    v.transform = CGAffineTransform(rotationAngle: CGFloat(snap.bearingDegrees * .pi / 180))
                }
            }
        }
    }

    // MARK: - Coordinator
    func makeCoordinator() -> Coordinator {
        let c = Coordinator(onStyleChange: onStyleChange)
        c.onTruckStopTapped = onTruckStopTapped
        return c
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var onStyleChange: ((MapStyleOption) -> Void)?
        var onTruckStopTapped: ((TruckStopItem) -> Void)?
        var currentRoutePolyline: MKPolyline? = nil
        var alertAnnotations: [UUID: MapAlertAnnotation] = [:]
        var truckStopAnnotations: [UUID: TruckStopAnnotation] = [:]
        var routeLeadAnnotation: RouteLeadArrowAnnotation?
        var lastLeadArrowPolyIndex: Int = 0
        var lastLeadArrowUpdateAt: Date = .distantPast
        var lastLeadArrowUserLoc: CLLocation?
        var shouldReEngage = false
        /// Throttle arrow re-animations — didUpdate can fire very frequently; fewer blocks = less risk while MapKit recycles views.
        private var lastUserArrowRadians: CGFloat?
        let cachedArrowImage: UIImage = {
            let size: CGFloat = 60
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            return renderer.image { ctx in
                let center = CGPoint(x: size / 2, y: size / 2)
                let routeOrange = HorizonRouteColors.routeOrangeUI

                let glowRadius: CGFloat = 30
                guard let gradient = CGGradient(
                    colorsSpace: nil,
                    colors: [
                        routeOrange.withAlphaComponent(0.4).cgColor,
                        routeOrange.withAlphaComponent(0.0).cgColor
                    ] as CFArray,
                    locations: [0.0, 1.0]
                ) else { return }
                ctx.cgContext.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 15,
                    endCenter: center,
                    endRadius: glowRadius,
                    options: []
                )

                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(x: 12, y: 12, width: 36, height: 36))

                let arrowCfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
                if let arrowImg = UIImage(systemName: "arrowtriangle.up.fill", withConfiguration: arrowCfg)?
                    .withTintColor(routeOrange, renderingMode: .alwaysOriginal) {
                    let imgSize = arrowImg.size
                    let imgOrigin = CGPoint(
                        x: center.x - imgSize.width / 2,
                        y: center.y - imgSize.height / 2
                    )
                    arrowImg.draw(at: imgOrigin)
                }
            }
        }()

        /// Shared bitmap for route corridor chevron (MapKit).
        static let cachedRouteLeadChevron: UIImage = {
            let size = CGSize(width: 44, height: 50)
            let routeOrange = HorizonRouteColors.routeOrangeUI
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                c.translateBy(x: size.width / 2, y: size.height / 2)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: -18))
                path.addLine(to: CGPoint(x: 14, y: 12))
                path.addLine(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: -14, y: 12))
                path.close()
                c.setShadow(offset: CGSize(width: 0, height: 1), blur: 2.5, color: UIColor.black.withAlphaComponent(0.35).cgColor)
                c.setFillColor(routeOrange.cgColor)
                c.addPath(path.cgPath)
                c.fillPath()
                c.setShadow(offset: .zero, blur: 0, color: nil)
                c.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
                c.setLineWidth(1.1)
                c.addPath(path.cgPath)
                c.strokePath()
            }
        }()

        init(onStyleChange: ((MapStyleOption) -> Void)?) {
            self.onStyleChange = onStyleChange
        }

        private func isUserInteracting(with mapView: MKMapView) -> Bool {
            let mapGestures = mapView.gestureRecognizers ?? []
            let subviewGestures = mapView.subviews.flatMap { $0.gestureRecognizers ?? [] }
            let allGestures = mapGestures + subviewGestures
            return allGestures.contains { $0.state == .began || $0.state == .changed || $0.state == .ended }
        }

        // MARK: Polyline renderer — called once, cached by MapKit
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let routeOverlay = overlay as? RouteOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: routeOverlay.polyline)
            if routeOverlay.isCasing {
                renderer.strokeColor = UIColor.black.withAlphaComponent(0.28)
                renderer.lineWidth = 18
                renderer.lineCap = .round
                renderer.lineJoin = .round
            } else if routeOverlay.isQuantumAccent {
                renderer.strokeColor = HorizonRouteColors.quantumPurpleUI
                renderer.lineWidth = 15
                renderer.lineCap = .round
                renderer.lineJoin = .round
            } else {
                renderer.strokeColor = HorizonRouteColors.routeOrangeUI
                renderer.lineWidth = 14
                renderer.lineCap = .round
                renderer.lineJoin = .round
            }
            return renderer
        }

        // MARK: Truck stop tap
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let stopAnn = view.annotation as? TruckStopAnnotation {
                mapView.deselectAnnotation(stopAnn, animated: true)
                onTruckStopTapped?(stopAnn.stop)
            }
        }

        // MARK: Custom annotation views
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let lead = annotation as? RouteLeadArrowAnnotation {
                let id = "routeLeadChevron"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                let size: CGFloat = 44
                view.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                view.centerOffset = .zero
                view.image = Coordinator.cachedRouteLeadChevron
                let radians = CGFloat(lead.bearingDegrees * .pi / 180)
                view.transform = CGAffineTransform(rotationAngle: radians)
                return view
            }

            // Truck stop annotations
            if let stopAnn = annotation as? TruckStopAnnotation {
                let reuseId = "truckStop"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseId)
                view.annotation = annotation
                view.canShowCallout = false
                view.subviews.forEach { $0.removeFromSuperview() }

                let network = stopAnn.stop.network
                let brandColor = UIColor(network.brandColor)

                // Pin background circle
                let bg = UIView(frame: CGRect(x: 0, y: 0, width: 38, height: 38))
                bg.backgroundColor = brandColor
                bg.layer.cornerRadius = 19
                bg.layer.borderWidth = 2
                bg.layer.borderColor = UIColor.white.cgColor
                bg.layer.shadowColor = UIColor.black.cgColor
                bg.layer.shadowOpacity = 0.35
                bg.layer.shadowRadius = 3
                bg.clipsToBounds = false

                // Icon
                let iconName: String
                switch network {
                case .pilotFlyingJ:  iconName = "airplane.departure"
                case .loves:         iconName = "heart.fill"
                case .taPetro:       iconName = "car.side.fill"
                case .kwikTrip:      iconName = "bolt.fill"
                default:             iconName = "fuelpump.fill"
                }
                let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
                if let img = UIImage(systemName: iconName, withConfiguration: cfg)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let iv = UIImageView(image: img)
                    iv.frame = CGRect(x: (38 - img.size.width) / 2, y: (38 - img.size.height) / 2,
                                      width: img.size.width, height: img.size.height)
                    bg.addSubview(iv)
                }

                view.addSubview(bg)
                view.frame = bg.frame
                view.centerOffset = CGPoint(x: 0, y: -19)
                return view
            }

            // Alert annotations
            if let alertAnn = annotation as? MapAlertAnnotation {
                let id = "alert-\(alertAnn.alert.type.rawValue)"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                view.subviews.forEach { $0.removeFromSuperview() }

                let img = UIImage(systemName: alertAnn.alert.type.icon)?
                    .withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
                    .withTintColor(.white, renderingMode: .alwaysOriginal)

                let bg = UIView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
                bg.backgroundColor = UIColor(alertAnn.alert.type.color)
                bg.layer.cornerRadius = 16
                bg.clipsToBounds = true

                if let img = img {
                    let imgView = UIImageView(image: img)
                    imgView.frame = CGRect(x: 9, y: 9, width: 14, height: 14)
                    bg.addSubview(imgView)
                }
                view.addSubview(bg)
                view.frame = bg.frame
                view.layer.shadowColor = UIColor.black.cgColor
                view.layer.shadowOpacity = 0.3
                view.layer.shadowRadius = 4
                return view
            }

            // ✅ User location — CUSTOM 3D NAVIGATION ARROW
            if annotation is MKUserLocation {
                let id = "userLocation"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.canShowCallout = false
                let size: CGFloat = 60
                view.image = cachedArrowImage
                view.bounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))
                view.centerOffset = .zero
                // Never animate inside viewFor — the view can be torn down before the animation block runs (EXC_BAD_ACCESS).
                let course = mapView.userLocation.location?.course ?? -1
                let heading = course >= 0 ? course : mapView.camera.heading
                view.transform = CGAffineTransform(rotationAngle: CGFloat(heading * .pi / 180))
                return view
            }
            return nil
        }

        // MARK: Arrow rotation — called on every GPS update (not just when view is created)
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let view = mapView.view(for: userLocation) else { return }
            let course = userLocation.location?.course ?? -1
            let angle = course >= 0 ? course : mapView.camera.heading
            let radians = CGFloat(angle * .pi / 180)
            if let last = lastUserArrowRadians, abs(last - radians) < 0.04 { return }
            lastUserArrowRadians = radians
            if Thread.isMainThread {
                view.transform = CGAffineTransform(rotationAngle: radians)
            } else {
                DispatchQueue.main.async { [weak view] in
                    view?.transform = CGAffineTransform(rotationAngle: radians)
                }
            }
        }

        // MARK: Detect user panning away during navigation — schedule re-engage
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // If a user gesture caused the map to move during navigation, re-engage after delay
            if isUserInteracting(with: mapView) {
                shouldReEngage = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self, weak mapView] in
                    guard let self = self, let map = mapView else { return }
                    if self.shouldReEngage {
                        map.setUserTrackingMode(.follow, animated: true)
                        self.shouldReEngage = false
                    }
                }
            }
        }
    }
}

// MARK: - Route lead arrow (MapKit)

/// Single chevron snapped ahead on the corridor polyline during navigation.
final class RouteLeadArrowAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var bearingDegrees: CLLocationDirection = 0

    init(coordinate: CLLocationCoordinate2D, bearingDegrees: CLLocationDirection) {
        self.coordinate = coordinate
        self.bearingDegrees = bearingDegrees
    }
}

// MARK: - RouteOverlay
// Wraps MKPolyline with an isCasing flag so the renderer knows which style to apply.
final class RouteOverlay: NSObject, MKOverlay {
    let polyline: MKPolyline
    let isCasing: Bool
    let isQuantumAccent: Bool

    init(polyline: MKPolyline, isCasing: Bool, isQuantumAccent: Bool = false) {
        self.polyline = polyline
        self.isCasing = isCasing
        self.isQuantumAccent = isQuantumAccent
    }

    var coordinate: CLLocationCoordinate2D { polyline.coordinate }
    var boundingMapRect: MKMapRect { polyline.boundingMapRect }
}

// MARK: - MapAlertAnnotation
final class MapAlertAnnotation: NSObject, MKAnnotation {
    let alert: MapAlert
    var coordinate: CLLocationCoordinate2D { alert.coordinate }
    var title: String? { alert.type.rawValue }

    init(alert: MapAlert) {
        self.alert = alert
    }
}

// MARK: - TruckStopAnnotation
final class TruckStopAnnotation: NSObject, MKAnnotation {
    let stop: TruckStopItem
    var coordinate: CLLocationCoordinate2D { stop.coordinate }
    var title: String? { stop.name }

    init(stop: TruckStopItem) {
        self.stop = stop
    }
}

// MARK: - MapStyleOption MKMapType extension
extension MapStyleOption {
    var mkMapType: MKMapType {
        switch self {
        case .standard:  return .standard
        case .satellite: return .satellite        // pure aerial imagery, no labels
        case .hybrid:    return .hybrid           // aerial imagery + road/label overlay
        case .globe:     return .hybrid           // avoid flyover black-sky artifacts on device
        }
    }
}
