import SwiftUI
import MapKit

#if canImport(MapboxMaps)
import MapboxMaps
#endif

private func agentLogUniversal(
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
    DeveloperDebugLog.appendNDJSONLine(line)
}

/// A universal map view that uses Mapbox when available, and falls back to Apple MapKit otherwise.
public struct UniversalMapView: View {
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    public var userLocation: CLLocationCoordinate2D?
    public var destination: CLLocationCoordinate2D?
    public var destinationName: String?
    public var polyline: [CLLocationCoordinate2D] = []
    public var recenterTrigger: Int = 0

    public init(userLocation: CLLocationCoordinate2D? = nil,
                destination: CLLocationCoordinate2D? = nil,
                destinationName: String? = nil,
                polyline: [CLLocationCoordinate2D] = [],
                recenterTrigger: Int = 0) {
        self.userLocation = userLocation
        self.destination = destination
        self.destinationName = destinationName
        self.polyline = polyline
        self.recenterTrigger = recenterTrigger
    }

    public var body: some View {
        Map(position: $mapCameraPosition) {
            if let userLocation {
                Annotation("You", coordinate: userLocation) {
                    ZStack {
                        Circle().fill(.blue).frame(width: 20, height: 20)
                        Circle().stroke(.white, lineWidth: 3).frame(width: 20, height: 20)
                    }
                }
            }

            if let dest = destination {
                Annotation(destinationName ?? "Destination", coordinate: dest) {
                    VStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.red, .white)
                        if let name = destinationName {
                            Text(name)
                                .font(.caption)
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                        }
                    }
                }
            }

            if polyline.count >= 2 {
                MapPolyline(coordinates: polyline)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea()
        .onAppear {
            // #region agent log
            agentLogUniversal(
                runId: "baseline",
                hypothesisId: "H2",
                location: "ViewsUniversalMapView.swift:onAppear",
                message: "UniversalMapView appeared",
                data: [
                    "polylineCount": polyline.count,
                    "hasUserLocation": userLocation != nil,
                    "hasDestination": destination != nil
                ]
            )
            // #endregion
        }
        .onChange(of: polyline.count) { _, count in
            // #region agent log
            agentLogUniversal(
                runId: "baseline",
                hypothesisId: "H2",
                location: "ViewsUniversalMapView.swift:onChange(polylineCount)",
                message: "UniversalMapView polyline count changed",
                data: [
                    "polylineCount": count,
                    "hasDestination": destination != nil
                ]
            )
            // #endregion
        }
        .onChange(of: recenterTrigger) { _, _ in
            if let center = userLocation ?? destination {
                mapCameraPosition = .camera(
                    MapCamera(
                        centerCoordinate: center,
                        distance: 5000,
                        heading: 0,
                        pitch: 0
                    )
                )
            }
        }
    }
}

// MARK: - Mapbox UIKit Wrapper (MapboxMaps v10.x)

#if canImport(MapboxMaps)
fileprivate struct MapboxWrappedView: UIViewRepresentable {
    let userLocation: CLLocationCoordinate2D?
    let destination: CLLocationCoordinate2D?
    let destinationName: String?
    let polyline: [CLLocationCoordinate2D]
    let recenterTrigger: Int

    typealias UIViewType = MapboxMaps.MapView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MapboxMaps.MapView {
        let mapView = MapboxMaps.MapView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        // Initial camera
        if let center = userLocation ?? destination {
            let cam = MapboxMaps.CameraOptions(center: center, zoom: 12)
            mapView.mapboxMap.setCamera(to: cam)
        }

        // Create annotation managers
        context.coordinator.pointManager = mapView.annotations.makePointAnnotationManager()
        context.coordinator.lineManager = mapView.annotations.makePolylineAnnotationManager()

        return mapView
    }

    func updateUIView(_ mapView: MapboxMaps.MapView, context: Context) {
        // Update destination annotation
        if let dest = destination {
            var point = MapboxMaps.PointAnnotation(coordinate: dest)
            point.iconAnchor = .bottom
            context.coordinator.pointManager?.annotations = [point]
        } else {
            context.coordinator.pointManager?.annotations = []
        }

        // Update route polyline
        if polyline.count >= 2 {
            var line = MapboxMaps.PolylineAnnotation(lineCoordinates: polyline)
            line.lineColor = MapboxMaps.StyleColor(UIColor.systemBlue)
            line.lineWidth = 6.0
            context.coordinator.lineManager?.annotations = [line]
        } else {
            context.coordinator.lineManager?.annotations = []
        }

        // Recenter when trigger changes
        if context.coordinator.lastRecenterTrigger != recenterTrigger {
            context.coordinator.lastRecenterTrigger = recenterTrigger
            if let center = userLocation ?? destination {
                let cam = MapboxMaps.CameraOptions(center: center, zoom: 12)
                mapView.mapboxMap.setCamera(to: cam)
            }
        }
    }

    class Coordinator {
        var pointManager: MapboxMaps.PointAnnotationManager?
        var lineManager: MapboxMaps.PolylineAnnotationManager?
        var lastRecenterTrigger: Int = 0
    }
}
#endif

#Preview {
    UniversalMapView(
        userLocation: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        destination: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
        destinationName: "Los Angeles, CA",
        polyline: [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 36.7783, longitude: -119.4179),
            CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        ]
    )
}
