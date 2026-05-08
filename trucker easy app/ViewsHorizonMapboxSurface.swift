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
        case .standard, .globe:
            return .streets
        case .satellite:
            return .satellite
        case .hybrid:
            return .satelliteStreets
        }
    }
}

// MARK: - Horizon Mapbox surface (MapboxMaps v11)

/// Mapbox-backed Horizon map: route polylines, truck stops, alerts, zoom/recenter, north-up, light chrome.
struct HorizonMapboxSurface: UIViewRepresentable {
    var selectedMapStyle: MapStyleOption
    let locationManager: LocationManager
    let mapAlerts: [MapAlert]
    let route: MKRoute?
    var truckRoute: TruckRoute? = nil
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
            return "tr:\(tr.coordinates.count):\(Int(tr.distanceMeters))"
        }
        if let r = route {
            return "mk:\(r.polyline.pointCount):\(Int(r.distance))"
        }
        return "none"
    }

    func makeUIView(context: Context) -> MapboxMaps.MapView {
        let initOptions = MapInitOptions(styleURI: selectedMapStyle.mapboxStyleURI)
        let mapView = MapboxMaps.MapView(frame: .zero, mapInitOptions: initOptions)
        mapView.overrideUserInterfaceStyle = .light

        var g = mapView.gestures.options
        g.pitchEnabled = false
        g.rotateEnabled = false
        mapView.gestures.options = g

        mapView.location.options.puckType = .puck2D()
        mapView.location.options.puckBearing = .course
        mapView.location.options.puckBearingEnabled = true

        context.coordinator.mapView = mapView

        context.coordinator.installManagers(on: mapView)
        context.coordinator.onTruckStopTapped = onTruckStopTapped
        context.coordinator.onStyleChange = onStyleChange
        context.coordinator.lastRouteFingerprint = routeFingerprint()
        context.coordinator.lastStyle = selectedMapStyle

        let coordinator = context.coordinator
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
                guard let map = coordinator.mapView, let c = coordinator.lastKnownCoordinate else { return }
                coordinator.resetCameraFollowThrottle()
                let z = map.mapboxMap.cameraState.zoom
                map.mapboxMap.setCamera(to: CameraOptions(center: c, zoom: z, bearing: 0, pitch: 0))
            }
        ))

        if let c = locationManager.currentLocation?.coordinate {
            mapView.mapboxMap.setCamera(to: CameraOptions(center: c, zoom: 14, bearing: 0, pitch: 0))
        }

        return mapView
    }

    func updateUIView(_ mapView: MapboxMaps.MapView, context: Context) {
        let coord = context.coordinator
        coord.onTruckStopTapped = onTruckStopTapped
        coord.onStyleChange = onStyleChange

        let targetMargins: UIEdgeInsets = isNavigating
            ? UIEdgeInsets(top: 190, left: 0, bottom: 90, right: 0)
            : UIEdgeInsets(top: 110, left: 58, bottom: 120, right: 64)
        let uiMap = mapView as UIView
        if uiMap.layoutMargins != targetMargins {
            uiMap.layoutMargins = targetMargins
        }

        if coord.lastStyle != selectedMapStyle {
            coord.lastStyle = selectedMapStyle
            mapView.mapboxMap.loadStyle(selectedMapStyle.mapboxStyleURI) { _ in
                DispatchQueue.main.async {
                    coord.installManagers(on: mapView)
                    coord.refreshRoute(mapView: mapView, coords: activeRouteCoordinates(), fingerprint: routeFingerprint())
                    coord.refreshPoints(mapView: mapView, truckStops: truckStops, alerts: mapAlerts)
                }
            }
        }

        let fp = routeFingerprint()
        if coord.lastRouteFingerprint != fp {
            coord.lastRouteFingerprint = fp
            coord.resetCameraFollowThrottle()
            coord.refreshRoute(mapView: mapView, coords: activeRouteCoordinates(), fingerprint: fp)
        }

        coord.refreshPoints(mapView: mapView, truckStops: truckStops, alerts: mapAlerts)

        if let fullLoc = locationManager.currentLocation {
            let locCoord = fullLoc.coordinate
            coord.lastKnownCoordinate = locCoord
            if coord.shouldUpdateFollowCamera(
                newLocation: fullLoc,
                isNavigating: isNavigating
            ) {
                let z = mapView.mapboxMap.cameraState.zoom
                mapView.mapboxMap.setCamera(to: CameraOptions(center: locCoord, zoom: z, bearing: 0, pitch: 0))
                #if DEBUG
                print("[HorizonMapbox] followCamera setCamera nav=\(isNavigating) acc=\(Int(fullLoc.horizontalAccuracy))m")
                #endif
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
        var lastKnownCoordinate: CLLocationCoordinate2D?

        /// Throttle follow-camera: evita `setCamera` a cada tick de GPS (causa mapa "nervoso").
        private var lastCameraUpdateAt: Date = .distantPast
        private var lastCameraCenterForDistance: CLLocation?
        private var lastIsNavigatingForCamera: Bool?

        func resetCameraFollowThrottle() {
            lastCameraCenterForDistance = nil
            lastCameraUpdateAt = .distantPast
            lastIsNavigatingForCamera = nil
        }

        func shouldUpdateFollowCamera(newLocation: CLLocation, isNavigating: Bool) -> Bool {
            if lastIsNavigatingForCamera != isNavigating {
                lastIsNavigatingForCamera = isNavigating
                lastCameraCenterForDistance = newLocation
                lastCameraUpdateAt = Date()
                return true
            }
            guard let prev = lastCameraCenterForDistance else {
                lastCameraCenterForDistance = newLocation
                lastCameraUpdateAt = Date()
                return true
            }
            let dist = newLocation.distance(from: prev)
            let dt = Date().timeIntervalSince(lastCameraUpdateAt)
            let minDist = isNavigating ? 12.0 : 32.0
            let minInterval = isNavigating ? 1.6 : 3.2
            if dist >= minDist || dt >= minInterval {
                lastCameraCenterForDistance = newLocation
                lastCameraUpdateAt = Date()
                return true
            }
            return false
        }

        private var routeLineManager: PolylineAnnotationManager?
        private var truckStopManager: PointAnnotationManager?
        private var alertManager: PointAnnotationManager?

        func installManagers(on mapView: MapboxMaps.MapView) {
            routeLineManager = mapView.annotations.makePolylineAnnotationManager(id: "horizon-route")
            truckStopManager = mapView.annotations.makePointAnnotationManager(id: "horizon-stops")
            alertManager = mapView.annotations.makePointAnnotationManager(id: "horizon-alerts")
        }

        func refreshRoute(mapView: MapboxMaps.MapView, coords: [CLLocationCoordinate2D]?, fingerprint _: String) {
            guard let mgr = routeLineManager else { return }
            guard let coords, coords.count >= 2 else {
                mgr.annotations = []
                return
            }
            var casing = PolylineAnnotation(lineCoordinates: coords)
            casing.lineColor = StyleColor(UIColor.black.withAlphaComponent(0.25))
            casing.lineWidth = 12
            casing.lineJoin = LineJoin.round
            casing.lineSortKey = 0

            var main = PolylineAnnotation(lineCoordinates: coords)
            main.lineColor = StyleColor(UIColor(red: 0, green: 0.83, blue: 0.78, alpha: 1))
            main.lineWidth = 8
            main.lineJoin = LineJoin.round
            main.lineSortKey = 1

            mgr.annotations = [casing, main]
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
}

#endif
