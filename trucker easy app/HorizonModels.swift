// HorizonModels.swift — Shared types for the Horizon (map) screen
// Extracted from ViewsHorizonView.swift for maintainability.

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Display Route Step

struct DisplayRouteStep: Identifiable {
    let id = UUID()
    let instructions: String
    let distance: Double  // meters
    let duration: Double  // seconds

    init(_ step: RouteStep) {
        self.instructions = step.instruction
        self.distance = step.distanceMeters
        self.duration = step.durationSeconds
    }
}

// MARK: - Map Alert

struct MapAlert: Identifiable {
    let id = UUID()
    let type: AlertType
    let coordinate: CLLocationCoordinate2D
    let timestamp = Date()
    var confirmations: Int = 1

    enum AlertType: String, CaseIterable {
        case police   = "Police"
        case accident = "Accident"
        case scale    = "Scale"
        case weather  = "Weather"
        case hazmat   = "Hazmat"
        case roadwork = "Road Work"

        var icon: String {
            switch self {
            case .police:   return "shield.fill"
            case .accident: return "car.fill"
            case .scale:    return "scalemass.fill"
            case .weather:  return "cloud.bolt.fill"
            case .hazmat:   return "exclamationmark.triangle.fill"
            case .roadwork: return "cone.fill"
            }
        }
        var color: Color {
            switch self {
            case .police:   return Color(hex: "#3b82f6")
            case .accident: return Color(hex: "#ef4444")
            case .scale:    return Color(hex: "#f59e0b")
            case .weather:  return Color(hex: "#6366f1")
            case .hazmat:   return Color(hex: "#ef4444")
            case .roadwork: return Color(hex: "#f97316")
            }
        }
    }
}

// MARK: - Nearby Category

enum NearbyCategory: String, CaseIterable {
    case fuel       = "Fuel"
    case rest       = "Rest Areas"
    case food       = "Food"
    case scale      = "Weigh Scales"
    case parking    = "Parking"
    case repair     = "Repair"
    case healthy    = "Healthy Food"
    case walmart    = "Walmart"
    case wash       = "Truck Washes"
    case weigh      = "Weigh Stations"

    var icon: String {
        switch self {
        case .fuel:     return "fuelpump.fill"
        case .rest:     return "moon.zzz.fill"
        case .food:     return "fork.knife"
        case .scale:    return "scalemass.fill"
        case .parking:  return "p.circle.fill"
        case .repair:   return "wrench.and.screwdriver.fill"
        case .healthy:  return "leaf.fill"
        case .walmart:  return "cart.fill"
        case .wash:     return "sparkles"
        case .weigh:    return "scalemass.fill"
        }
    }

    var label: String { rawValue }

    var gridLabel: String {
        switch self {
        case .fuel:     return "Fuel"
        case .rest:     return "Rest Areas"
        case .food:     return "Food"
        case .scale:    return "Weigh Scales"
        case .parking:  return "Parking"
        case .repair:   return "Repair"
        case .healthy:  return "Healthy"
        case .walmart:  return "Walmarts"
        case .wash:     return "Truck Washes"
        case .weigh:    return "Weigh\nStations"
        }
    }

    var sidebarLabel: String { sidebarLabel(for: .english) }

    func sidebarLabel(for lang: AppLanguage) -> String {
        switch self {
        case .fuel:    return lang.categoryFuel
        case .rest:    return lang.categoryRest
        case .food:    return lang.categoryFood
        case .scale:   return "Scale"
        case .parking: return lang.categoryParking
        case .repair:  return lang.categoryRepair
        case .healthy: return "Healthy"
        case .walmart: return "Walmart"
        case .wash:    return lang.categoryWash
        case .weigh:   return "Weigh"
        }
    }

    var searchQuery: String {
        switch self {
        case .fuel:     return "diesel fuel truck stop Pilot Love's TA Petro Flying J"
        case .rest:     return "rest area truck parking highway"
        case .food:     return "restaurant diner truck stop food"
        case .scale:    return "CAT Scale weigh station truck scale"
        case .parking:  return "truck parking lot overnight parking"
        case .repair:   return "truck repair tire service diesel mechanic"
        case .healthy:  return "healthy restaurant salad grill fresh food"
        case .walmart:  return "Walmart Supercenter"
        case .wash:     return "truck wash Blue Beacon"
        case .weigh:    return "weigh station DOT inspection"
        }
    }

    var color: Color {
        switch self {
        case .fuel:     return Color(hex: "#f59e0b")
        case .rest:     return Color(hex: "#6366f1")
        case .food:     return Color(hex: "#10b981")
        case .scale:    return Color(hex: "#ef4444")
        case .parking:  return Color(hex: "#00d4ff")
        case .repair:   return Color(hex: "#f97316")
        case .healthy:  return Color(hex: "#34d399")
        case .walmart:  return Color(hex: "#2563eb")
        case .wash:     return Color(hex: "#a855f7")
        case .weigh:    return Color(hex: "#ef4444")
        }
    }
}

// MARK: - Nearby Stop Item

struct NearbyStopItem: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let phone: String?
    let category: NearbyCategory

    var distanceText: String {
        if distanceMeters < 1609 {
            return String(format: "%.0f ft", distanceMeters * 3.28084)
        }
        return String(format: "%.1f mi", distanceMeters / 1609.34)
    }
}

// MARK: - Food Suggestion

struct FoodSuggestion {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let reason: String
    var useMetric: Bool = false

    var distanceText: String {
        if useMetric {
            if distanceMeters < 1000 {
                return String(format: "%.0f m", distanceMeters)
            }
            return String(format: "%.1f km", distanceMeters / 1000)
        } else {
            if distanceMeters < 1609 {
                return String(format: "%.0f ft", distanceMeters * 3.28084)
            }
            return String(format: "%.1f mi", distanceMeters / 1609.34)
        }
    }
}

// MARK: - RoundedCorner Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(HorizonRoundedCorner(radius: radius, corners: corners))
    }
}

struct HorizonRoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
