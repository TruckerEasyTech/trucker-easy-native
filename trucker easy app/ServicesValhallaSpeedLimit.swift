//  ServicesValhallaSpeedLimit.swift
//  Limite de velocidade REAL por trecho de via, via Valhalla /locate (campo edge_info.speed_limit).
//  Usado p/ trocar o limite-base genérico do aviso de velocidade (Issue 2 do teste de estrada)
//  pelo limite real da estrada onde o caminhão está.
//
//  Criado pelo Jarvis · 2026-06-15

import Foundation
import CoreLocation

extension ValhallaRoutingService {

    /// Limite de velocidade posted (km/h) da via na coordenada, via Valhalla `/locate`.
    /// Retorna nil se indisponível/desconhecido — o chamador cai no baseline da jurisdição.
    func fetchEdgeSpeedLimitKmh(at coordinate: CLLocationCoordinate2D) async -> Double? {
        guard let base = prioritizedServerBaseURLs.first,
              let url = URL(string: "\(base)/locate") else { return nil }

        let body: [String: Any] = [
            "locations": [["lat": coordinate.latitude, "lon": coordinate.longitude]],
            "costing": "truck",
            "verbose": true
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let edges = first["edges"] as? [[String: Any]] else { return nil }

        for edge in edges {
            // O speed_limit fica em edge_info; alguns builds expõem no próprio edge.
            let containers = [edge["edge_info"] as? [String: Any], edge].compactMap { $0 }
            for c in containers {
                if let sl = (c["speed_limit"] as? NSNumber)?.doubleValue, sl > 0, sl < 200 {
                    return sl   // km/h
                }
            }
        }
        return nil
    }
}
