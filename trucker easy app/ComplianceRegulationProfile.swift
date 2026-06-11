//
//  RegulationProfile.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/31/26.
//
//  Country-specific truck regulation profiles and compliance checking.
//  Validates truck specifications against regional laws for height, weight, length restrictions.

import Foundation
import MapKit
import CoreLocation

// MARK: - Regulation Profile

/// Country/region-specific truck regulations
struct RegulationProfile {
    let country: Country
    let maxHeightCm: Int        // Maximum legal height in centimeters
    let maxWeightKg: Int        // Maximum gross vehicle weight in kilograms
    let maxLengthCm: Int        // Maximum length in centimeters
    let maxRoadTrainLengthCm: Int?
    let maxWidthCm: Int         // Maximum width in centimeters
    let maxIntermodalWeightKg: Int?
    let requiresPermitAboveHeight: Int?  // Height threshold requiring special permit
    let requiresPermitAboveWeight: Int?  // Weight threshold requiring special permit
    let legalReference: String

    init(
        country: Country,
        maxHeightCm: Int,
        maxWeightKg: Int,
        maxLengthCm: Int,
        maxRoadTrainLengthCm: Int? = nil,
        maxWidthCm: Int,
        maxIntermodalWeightKg: Int? = nil,
        requiresPermitAboveHeight: Int?,
        requiresPermitAboveWeight: Int?,
        legalReference: String
    ) {
        self.country = country
        self.maxHeightCm = maxHeightCm
        self.maxWeightKg = maxWeightKg
        self.maxLengthCm = maxLengthCm
        self.maxRoadTrainLengthCm = maxRoadTrainLengthCm
        self.maxWidthCm = maxWidthCm
        self.maxIntermodalWeightKg = maxIntermodalWeightKg
        self.requiresPermitAboveHeight = requiresPermitAboveHeight
        self.requiresPermitAboveWeight = requiresPermitAboveWeight
        self.legalReference = legalReference
    }
    
    enum Country: String, CaseIterable {
        case usa = "USA"
        case canada = "CAN"
        case mexico = "MEX"
        case uk = "GBR"
        case eu = "EU"
        case germany = "DEU"
        case france = "FRA"
        case brazil = "BRA"
        case australia = "AUS"
        case generic = "GENERIC"
        
        var displayName: String {
            switch self {
            case .usa: return "United States"
            case .canada: return "Canada"
            case .mexico: return "Mexico"
            case .uk: return "United Kingdom"
            case .eu: return "European Union"
            case .germany: return "Germany"
            case .france: return "France"
            case .brazil: return "Brazil"
            case .australia: return "Australia"
            case .generic: return "International"
            }
        }
    }
    
    // MARK: - Predefined Profiles
    
    /// United States federal regulations (approximates most states)
    static let usa = RegulationProfile(
        country: .usa,
        maxHeightCm: 420,       // 13'6" (4.2m) - most states
        maxWeightKg: 36287,     // 80,000 lbs
        maxLengthCm: 1645,      // 53' trailer + tractor ≈ 54' total
        maxWidthCm: 260,        // 102" (8'6")
        requiresPermitAboveHeight: 420,
        requiresPermitAboveWeight: 36287,
        legalReference: "US Federal baseline (state-specific overrides may apply)"
    )
    
    /// Canada federal regulations
    static let canada = RegulationProfile(
        country: .canada,
        maxHeightCm: 415,       // 4.15m common limit
        maxWeightKg: 63500,     // 63.5 metric tonnes
        maxLengthCm: 2320,      // 23.2m (varies by province)
        maxWidthCm: 260,        // 2.6m
        requiresPermitAboveHeight: 415,
        requiresPermitAboveWeight: 63500,
        legalReference: "Canadian federal/provincial heavy vehicle baseline"
    )
    
    /// United Kingdom regulations
    static let uk = RegulationProfile(
        country: .uk,
        maxHeightCm: 490,       // 4.9m (16 feet)
        maxWeightKg: 44000,     // 44 tonnes
        maxLengthCm: 1850,      // 18.5m for articulated vehicles
        maxWidthCm: 255,        // 2.55m
        requiresPermitAboveHeight: 490,
        requiresPermitAboveWeight: 44000,
        legalReference: "UK domestic heavy vehicle limits"
    )

    /// EU baseline for international traffic (Directive 96/53/EC + amendments)
    static let eu = RegulationProfile(
        country: .eu,
        maxHeightCm: 400,         // 4.00m
        maxWeightKg: 40000,       // 40t
        maxLengthCm: 1650,        // 16.50m articulated
        maxRoadTrainLengthCm: 1875, // 18.75m road train
        maxWidthCm: 255,          // 2.55m
        maxIntermodalWeightKg: 44000, // 44t intermodal operations
        requiresPermitAboveHeight: 400,
        requiresPermitAboveWeight: 40000,
        legalReference: "EU Directive 96/53/EC (incl. 2015/719 amendments)"
    )
    
    /// Germany regulations
    static let germany = RegulationProfile(
        country: .germany,
        maxHeightCm: 400,       // 4.0m
        maxWeightKg: 40000,     // 40 tonnes (can be 44t with permit)
        maxLengthCm: 1850,      // 18.5m
        maxWidthCm: 255,        // 2.55m
        requiresPermitAboveHeight: 400,
        requiresPermitAboveWeight: 40000,
        legalReference: "Germany + EU heavy goods framework"
    )
    
    /// France regulations
    static let france = RegulationProfile(
        country: .france,
        maxHeightCm: 400,       // 4.0m
        maxWeightKg: 44000,     // 44 tonnes
        maxLengthCm: 1850,      // 18.5m
        maxWidthCm: 255,        // 2.55m
        requiresPermitAboveHeight: 400,
        requiresPermitAboveWeight: 44000,
        legalReference: "France + EU heavy goods framework"
    )
    
    /// Brazil regulations
    static let brazil = RegulationProfile(
        country: .brazil,
        maxHeightCm: 440,       // 4.40m (Contran 882/2021 baseline)
        maxWeightKg: 58500,     // Common articulated PBTC baseline; configuration-dependent above this
        maxLengthCm: 1860,      // 18.60m (tractor + semitrailer baseline)
        maxRoadTrainLengthCm: 1980, // 19.80m for selected combinations without special regime
        maxWidthCm: 260,        // 2.6m
        requiresPermitAboveHeight: 440,
        requiresPermitAboveWeight: 58500,
        legalReference: "Brazil CONTRAN Resolution 882/2021 (AET required above baseline classes)"
    )

    /// Mexico federal corridors (approximate baseline)
    static let mexico = RegulationProfile(
        country: .mexico,
        maxHeightCm: 425,       // ~4.25m
        maxWeightKg: 66000,     // Depends on axle config/corridor
        maxLengthCm: 3150,      // Double trailers allowed on authorized routes
        maxWidthCm: 260,
        requiresPermitAboveHeight: 425,
        requiresPermitAboveWeight: 66000,
        legalReference: "Mexico federal corridor rules (configuration and corridor dependent)"
    )

    /// Australia heavy vehicle baseline (national network approximation)
    static let australia = RegulationProfile(
        country: .australia,
        maxHeightCm: 430,       // 4.3m
        maxWeightKg: 42500,     // Varies by class/network
        maxLengthCm: 2650,      // Typical articulated combinations vary by permit
        maxWidthCm: 250,        // 2.5m standard
        requiresPermitAboveHeight: 430,
        requiresPermitAboveWeight: 42500,
        legalReference: "Australia NHVR baseline (state/network class variations apply)"
    )
    
    /// Generic/International fallback
    static let generic = RegulationProfile(
        country: .generic,
        maxHeightCm: 400,       // Conservative 4.0m
        maxWeightKg: 40000,     // Conservative 40 tonnes
        maxLengthCm: 1850,      // Conservative 18.5m
        maxWidthCm: 255,        // Conservative 2.55m
        requiresPermitAboveHeight: 400,
        requiresPermitAboveWeight: 40000,
        legalReference: "Generic conservative fallback profile"
    )
    
    // MARK: - Factory Method
    
    /// Returns regulation profile for a given country code (ISO 3166-1 alpha-3)
    static func profile(for country: Country) -> RegulationProfile {
        switch country {
        case .usa: return .usa
        case .canada: return .canada
        case .uk: return .uk
        case .eu: return .eu
        case .germany: return .germany
        case .france: return .france
        case .brazil: return .brazil
        case .mexico: return .mexico
        case .australia: return .australia
        case .generic: return .generic
        }
    }
    
    /// Detect regulation profile from coordinate (basic reverse geocoding)
    static func profile(for coordinate: CLLocationCoordinate2D) async -> RegulationProfile {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return .generic }
            return await withCheckedContinuation { continuation in
                request.getMapItems { items, _ in
                    if let code = items?.first?.addressRepresentations?.region?.identifier {
                        continuation.resume(returning: profile(forISOCode: code.uppercased()))
                    } else {
                        continuation.resume(returning: .generic)
                    }
                }
            }
        } else {
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                if let countryCode = placemarks.first?.isoCountryCode?.uppercased() {
                    return profile(forISOCode: countryCode)
                }
            } catch {
                #if DEBUG
                print("[RegulationProfile] ⚠️ Geocoding failed: \(error.localizedDescription)")
                #endif
            }
        }

        return .generic
    }
    
    /// Maps ISO 3166-1 alpha-2 or alpha-3 country codes to profiles
    static func profile(forISOCode code: String) -> RegulationProfile {
        let normalized = code.uppercased()
        
        switch normalized {
        case "US", "USA":
            return .usa
        case "CA", "CAN":
            return .canada
        case "GB", "GBR", "UK":
            return .uk
        // EU-27 + EEA (IS, NO) + CH + candidate / neighbourhood states often crossed in road freight
        case "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "ES", "FI", "GR",
             "HR", "HU", "IE", "IT", "LT", "LU", "LV", "MT", "NL", "PL",
             "PT", "RO", "SE", "SI", "SK", "IS", "NO", "LI", "CH",
             "AD", "MC", "SM", "VA",
             "BA", "RS", "ME", "MK", "AL", "MD", "UA", "XK":
            return .eu
        case "DE", "DEU":
            return .germany
        case "FR", "FRA":
            return .france
        case "BR", "BRA":
            return .brazil
        case "MX", "MEX":
            return .mexico
        case "AU", "AUS":
            return .australia
        // Latin America & Caribbean — conservative generic (not BR/MX-specific law)
        case "AR", "CL", "CO", "PE", "EC", "BO", "UY", "PY", "VE", "GY", "SR", "GF",
             "GT", "HN", "SV", "NI", "CR", "PA", "BZ", "CU", "DO", "HT", "JM", "TT", "BB":
            return .generic
        default:
            return .generic
        }
    }
}

// MARK: - Compliance Checker

/// Validates truck specifications against regulation profiles
struct ComplianceChecker {
    
    enum ComplianceLevel {
        case compliant          // Within legal limits
        case softViolation      // Exceeds limits but may be allowed with permit
        case hardViolation      // Illegal without special authorization
    }
    
    struct ComplianceResult {
        let level: ComplianceLevel
        let violations: [Violation]
        
        var isCompliant: Bool { level == .compliant }
        var hasSoftViolations: Bool { violations.contains { $0.severity == .soft } }
        var hasHardViolations: Bool { violations.contains { $0.severity == .hard } }
        
        struct Violation {
            let type: ViolationType
            let severity: Severity
            let message: String
            let current: Int
            let limit: Int
            
            enum ViolationType {
                case height
                case weight
                case length
                case width
            }
            
            enum Severity {
                case soft   // May be permitted with authorization
                case hard   // Illegal/requires rerouting
            }
        }
    }
    
    /// Check truck specifications against regulation profile (violation copy follows driver language).
    static func check(
        specs: TruckSpecifications,
        against regulations: RegulationProfile,
        language: AppLanguage
    ) -> ComplianceResult {
        var violations: [ComplianceResult.Violation] = []

        // Height check
        if specs.heightCm > regulations.maxHeightCm {
            let severity: ComplianceResult.Violation.Severity
            if let permitThreshold = regulations.requiresPermitAboveHeight,
               specs.heightCm <= permitThreshold + 50 {  // 50cm grace for permits
                severity = .soft
            } else {
                severity = .hard
            }

            violations.append(.init(
                type: .height,
                severity: severity,
                message: localizedViolationMessage(
                    type: .height,
                    current: specs.heightCm,
                    limit: regulations.maxHeightCm,
                    language: language
                ),
                current: specs.heightCm,
                limit: regulations.maxHeightCm
            ))
        }

        // Weight check
        if specs.grossWeightKg > regulations.maxWeightKg {
            let severity: ComplianceResult.Violation.Severity
            if let permitThreshold = regulations.requiresPermitAboveWeight,
               specs.grossWeightKg <= permitThreshold + 5000 {  // 5,000kg grace for permits
                severity = .soft
            } else {
                severity = .hard
            }

            violations.append(.init(
                type: .weight,
                severity: severity,
                message: localizedViolationMessage(
                    type: .weight,
                    current: specs.grossWeightKg,
                    limit: regulations.maxWeightKg,
                    language: language
                ),
                current: specs.grossWeightKg,
                limit: regulations.maxWeightKg
            ))
        }

        // Length check
        if specs.lengthCm > regulations.maxLengthCm {
            violations.append(.init(
                type: .length,
                severity: .soft,  // Length usually has more flexibility
                message: localizedViolationMessage(
                    type: .length,
                    current: specs.lengthCm,
                    limit: regulations.maxLengthCm,
                    language: language
                ),
                current: specs.lengthCm,
                limit: regulations.maxLengthCm
            ))
        }

        // Width check
        if specs.widthCm > regulations.maxWidthCm {
            violations.append(.init(
                type: .width,
                severity: .hard,  // Width is usually strict
                message: localizedViolationMessage(
                    type: .width,
                    current: specs.widthCm,
                    limit: regulations.maxWidthCm,
                    language: language
                ),
                current: specs.widthCm,
                limit: regulations.maxWidthCm
            ))
        }
        
        // Determine overall compliance level
        let level: ComplianceLevel
        if violations.isEmpty {
            level = .compliant
        } else if violations.allSatisfy({ $0.severity == .soft }) {
            level = .softViolation
        } else {
            level = .hardViolation
        }
        
        return ComplianceResult(level: level, violations: violations)
    }

    private static func localizedViolationMessage(
        type: ComplianceResult.Violation.ViolationType,
        current: Int,
        limit: Int,
        language: AppLanguage
    ) -> String {
        switch type {
        case .height:
            switch language {
            case .english, .hindi, .arabic:
                return "Height \(current) cm exceeds the legal limit of \(limit) cm"
            case .portuguese:
                return "Altura \(current) cm acima do limite legal de \(limit) cm"
            case .spanish, .spanishLatam:
                return "Altura \(current) cm supera el límite legal de \(limit) cm"
            case .french:
                return "Hauteur \(current) cm au-dessus de la limite légale de \(limit) cm"
            case .german:
                return "Höhe \(current) cm über dem gesetzlichen Limit von \(limit) cm"
            case .polish:
                return "Wysokość \(current) cm przekracza limit prawny \(limit) cm"
            case .russian:
                return "Высота \(current) см превышает законный предел \(limit) см"
            }
        case .weight:
            switch language {
            case .english, .hindi, .arabic:
                return "Weight \(current) kg exceeds the legal limit of \(limit) kg"
            case .portuguese:
                return "Peso \(current) kg acima do limite legal de \(limit) kg"
            case .spanish, .spanishLatam:
                return "Peso \(current) kg supera el límite legal de \(limit) kg"
            case .french:
                return "Masse \(current) kg au-dessus de la limite légale de \(limit) kg"
            case .german:
                return "Gewicht \(current) kg über dem gesetzlichen Limit von \(limit) kg"
            case .polish:
                return "Masa \(current) kg przekracza limit prawny \(limit) kg"
            case .russian:
                return "Масса \(current) кг превышает законный предел \(limit) кг"
            }
        case .length:
            switch language {
            case .english, .hindi, .arabic:
                return "Length \(current) cm exceeds the legal limit of \(limit) cm"
            case .portuguese:
                return "Comprimento \(current) cm acima do limite legal de \(limit) cm"
            case .spanish, .spanishLatam:
                return "Longitud \(current) cm supera el límite legal de \(limit) cm"
            case .french:
                return "Longueur \(current) cm au-dessus de la limite légale de \(limit) cm"
            case .german:
                return "Länge \(current) cm über dem gesetzlichen Limit von \(limit) cm"
            case .polish:
                return "Długość \(current) cm przekracza limit prawny \(limit) cm"
            case .russian:
                return "Длина \(current) см превышает законный предел \(limit) см"
            }
        case .width:
            switch language {
            case .english, .hindi, .arabic:
                return "Width \(current) cm exceeds the legal limit of \(limit) cm"
            case .portuguese:
                return "Largura \(current) cm acima do limite legal de \(limit) cm"
            case .spanish, .spanishLatam:
                return "Anchura \(current) cm supera el límite legal de \(limit) cm"
            case .french:
                return "Largeur \(current) cm au-dessus de la limite légale de \(limit) cm"
            case .german:
                return "Breite \(current) cm über dem gesetzlichen Limit von \(limit) cm"
            case .polish:
                return "Szerokość \(current) cm przekracza limit prawny \(limit) cm"
            case .russian:
                return "Ширина \(current) см превышает законный предел \(limit) см"
            }
        }
    }
}

// MARK: - Localized country labels (driver UI language)

extension RegulationProfile.Country {
    /// Human-readable country/region for the active app language (`RegionalSettingsManager` / `selectedLanguage`).
    func displayName(for lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.usa, .portuguese): return "Estados Unidos"
        case (.usa, .spanish), (.usa, .spanishLatam): return "Estados Unidos"
        case (.usa, .french): return "États-Unis"
        case (.usa, .german): return "Vereinigte Staaten"
        case (.usa, .polish): return "Stany Zjednoczone"
        case (.usa, .russian): return "США"
        case (.canada, .portuguese): return "Canadá"
        case (.canada, .spanish), (.canada, .spanishLatam): return "Canadá"
        case (.canada, .french): return "Canada"
        case (.mexico, .portuguese): return "México"
        case (.mexico, .spanish), (.mexico, .spanishLatam): return "México"
        case (.brazil, .english): return "Brazil"
        case (.brazil, .spanish), (.brazil, .spanishLatam): return "Brasil"
        case (.brazil, .french): return "Brésil"
        case (.brazil, .german): return "Brasilien"
        case (.uk, .portuguese): return "Reino Unido"
        case (.uk, .spanish), (.uk, .spanishLatam): return "Reino Unido"
        case (.uk, .french): return "Royaume-Uni"
        case (.uk, .german): return "Vereinigtes Königreich"
        case (.eu, .portuguese): return "União Europeia"
        case (.eu, .spanish), (.eu, .spanishLatam): return "Unión Europea"
        case (.eu, .french): return "Union européenne"
        case (.eu, .german): return "Europäische Union"
        case (.germany, .portuguese): return "Alemanha"
        case (.germany, .spanish), (.germany, .spanishLatam): return "Alemania"
        case (.germany, .french): return "Allemagne"
        case (.france, .portuguese): return "França"
        case (.france, .spanish), (.france, .spanishLatam): return "Francia"
        case (.france, .german): return "Frankreich"
        case (.australia, .portuguese): return "Austrália"
        case (.australia, .spanish), (.australia, .spanishLatam): return "Australia"
        case (.generic, .portuguese): return "Internacional"
        case (.generic, .spanish), (.generic, .spanishLatam): return "Internacional"
        case (.generic, .french): return "International"
        case (.generic, .german): return "International"
        default:
            return displayName
        }
    }
}
