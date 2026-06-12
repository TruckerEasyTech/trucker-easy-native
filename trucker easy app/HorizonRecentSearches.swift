//
//  HorizonRecentSearches.swift
//  trucker easy app
//
//  Histórico das últimas buscas de destino do My Horizon (estilo GPS profissional):
//  ao focar a busca com o campo vazio, o motorista vê os últimos destinos e
//  re-roteia com um toque, sem digitar de novo. Persistido em UserDefaults.
//

import Foundation
import CoreLocation

struct HorizonRecentSearch: Codable, Equatable, Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double
    let at: Date

    var id: String { name }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum HorizonRecentSearchStore {
    private static let key = "horizonRecentSearches_v1"
    private static let maxCount = 8

    static func load() -> [HorizonRecentSearch] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([HorizonRecentSearch].self, from: data)
        else { return [] }
        return items
    }

    /// Registra um destino roteado com sucesso. Dedup por nome (case-insensitive),
    /// mais recente primeiro, máximo de `maxCount` itens — payload minúsculo, ok na main.
    static func record(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = load()
        items.removeAll { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        items.insert(
            HorizonRecentSearch(
                name: trimmed,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                at: Date()
            ),
            at: 0
        )
        if items.count > maxCount { items = Array(items.prefix(maxCount)) }
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
