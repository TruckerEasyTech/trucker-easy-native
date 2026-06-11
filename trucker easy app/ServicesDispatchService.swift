import Foundation
import UserNotifications
import CoreLocation
import SwiftUI

// MARK: - Dispatched Load Model
// Represents an incoming load assignment from the dispatcher (Supabase: dispatched_loads table)
struct DispatchedLoad: Codable, Identifiable, Equatable {
    let id: String
    let driverId: String
    let loadNumber: String
    let originAddress: String
    let destinationAddress: String
    let destinationLatitude: Double
    let destinationLongitude: Double
    let pickupTime: Date?
    let deliveryTime: Date?
    let commodity: String?
    let weightLbs: Double?
    let specialInstructions: String?
    var status: LoadStatus

    // B2B fields — populated when load is dispatched from a fleet company
    let companyId: String?        // Company that dispatched this load
    let companyName: String?      // Display name of the company
    let valorFrete: Double?       // Freight value in USD (for profit tracking)
    let precoDieselEia: Double?   // EIA government diesel average for comparison (USD/gallon)

    enum LoadStatus: String, Codable {
        case pending      = "pending"
        case received     = "received"    // Driver acknowledged
        case enRoute      = "en_route"
        case delivered    = "delivered"
        case cancelled    = "cancelled"
    }

    var destinationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)
    }

    // Deep link URL format: truckereasy://dispatch?loadId=...&lat=...&lng=...&address=...
    var deepLinkURL: URL? {
        var components = URLComponents()
        components.scheme = "truckereasy"
        components.host = "dispatch"
        components.queryItems = [
            URLQueryItem(name: "loadId", value: id),
            URLQueryItem(name: "lat", value: String(destinationLatitude)),
            URLQueryItem(name: "lng", value: String(destinationLongitude)),
            URLQueryItem(name: "address", value: destinationAddress),
            URLQueryItem(name: "loadNumber", value: loadNumber)
        ]
        return components.url
    }
}

// MARK: - Dispatch Service
// Handles incoming load notifications and status reporting back to dispatcher
@Observable
class DispatchService {
    // Pending load received via notification/deep link
    var pendingLoad: DispatchedLoad?
    var showingDispatchAlert = false

    static let shared = DispatchService()

    private init() {}

    // Called when app receives a push notification with load data
    func handleIncomingLoad(_ load: DispatchedLoad) {
        pendingLoad = load
        showingDispatchAlert = true
        // Schedule a local confirmation notification
        scheduleReceivedConfirmation(for: load)
    }

    /// Custom scheme `truckereasy://dispatch?...` or Universal Link `https://truckereasy.com/dispatch/...?...`
    func handleDeepLink(_ url: URL) -> DispatchedLoad? {
        guard isDispatchDeepLink(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }

        let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        guard let loadId   = params["loadId"],
              let latStr   = params["lat"],    let lat = Double(latStr),
              let lngStr   = params["lng"],    let lng = Double(lngStr),
              let address  = params["address"] else { return nil }

        let load = DispatchedLoad(
            id: loadId,
            driverId: SupabaseClient.shared.currentDriverId ?? "current-driver",
            loadNumber: params["loadNumber"] ?? loadId,
            originAddress: "Current Location",
            destinationAddress: address.removingPercentEncoding ?? address,
            destinationLatitude: lat,
            destinationLongitude: lng,
            pickupTime: nil,
            deliveryTime: nil,
            commodity: params["commodity"],
            weightLbs: params["weight"].flatMap { Double($0) },
            specialInstructions: params["notes"],
            status: .pending,
            companyId: params["companyId"],
            companyName: params["companyName"]?.removingPercentEncoding,
            valorFrete: params["valorFrete"].flatMap { Double($0) },
            precoDieselEia: params["precoDieselEia"].flatMap { Double($0) }
        )
        return load
    }

    private func isDispatchDeepLink(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "truckereasy", url.host == "dispatch" { return true }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "https" || scheme == "http" else { return false }
        let host = url.host?.lowercased() ?? ""
        guard host == "truckereasy.com" || host == "www.truckereasy.com" else { return false }
        let path = url.path.lowercased()
        return path.contains("dispatch") || path.hasPrefix("/app/")
    }

    // Report back to dispatcher that load was received/acknowledged
    func acknowledgeLoad(_ load: DispatchedLoad, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                try await SupabaseClient.shared.acknowledgeLoad(id: load.id)
                await MainActor.run { completion(true) }
            } catch {
                #if DEBUG
                print("DispatchService: failed to acknowledge load \(load.id) — \(error.localizedDescription)")
                #endif
                await MainActor.run { completion(false) }
            }
        }
    }

    // Parse push notification payload into a DispatchedLoad
    func loadFromNotificationPayload(_ userInfo: [AnyHashable: Any]) -> DispatchedLoad? {
        guard let loadData = userInfo["load"] as? [String: Any],
              let id       = loadData["id"]      as? String,
              let driverId = loadData["driver_id"] as? String,
              let loadNum  = loadData["load_number"] as? String,
              let origin   = loadData["origin_address"] as? String,
              let dest     = loadData["destination_address"] as? String,
              let lat      = loadData["destination_lat"] as? Double,
              let lng      = loadData["destination_lng"] as? Double else { return nil }

        return DispatchedLoad(
            id: id,
            driverId: driverId,
            loadNumber: loadNum,
            originAddress: origin,
            destinationAddress: dest,
            destinationLatitude: lat,
            destinationLongitude: lng,
            pickupTime: nil,
            deliveryTime: nil,
            commodity: loadData["commodity"] as? String,
            weightLbs: loadData["weight_lbs"] as? Double,
            specialInstructions: loadData["instructions"] as? String,
            status: .pending,
            companyId: loadData["company_id"] as? String,
            companyName: loadData["company_name"] as? String,
            valorFrete: loadData["valor_frete"] as? Double,
            precoDieselEia: loadData["preco_diesel_eia"] as? Double
        )
    }

    // Mark load as en_route — called when driver accepts and starts navigation
    func startRoute(for load: DispatchedLoad) {
        Task {
            do {
                try await SupabaseClient.shared.updateLoadStatus(id: load.id, status: .enRoute)
            } catch {
                #if DEBUG
                print("DispatchService: failed to update status to en_route — \(error.localizedDescription)")
                #endif
            }
        }
    }

    // Mark load as delivered — called when driver taps "Mark Delivered"
    func markDelivered(_ load: DispatchedLoad, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                try await SupabaseClient.shared.updateLoadStatus(id: load.id, status: .delivered)
                await MainActor.run { completion(true) }
            } catch {
                #if DEBUG
                print("DispatchService: failed to mark delivered — \(error.localizedDescription)")
                #endif
                await MainActor.run { completion(false) }
            }
        }
    }

    // Report a fuel stop — price paid vs EIA average feeds back to company profit dashboard
    func reportFuelStop(for load: DispatchedLoad, gallons: Double, pricePerGallon: Double, stationName: String?, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                try await SupabaseClient.shared.reportFuelPurchase(
                    loadId: load.id,
                    driverId: load.driverId,
                    companyId: load.companyId,
                    gallons: gallons,
                    pricePerGallon: pricePerGallon,
                    eiaAverage: load.precoDieselEia,
                    stationName: stationName
                )
                await MainActor.run { completion(true) }
            } catch {
                #if DEBUG
                print("DispatchService: failed to report fuel stop — \(error.localizedDescription)")
                #endif
                await MainActor.run { completion(false) }
            }
        }
    }

    // MARK: - Local notification when load is confirmed received
    private func scheduleReceivedConfirmation(for load: DispatchedLoad) {
        let content = UNMutableNotificationContent()
        content.title = "Load #\(load.loadNumber) Received"
        content.body = "Destination: \(load.destinationAddress)"
        content.sound = .default
        content.userInfo = ["loadId": load.id]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "load-\(load.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Truck Routing Configuration
// Height/weight/bridge restrictions for truck-safe routing
// Renamed DispatchTruckConfig to avoid module-level name conflict with ModelsTruckProfile.TruckProfile
private struct DispatchTruckConfig {
    var heightMeters: Double        // Vehicle height
    var weightTonnes: Double        // Gross vehicle weight
    var lengthMeters: Double        // Total length including trailer
    var axleWeightTonnes: Double    // Per-axle weight
    var hasHazmat: Bool
    var truckType: VehicleKind

    enum VehicleKind: String, CaseIterable {
        case semi        = "Semi-Truck (18-Wheeler)"
        case straight    = "Straight Truck"
        case tanker      = "Tanker"
        case flatbed     = "Flatbed"
        case refrigerated = "Reefer"

        var defaultHeight: Double {
            switch self {
            case .semi, .refrigerated: return 4.11  // 13'6" standard US limit
            case .tanker:              return 3.96
            case .flatbed:             return 4.27  // can carry taller loads
            case .straight:            return 3.66
            }
        }
        var defaultWeight: Double {
            switch self {
            case .semi:    return 36.29  // 80,000 lbs
            default:       return 11.34  // 25,000 lbs
            }
        }
    }

    static let `default` = DispatchTruckConfig(
        heightMeters: 4.11,
        weightTonnes: 36.29,
        lengthMeters: 22.0,
        axleWeightTonnes: 8.16,
        hasHazmat: false,
        truckType: .semi
    )

    // MapKit MKDirections has no truck dimensions (height/GVW); we use automobile + tollPreference when avoiding tolls.
    // These restrictions are used to display warnings and to pass to the active map / routing stack.
    // For MapKit routes, we annotate known low-clearance bridges as map overlays.
    var heightWarningText: String {
        "Max height: \(String(format: "%.2f", heightMeters))m (\(String(format: "%.0f'", heightMeters * 3.28084))\(String(format: "%.0f\"", (heightMeters * 3.28084 - floor(heightMeters * 3.28084)) * 12)))"
    }
}

// MARK: - Truck Restriction Warning Model
// NOTA: TruckRestrictionWarning está definido em ViewsTruckRestrictionAlertView.swift
// Definição duplicada removida para evitar erro de compilação
// O modelo partilhado inclui:
// - Equatable
// - CLLocationCoordinate2D
// - Conversão automática de TruckRouteNotice (provedor de rota)

/*
struct TruckRestrictionWarning: Identifiable {
    let id = UUID()
    let type: WarningType
    let description: String
    let location: String

    enum WarningType {
        case lowBridge, weightLimit, heightLimit, hazmat, tunnel
        var icon: String {
            switch self {
            case .lowBridge:   return "exclamationmark.triangle.fill"
            case .weightLimit: return "scalemass.fill"
            case .heightLimit: return "arrow.up.to.line"
            case .hazmat:      return "biohazard"
            case .tunnel:      return "tunnel"
            }
        }
        var color: Color {
            switch self {
            case .lowBridge, .heightLimit: return AppTheme.Colors.danger
            case .weightLimit:             return AppTheme.Colors.warning
            case .hazmat:                  return Color(hex: "#f59e0b")
            case .tunnel:                  return AppTheme.Colors.accentSoft
            }
        }
    }
}
*/
