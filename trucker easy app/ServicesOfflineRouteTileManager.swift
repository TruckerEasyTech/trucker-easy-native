//  ServicesOfflineRouteTileManager.swift
//  Tiles offline da rota ativa (C3 — híbrido).
//
//  Estratégia para viagens longas (coast-to-coast) sem estourar disco/tempo:
//   • VISÃO GERAL  — rota inteira em zoom baixo (orientação na viagem longa).
//   • JANELA À FRENTE — ~80 km adiante em zoom de navegação, ROLANDO com o motorista
//     (cobre a zona morta do trecho imediato).
//
//  Mapbox Maps v11: OfflineManager + TileStore + TileRegion (geometria = linha da rota).

#if canImport(MapboxMaps)
import Foundation
import CoreLocation
import MapboxMaps

final class OfflineRouteTileManager {
    static let shared = OfflineRouteTileManager()

    private let offlineManager = OfflineManager()
    private let tileStore = TileStore.default

    private let overviewRegionId = "te-route-overview"
    private let aheadRegionId = "te-route-ahead"
    private let overviewZoom: ClosedRange<UInt8> = 0...10   // rota inteira, leve
    private let aheadZoom: ClosedRange<UInt8> = 11...14      // trecho à frente, detalhado
    private let aheadDistanceMeters: CLLocationDistance = 80_000
    private let refreshAfterMovedMeters: CLLocationDistance = 40_000

    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var styleURI: StyleURI = .standard
    private var lastWindowAnchor: CLLocationCoordinate2D?

    private init() {}

    /// Chamar ao APLICAR uma nova rota: baixa a visão geral + a primeira janela à frente.
    func cacheRoute(coordinates: [CLLocationCoordinate2D], style: StyleURI) {
        guard coordinates.count >= 2 else { return }
        routeCoordinates = coordinates
        styleURI = style
        lastWindowAnchor = nil

        loadStylePack(style)
        loadRegion(id: overviewRegionId, coordinates: coordinates, zoom: overviewZoom)
        refreshAheadWindow(from: coordinates[0])
    }

    /// Chamar nas atualizações de localização durante a navegação: rola a janela à frente.
    /// Throttle interno — só rebaixa após andar `refreshAfterMovedMeters`.
    func refreshAheadWindow(from coordinate: CLLocationCoordinate2D) {
        guard routeCoordinates.count >= 2 else { return }
        if let anchor = lastWindowAnchor {
            let moved = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if moved < refreshAfterMovedMeters { return }
        }
        let window = aheadWindowCoordinates(from: coordinate)
        guard window.count >= 2 else { return }
        lastWindowAnchor = coordinate
        loadRegion(id: aheadRegionId, coordinates: window, zoom: aheadZoom)
    }

    /// Remove os tiles da rota (ex.: ao encerrar a navegação) para não acumular disco.
    func clear() {
        tileStore.removeTileRegion(forId: overviewRegionId)
        tileStore.removeTileRegion(forId: aheadRegionId)
        routeCoordinates = []
        lastWindowAnchor = nil
    }

    // MARK: - Internos

    /// Acha o ponto da rota mais próximo da posição atual e acumula ~80 km à frente.
    private func aheadWindowCoordinates(from coordinate: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var startIdx = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, c) in routeCoordinates.enumerated() {
            let d = here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < bestDist { bestDist = d; startIdx = i }
        }
        var window: [CLLocationCoordinate2D] = []
        var acc: CLLocationDistance = 0
        var prev: CLLocation?
        for i in startIdx..<routeCoordinates.count {
            let c = routeCoordinates[i]
            let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
            if let p = prev { acc += loc.distance(from: p) }
            window.append(c)
            prev = loc
            if acc >= aheadDistanceMeters { break }
        }
        return window
    }

    private func loadStylePack(_ style: StyleURI) {
        guard let options = StylePackLoadOptions(
            glyphsRasterizationMode: .ideographsRasterizedLocally,
            metadata: ["name": "te-route-style"],
            acceptExpired: true
        ) else { return }
        offlineManager.loadStylePack(for: style, loadOptions: options, progress: nil) { _ in }
    }

    private func loadRegion(id: String, coordinates: [CLLocationCoordinate2D], zoom: ClosedRange<UInt8>) {
        let descriptorOptions = TilesetDescriptorOptions(styleURI: styleURI, zoomRange: zoom, tilesets: nil)
        let descriptor = offlineManager.createTilesetDescriptor(for: descriptorOptions)
        let geometry = Geometry.lineString(LineString(coordinates))
        guard let loadOptions = TileRegionLoadOptions(
            geometry: geometry,
            descriptors: [descriptor],
            metadata: ["name": id],
            acceptExpired: true
        ) else { return }
        tileStore.loadTileRegion(forId: id, loadOptions: loadOptions) { _ in }
    }
}
#endif
