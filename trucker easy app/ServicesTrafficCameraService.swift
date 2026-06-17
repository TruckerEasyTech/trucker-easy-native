//
//  ServicesTrafficCameraService.swift
//  Câmeras de trânsito 511 (dado REAL de governo) próximas do motorista/rota.
//
//  Fonte: tabela `traffic_cameras` no Supabase (populada pelo cron sync_traffic_cameras.py).
//  Busca só as do corredor via RPC `traffic_cameras_near`. A imagem é uma URL AO VIVO do DOT —
//  nada fabricado: sem câmera real na área, a lista fica vazia.
//

import Foundation
import CoreLocation
import Observation

struct TrafficCamera: Identifiable, Decodable, Equatable {
    let id: String
    let source: String
    let name: String?
    let roadway: String?
    let direction: String?
    let latitude: Double
    let longitude: Double
    let imageURL: String
    let videoURL: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Rótulo curto pro pin/sheet (rodovia + direção quando houver).
    var label: String {
        let parts = [roadway, direction].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return name ?? "Camera"
    }

    enum CodingKeys: String, CodingKey {
        case id, source, name, roadway, direction, latitude, longitude
        case imageURL = "image_url"
        case videoURL = "video_url"
    }
}

@MainActor
@Observable
final class TrafficCameraService {
    static let shared = TrafficCameraService()

    private(set) var cameras: [TrafficCamera] = []
    private(set) var lastError: String?

    private var lastFetchDate: Date = .distantPast
    private var lastFetchCoordinate: CLLocationCoordinate2D?
    private let refreshInterval: TimeInterval = 300       // câmeras mudam de local raramente
    private let refreshDistanceMeters: Double = 15_000

    private init() {}

    private struct NearParams: Encodable {
        let p_lat: Double
        let p_lon: Double
        let p_radius_km: Double
        let p_limit: Int
    }

    func refreshIfNeeded(near location: CLLocation, radiusKm: Double = 25) async {
        let now = Date()
        if now.timeIntervalSince(lastFetchDate) < refreshInterval, let prev = lastFetchCoordinate {
            let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            if location.distance(from: prevLoc) < refreshDistanceMeters { return }
        }
        do {
            let result: [TrafficCamera] = try await SupabaseClient.shared.rpc(
                "traffic_cameras_near",
                params: NearParams(p_lat: location.coordinate.latitude,
                                   p_lon: location.coordinate.longitude,
                                   p_radius_km: radiusKm, p_limit: 60)
            )
            cameras = result
            lastError = nil
            lastFetchDate = now
            lastFetchCoordinate = location.coordinate
        } catch {
            // Sem dado real disponível → mantém o que tinha; NUNCA inventa câmera.
            lastError = error.localizedDescription
            #if DEBUG
            print("[TrafficCamera] fetch falhou: \(error.localizedDescription)")
            #endif
        }
    }

    func clear() { cameras = [] }
}
