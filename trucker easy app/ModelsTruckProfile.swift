//
//  TruckProfile.swift
//  trucker easy app
//
//  Created by AI Assistant on 4/1/26.
//
//  Core TruckProfile definition - centralized to avoid duplications

import Foundation

// MARK: - TruckProfile

struct TruckProfile: Codable, Equatable {
    var heightMeters: Double
    var weightTonnes: Double
    var lengthMeters: Double
    var widthMeters: Double = 2.59   // 8'6" standard semi width; wider loads need a permit
    var axleWeightTonnes: Double
    var hasHazmat: Bool
    var truckType: TruckType
    /// Eficiência real de combustível em milhas por galão (MPG). Usado na rota inteligente para
    /// calcular custo de diesel da viagem e economia com paradas mais baratas.
    /// Padrões realistas DOE/EIA 2024: semi = 6.5 MPG, straight = 10.5 MPG.
    var fuelEfficiencyMPG: Double = 6.5
    
    // MARK: - Predefined Profiles
    
    /// Standard 53' semi truck with common dimensions
    static let semiFiftyThree = TruckProfile(
        heightMeters: 4.11,      // 13'6"
        weightTonnes: 36.287,    // 80,000 lbs
        lengthMeters: 16.76,     // 55' (tractor + trailer)
        axleWeightTonnes: 9.072, // ~20,000 lbs per axle
        hasHazmat: false,
        truckType: .semi
    )
    
    /// Standard 48' semi truck
    static let semiFortyEight = TruckProfile(
        heightMeters: 4.11,
        weightTonnes: 36.287,
        lengthMeters: 15.24,     // 50'
        axleWeightTonnes: 9.072,
        hasHazmat: false,
        truckType: .semi
    )
    
    /// Straight truck (box truck)
    static let straightTruck = TruckProfile(
        heightMeters: 3.96,       // 13'
        weightTonnes: 11.793,     // 26,000 lbs
        lengthMeters: 7.92,       // 26'
        axleWeightTonnes: 5.897,
        hasHazmat: false,
        truckType: .straight,
        fuelEfficiencyMPG: 10.5   // DOE/EIA 2024 médio para straight truck / box truck
    )
    
    /// Tanker truck
    static let tanker = TruckProfile(
        heightMeters: 4.11,
        weightTonnes: 36.287,
        lengthMeters: 16.76,
        axleWeightTonnes: 9.072,
        hasHazmat: false,  // Set true if carrying hazmat
        truckType: .tanker
    )
    
    /// Flatbed truck
    static let flatbed = TruckProfile(
        heightMeters: 2.59,      // 8'6" (lower because no box)
        weightTonnes: 36.287,
        lengthMeters: 16.76,
        axleWeightTonnes: 9.072,
        hasHazmat: false,
        truckType: .flatbed
    )
    
    /// Refrigerated truck
    static let refrigerated = TruckProfile(
        heightMeters: 4.11,
        weightTonnes: 36.287,
        lengthMeters: 16.15,     // 53' (common reefer length)
        axleWeightTonnes: 9.072,
        hasHazmat: false,
        truckType: .refrigerated
    )
    
    /// Oversized load (requires permits)
    static let oversized = TruckProfile(
        heightMeters: 4.57,      // 15' (over standard)
        weightTonnes: 45.359,    // 100,000 lbs (over standard)
        lengthMeters: 18.29,     // 60'
        axleWeightTonnes: 11.34,
        hasHazmat: false,
        truckType: .semi
    )

    /// Default profile — standard 53' semi (most common US configuration)
    static let `default` = semiFiftyThree
}

// MARK: - Backward-compatible decoding
//
// `widthMeters` was added after profiles were already persisted. A profile saved
// without the key must still decode (keeping the driver's other dimensions) instead
// of failing and resetting to `.default`. Encoding stays synthesized over these keys.

extension TruckProfile {
    private enum CodingKeys: String, CodingKey {
        case heightMeters, weightTonnes, lengthMeters, widthMeters, axleWeightTonnes, hasHazmat, truckType, fuelEfficiencyMPG
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heightMeters       = try c.decode(Double.self, forKey: .heightMeters)
        weightTonnes       = try c.decode(Double.self, forKey: .weightTonnes)
        lengthMeters       = try c.decode(Double.self, forKey: .lengthMeters)
        widthMeters        = try c.decodeIfPresent(Double.self, forKey: .widthMeters) ?? 2.59
        axleWeightTonnes   = try c.decode(Double.self, forKey: .axleWeightTonnes)
        hasHazmat          = try c.decode(Bool.self, forKey: .hasHazmat)
        truckType          = try c.decode(TruckType.self, forKey: .truckType)
        // MPG adicionado depois — fallback por tipo de caminhão (DOE/EIA 2024)
        if let saved = try c.decodeIfPresent(Double.self, forKey: .fuelEfficiencyMPG), saved > 0 {
            fuelEfficiencyMPG = saved
        } else {
            switch truckType {
            case .straight: fuelEfficiencyMPG = 10.5
            default:        fuelEfficiencyMPG = 6.5
            }
        }
    }
}

// MARK: - TruckType

enum TruckType: String, Codable, CaseIterable {
    case semi = "Semi Trailer"
    case straight = "Straight Truck"
    case tanker = "Tanker"
    case flatbed = "Flatbed"
    case refrigerated = "Refrigerated"
}

// MARK: - Truck Specifications (for restriction checking)

struct TruckSpecifications: Sendable {
    var grossWeightKg: Int = 36000
    var weightPerAxleKg: Int = 9000
    var heightCm: Int = 400
    var widthCm: Int = 260
    var lengthCm: Int = 1650
    var axleCount: Int = 5
    var trailerCount: Int = 1
    var tunnelCategory: String = "B"
    var hazardousMaterials: [String] = []

    nonisolated static let `default` = TruckSpecifications()

    nonisolated static let dayCab = TruckSpecifications(
        grossWeightKg: 36000,
        heightCm: 380,
        lengthCm: 1400
    )

    nonisolated static let sleeper = TruckSpecifications(
        grossWeightKg: 36000,
        heightCm: 400,
        lengthCm: 1800
    )
}

// MARK: - TruckProfile Persistence

extension TruckProfile {
    private static let userDefaultsKey = "savedTruckProfile_v1"

    /// Load previously saved profile from UserDefaults (falls back to .default)
    static func loadSaved() -> TruckProfile {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let profile = try? JSONDecoder().decode(TruckProfile.self, from: data)
        else { return .default }
        return profile
    }

    /// Persist this profile to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: TruckProfile.userDefaultsKey)
        }
    }
}
