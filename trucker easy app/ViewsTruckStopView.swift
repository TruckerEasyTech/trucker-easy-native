import SwiftUI
import MapKit
import CoreLocation

// MARK: - Truck Stop Network Detection

enum TruckStopNetwork: String, CaseIterable {
    case pilotFlyingJ  = "Pilot Flying J"
    case loves         = "Love's"
    case taPetro       = "TA / Petro"
    case sappBros      = "Sapp Bros"
    case littleAmerica = "Little America"
    case roadsRangers  = "Road Ranger"
    case kwikTrip      = "Kwik Trip"
    case independent   = "Independent"

    // Brand accent color
    var brandColor: Color {
        switch self {
        case .pilotFlyingJ:  return Color(hex: "#e63312") // Pilot red
        case .loves:         return Color(hex: "#e31837") // Love's red
        case .taPetro:       return Color(hex: "#0066cc") // TA blue
        case .sappBros:      return Color(hex: "#2ecc71")
        case .littleAmerica: return Color(hex: "#f59e0b")
        case .roadsRangers:  return Color(hex: "#8b5cf6")
        case .kwikTrip:      return Color(hex: "#e11d48")
        case .independent:   return AppTheme.Colors.textSecondary
        }
    }

    var icon: String {
        switch self {
        case .pilotFlyingJ:  return "airplane.departure"
        case .loves:         return "heart.fill"
        case .taPetro:       return "car.side.fill"
        case .sappBros:      return "star.fill"
        case .littleAmerica: return "flag.fill"
        case .roadsRangers:  return "road.lanes"
        case .kwikTrip:      return "bolt.fill"
        case .independent:   return "fuelpump.fill"
        }
    }

    /// Short letter badge shown in the navigation sidebar (like TruckerPath's "P T P" strip)
    var shortLabel: String {
        switch self {
        case .pilotFlyingJ:  return "P"
        case .loves:         return "L"
        case .taPetro:       return "T"
        case .sappBros:      return "S"
        case .littleAmerica: return "LA"
        case .roadsRangers:  return "R"
        case .kwikTrip:      return "K"
        case .independent:   return "I"
        }
    }

    /// Tier description for driver context
    var tierLabel: String {
        switch self {
        case .pilotFlyingJ:  return "Largest network • Rewards program"
        case .loves:         return "Best tire care • Clean showers"
        case .taPetro:       return "Full-service • Sit-down restaurants"
        case .sappBros:      return "Independent • Lower prices"
        case .littleAmerica: return "Scenic stops • Quality food"
        case .roadsRangers:  return "Midwest chain"
        case .kwikTrip:      return "Fresh food focus"
        case .independent:   return "Independently owned"
        }
    }

    /// Detect network from place name
    static func detect(from name: String) -> TruckStopNetwork {
        let lower = name.lowercased()
        if lower.contains("pilot") || lower.contains("flying j") { return .pilotFlyingJ }
        if lower.contains("love's") || lower.contains("loves") { return .loves }
        if lower.contains(" ta ") || lower.contains("travel center") || lower.contains("petro") { return .taPetro }
        if lower.contains("sapp") { return .sappBros }
        if lower.contains("little america") { return .littleAmerica }
        if lower.contains("road ranger") { return .roadsRangers }
        if lower.contains("kwik trip") || lower.contains("kwiktrip") { return .kwikTrip }
        return .independent
    }
}

// MARK: - Truck Stop Amenity Model

struct TruckStopAmenities {
    // Rating & reviews (community-sourced)
    var rating: Double?             // 1.0–5.0 stars
    var reviewCount: Int?           // Number of reviews

    // Logistics
    var parkingSlots: Int?          // Total truck parking spaces
    var parkingAvailable: Int?      // Live: available slots (crowdsourced)
    var hasReservableParking: Bool  // Pre-book a spot
    var parkingUpdatedAt: Date?     // When parking count was last updated

    // Hygiene & wellness
    var showerCount: Int?
    var showerWaitMinutes: Int?     // Crowdsourced wait time
    var hasLaundry: Bool
    var hasLounge: Bool             // Trucker lounge / TV room
    var hasWifi: Bool               // Free WiFi for drivers

    // Food
    var foodType: FoodType
    var hasHealthyOptions: Bool     // Fresh food, salads, not just fast food
    var restaurantNames: [String]   // e.g. ["Denny's", "Subway"]

    // Truck care
    var hasCATScale: Bool  // CAT Scale certified weigh station
    var hasTireService: Bool        // Love's Truck Care style
    var hasMechanic: Bool
    var hasDEF: Bool                // Diesel Exhaust Fluid
    var defPrice: Double?           // DEF $/gal
    var defUpdatedAt: Date?         // When DEF price was last updated

    // Fuel
    var dieselPrice: Double?        // $/gal - crowdsourced
    var dieselUpdatedAt: Date?      // When diesel price was last updated
    var acceptsTruckCard: Bool      // Comdata, EFS, etc.

    enum FoodType: String {
        case fullService  = "Full-Service Restaurant"
        case fastFood     = "Fast Food Only"
        case freshDeli    = "Fresh Deli & Market"
        case vending      = "Vending Only"
        case none         = "No Food"
    }

    // Parking status label
    var parkingStatus: ParkingStatus {
        guard let total = parkingSlots, total > 0 else { return .unknown }
        guard let available = parkingAvailable else { return .unknown }
        let fraction = Double(available) / Double(total)
        if fraction > 0.3 { return .available }
        if fraction > 0.05 { return .limited }
        return .full
    }

    enum ParkingStatus {
        case available, limited, full, unknown
        var label: String {
            switch self {
            case .available: return "Spaces Available"
            case .limited:   return "Few Spaces Left"
            case .full:      return "FULL"
            case .unknown:   return "Parking Info N/A"
            }
        }
        var color: Color {
            switch self {
            case .available: return AppTheme.Colors.success
            case .limited:   return AppTheme.Colors.warning
            case .full:      return AppTheme.Colors.danger
            case .unknown:   return AppTheme.Colors.textSecondary
            }
        }
        var icon: String {
            switch self {
            case .available: return "checkmark.circle.fill"
            case .limited:   return "exclamationmark.circle.fill"
            case .full:      return "xmark.circle.fill"
            case .unknown:   return "questionmark.circle.fill"
            }
        }
    }
}

// MARK: - Enriched Truck Stop Item

struct TruckStopItem: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let phone: String?
    let network: TruckStopNetwork
    var amenities: TruckStopAmenities
    var crowdsourceReports: [CrowdsourceReport] = []

    var distanceText: String {
        if distanceMeters < 1609 {
            return String(format: "%.0f ft", distanceMeters * 3.28084)
        }
        return String(format: "%.1f mi", distanceMeters / 1609.34)
    }

    // HOS-reachability: is this stop reachable within the given hours remaining?
    func isReachable(withHoursRemaining hours: Double, avgSpeedMph: Double = 55) -> Bool {
        let maxMiles = hours * avgSpeedMph
        let stopMiles = distanceMeters / 1609.34
        return stopMiles <= maxMiles
    }

    /// Posto / travel plaza — sugestão alimentar só quando parado neste tipo de paragem.
    var qualifiesAsFuelStopForFood: Bool {
        if amenities.dieselPrice != nil { return true }
        if network != .independent { return true }
        let n = name.lowercased()
        return n.contains("fuel") || n.contains("diesel") || n.contains("travel")
            || n.contains("truck") || n.contains("pilot") || n.contains("loves")
            || n.contains("ta ") || n.contains("petro") || n.contains("flying j")
    }

    /// Wellness score 0-100 based on food quality + shower + parking availability
    var wellnessScore: Int {
        var score = 50
        if amenities.hasHealthyOptions { score += 20 }
        if amenities.foodType == .freshDeli { score += 10 }
        if amenities.foodType == .fullService { score += 5 }
        if amenities.showerCount ?? 0 > 10 { score += 10 }
        if amenities.showerWaitMinutes ?? 99 < 15 { score += 5 }
        return min(score, 100)
    }
}

// MARK: - Crowdsource Report

struct CrowdsourceReport: Identifiable {
    let id = UUID()
    let type: ReportType
    let note: String
    let reportedAt: Date
    var thumbsUp: Int = 0

    enum ReportType: String, CaseIterable {
        case dieselPriceWrong = "Price Wrong"
        case scaleOpen        = "Scale Open"
        case scaleClosed      = "Scale Closed"
        case showerWait       = "Long Shower Wait"
        case parkingFull      = "Parking Full"
        case parkingAvailable = "Parking Available"
        case greatFood        = "Great Food"
        case poorConditions   = "Poor Conditions"

        var icon: String {
            switch self {
            case .dieselPriceWrong: return "dollarsign.circle.fill"
            case .scaleOpen:        return "scalemass.fill"
            case .scaleClosed:      return "scalemass"
            case .showerWait:       return "shower.fill"
            case .parkingFull:      return "p.circle.fill"
            case .parkingAvailable: return "p.circle"
            case .greatFood:        return "fork.knife"
            case .poorConditions:   return "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .dieselPriceWrong: return Color(hex: "#f59e0b")
            case .scaleOpen:        return AppTheme.Colors.success
            case .scaleClosed:      return AppTheme.Colors.danger
            case .showerWait:       return AppTheme.Colors.warning
            case .parkingFull:      return AppTheme.Colors.danger
            case .parkingAvailable: return AppTheme.Colors.success
            case .greatFood:        return Color(hex: "#10b981")
            case .poorConditions:   return AppTheme.Colors.danger
            }
        }
    }
}

private extension CrowdsourceReport.ReportType {
    var backendKey: String {
        switch self {
        case .dieselPriceWrong: return "dieselPriceWrong"
        case .scaleOpen: return "scaleOpen"
        case .scaleClosed: return "scaleClosed"
        case .showerWait: return "showerWait"
        case .parkingFull: return "parkingFull"
        case .parkingAvailable: return "parkingAvailable"
        case .greatFood: return "greatFood"
        case .poorConditions: return "poorConditions"
        }
    }

    static func fromBackendKey(_ key: String) -> Self? {
        switch key {
        case "dieselPriceWrong": return .dieselPriceWrong
        case "scaleOpen": return .scaleOpen
        case "scaleClosed": return .scaleClosed
        case "showerWait": return .showerWait
        case "parkingFull": return .parkingFull
        case "parkingAvailable": return .parkingAvailable
        case "greatFood": return .greatFood
        case "poorConditions": return .poorConditions
        default: return nil
        }
    }
}

// MARK: - HOS State (Hours of Service)

struct HOSState {
    var driveTimeRemainingHours: Double  // Hours driver can still legally drive
    var dutyTimeRemainingHours: Double   // Total on-duty hours remaining
    var isInBreak: Bool
    var breakEndsAt: Date?

    static let mock = HOSState(
        driveTimeRemainingHours: 4.5,
        dutyTimeRemainingHours: 7.0,
        isInBreak: false,
        breakEndsAt: nil
    )

    var driveTimeText: String {
        let h = Int(driveTimeRemainingHours)
        let m = Int((driveTimeRemainingHours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var urgencyColor: Color {
        if driveTimeRemainingHours < 1 { return AppTheme.Colors.danger }
        if driveTimeRemainingHours < 2 { return AppTheme.Colors.warning }
        return AppTheme.Colors.success
    }

    /// Max distance (miles) driveable at avg speed
    func reachableMiles(avgSpeedMph: Double = 55) -> Double {
        driveTimeRemainingHours * avgSpeedMph
    }
}

// MARK: - Truck Stop Service

@MainActor
@Observable
final class TruckStopService {
    static let shared = TruckStopService()

    var nearbyStops: [TruckStopItem] = []
    var isLoading = false
    var hos = HOSState.mock

    private init() {}

    func searchNearby(location: CLLocation, radiusMeters: Double = 80467) async { // 50mi
        isLoading = true

        // Multi-query strategy: cover all major truck-stop brand names and generic terms.
        // Parallel searches then de-duplicate, giving significantly better coverage than
        // a single generic query.
        let queries = [
            "Pilot Flying J truck stop",
            "Love's Travel Stop",
            "Petro Stopping Center",
            "TA Travel Center",
            "Flying J truck stop",
            "truck stop",
            "travel plaza trucks",
            "Sapp Bros travel center"
        ]
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )

        var allItems: [MKMapItem] = []
        await withTaskGroup(of: [MKMapItem].self) { group in
            for query in queries {
                group.addTask {
                    let req = MKLocalSearch.Request()
                    req.naturalLanguageQuery = query
                    req.region = region
                    return (try? await MKLocalSearch(request: req).start())?.mapItems ?? []
                }
            }
            for await items in group {
                allItems.append(contentsOf: items)
            }
        }

        // De-duplicate by proximity (< 300m apart = same stop)
        var deduped: [MKMapItem] = []
        for item in allItems {
            let loc = item.location
            let isDup = deduped.contains { $0.location.distance(from: loc) < 300 }
            if !isDup { deduped.append(item) }
        }

        // Filter to stops within the search radius and convert
        let results = deduped.filter { location.distance(from: $0.location) <= radiusMeters }

        nearbyStops = results.prefix(20).compactMap { item -> TruckStopItem? in
            let loc = item.location
            let dist = location.distance(from: loc)
            let name = item.name ?? "Truck Stop"
            let network = TruckStopNetwork.detect(from: name)
            let addr = item.address?.fullAddress ?? ""

            // Real-data baseline: only infer fields available from map metadata / crowdsource.
            let amenities = amenitiesFromMapItem(item, network: network)

            return TruckStopItem(
                name: name,
                address: addr,
                coordinate: loc.coordinate,
                distanceMeters: dist,
                phone: item.phoneNumber,
                network: network,
                amenities: amenities
            )
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }

        isLoading = false
    }

    /// Stops reachable given current HOS
    var reachableStops: [TruckStopItem] {
        nearbyStops.filter { $0.isReachable(withHoursRemaining: hos.driveTimeRemainingHours) }
    }

    /// Merge partner operational parking signals (official/provider feed).
    func applyOperationalSignals(_ signals: [PartnerParkingSignal]) {
        guard !signals.isEmpty else { return }

        for signal in signals {
            let signalLocation = CLLocation(latitude: signal.latitude, longitude: signal.longitude)

            guard let index = nearbyStops.enumerated()
                .map({ ($0.offset, CLLocation(latitude: $0.element.coordinate.latitude, longitude: $0.element.coordinate.longitude)) })
                .map({ ($0.0, signalLocation.distance(from: $0.1)) })
                .filter({ $0.1 <= 1_500 })
                .sorted(by: { $0.1 < $1.1 })
                .first?.0 else {
                continue
            }

            nearbyStops[index].amenities.parkingAvailable = signal.availableSlots
            nearbyStops[index].amenities.parkingSlots = signal.totalSlots ?? nearbyStops[index].amenities.parkingSlots
            nearbyStops[index].amenities.parkingUpdatedAt = signal.updatedAt ?? Date()
        }
    }

    /// Add a crowdsource report to a stop
    func addReport(to stopID: UUID, report: CrowdsourceReport) {
        if let idx = nearbyStops.firstIndex(where: { $0.id == stopID }) {
            nearbyStops[idx].crowdsourceReports.insert(report, at: 0)

            // Apply crowdsource data to amenities
            switch report.type {
            case .parkingFull:
                nearbyStops[idx].amenities.parkingAvailable = 0
            case .parkingAvailable:
                nearbyStops[idx].amenities.parkingAvailable = (nearbyStops[idx].amenities.parkingSlots ?? 50) / 2
            default:
                break
            }
        }
    }

    // MARK: - Real amenities baseline (no synthetic ratings/prices)
    private func amenitiesFromMapItem(_ item: MKMapItem, network: TruckStopNetwork) -> TruckStopAmenities {
        let normalized = (item.name ?? "").lowercased()
        let hasCATScale = normalized.contains("cat scale") || normalized.contains("weigh")
        let likelyRepair = normalized.contains("truck care") || normalized.contains("service")
        let likelyFood = normalized.contains("travel center") || normalized.contains("truck stop")

        return TruckStopAmenities(
            rating: nil,
            reviewCount: nil,
            parkingSlots: nil,
            parkingAvailable: nil,
            hasReservableParking: false,
            parkingUpdatedAt: nil,
            showerCount: nil,
            showerWaitMinutes: nil,
            hasLaundry: false,
            hasLounge: false,
            hasWifi: false,
            foodType: likelyFood ? .fastFood : .none,
            hasHealthyOptions: false,
            restaurantNames: [],
            hasCATScale: hasCATScale,
            hasTireService: likelyRepair,
            hasMechanic: likelyRepair,
            hasDEF: false,
            defPrice: nil,
            defUpdatedAt: nil,
            dieselPrice: nil,
            dieselUpdatedAt: nil,
            acceptsTruckCard: false
        )
    }
}

// MARK: - HOS Tracker Bar

struct HOSTrackerBar: View {
    let hos: HOSState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Clock icon
                ZStack {
                    Circle()
                        .fill(hos.urgencyColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: hos.isInBreak ? "bed.double.fill" : "clock.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(hos.urgencyColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(hos.isInBreak ? "IN BREAK" : "DRIVE TIME LEFT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .kerning(0.8)
                    Text(hos.isInBreak ? "Rest required" : hos.driveTimeText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(hos.urgencyColor)
                }

                Spacer()

                // Progress arc
                HoursArc(fraction: hos.driveTimeRemainingHours / 11.0, color: hos.urgencyColor)
                    .frame(width: 36, height: 36)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(AppTheme.Radius.md)
        }
    }
}

struct HoursArc: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(fraction, 1))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - HOS Alert Banner (shown when < 1h drive time remains)

struct HOSAlertBanner: View {
    let hos: HOSState
    let onTap: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.danger.opacity(pulse ? 0.35 : 0.15))
                        .frame(width: 36, height: 36)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(AppTheme.Colors.danger)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("HOS LIMIT APPROACHING")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(AppTheme.Colors.danger)
                        .kerning(0.8)
                    Text("\(hos.driveTimeText) remaining — plan your rest stop now")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(Color(hex: "#1a0a0a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .stroke(AppTheme.Colors.danger.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onAppear { pulse = true }
    }
}

// MARK: - HOS Telemetry Widget (compact floating map widget)

struct HOSTelemetryWidget: View {
    let hos: HOSState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Drive arc
                ZStack {
                    Circle()
                        .stroke(AppTheme.Colors.backgroundCard.opacity(0.6), lineWidth: 5)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: min(hos.driveTimeRemainingHours / 11.0, 1))
                        .stroke(hos.urgencyColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Image(systemName: hos.isInBreak ? "bed.double.fill" : "steeringwheel")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(hos.urgencyColor)
                        Text(hos.isInBreak ? "REST" : hos.driveTimeText)
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(hos.urgencyColor)
                            .minimumScaleFactor(0.7)
                    }
                }

                // Duty arc
                ZStack {
                    Circle()
                        .stroke(AppTheme.Colors.backgroundCard.opacity(0.6), lineWidth: 4)
                        .frame(width: 36, height: 36)
                    Circle()
                        .trim(from: 0, to: min(hos.dutyTimeRemainingHours / 14.0, 1))
                        .stroke(AppTheme.Colors.accentSoft, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))
                    Text("ON")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(AppTheme.Colors.accentSoft)
                }

                Text("HOS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Truck Stops Panel (enhanced, HOS-aware)

struct TruckStopsPanel: View {
    let stops: [TruckStopItem]
    let hos: HOSState
    let isLoading: Bool
    let onClose: () -> Void
    let onSelect: (TruckStopItem) -> Void

    @State private var showOnlyReachable = true

    var displayedStops: [TruckStopItem] {
        if showOnlyReachable {
            let reachable = stops.filter { $0.isReachable(withHoursRemaining: hos.driveTimeRemainingHours) }
            return reachable.isEmpty ? stops : reachable
        }
        return stops
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#f59e0b").opacity(0.2))
                        .frame(width: 34, height: 34)
                    Image(systemName: "fuelpump.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "#f59e0b"))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Truck Stops")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(displayedStops.count) within \(hos.driveTimeText) drive")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()

                // HOS filter toggle
                Button(action: { withAnimation { showOnlyReachable.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: showOnlyReachable ? "clock.badge.checkmark" : "clock")
                            .font(.system(size: 11, weight: .bold))
                        Text(showOnlyReachable ? "HOS" : "All")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(showOnlyReachable ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(showOnlyReachable ? AppTheme.Colors.accent.opacity(0.15) : AppTheme.Colors.backgroundCard)
                    .cornerRadius(AppTheme.Radius.pill)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().background(AppTheme.Colors.backgroundCard)

            if isLoading {
                HStack(spacing: 12) {
                    ProgressView().tint(AppTheme.Colors.accent)
                    Text("Finding truck stops...")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(.vertical, 24)
            } else if displayedStops.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fuelpump")
                        .font(.system(size: 28))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Text("No truck stops found")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(displayedStops) { stop in
                            TruckStopRow(stop: stop, hos: hos, onSelect: { onSelect(stop) })
                            if stop.id != displayedStops.last?.id {
                                Divider()
                                    .background(AppTheme.Colors.backgroundCard)
                                    .padding(.leading, 66)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .background(AppTheme.Colors.backgroundSecond)
        .cornerRadius(AppTheme.Radius.lg)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg).stroke(AppTheme.Colors.backgroundCard, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 4)
    }
}

// MARK: - Truck Stop Row

struct TruckStopRow: View {
    let stop: TruckStopItem
    let hos: HOSState
    let onSelect: () -> Void

    private var isReachable: Bool {
        stop.isReachable(withHoursRemaining: hos.driveTimeRemainingHours)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Network brand badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(stop.network.brandColor.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: stop.network.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(stop.network.brandColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(stop.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        // Reachability dot
                        Circle()
                            .fill(isReachable ? AppTheme.Colors.success : AppTheme.Colors.danger)
                            .frame(width: 6, height: 6)
                    }

                    // Amenity icons row
                    HStack(spacing: 8) {
                        if stop.amenities.showerCount ?? 0 > 0 {
                            AmenityDot(icon: "shower.fill", color: AppTheme.Colors.accent)
                        }
                        if stop.amenities.hasCATScale {
                            AmenityDot(icon: "scalemass.fill", color: Color(hex: "#f59e0b"))
                        }
                        if stop.amenities.hasTireService {
                            AmenityDot(icon: "car.side.fill", color: Color(hex: "#f97316"))
                        }
                        if stop.amenities.hasHealthyOptions {
                            AmenityDot(icon: "leaf.fill", color: Color(hex: "#10b981"))
                        }
                        if stop.amenities.hasReservableParking {
                            AmenityDot(icon: "p.circle.fill", color: AppTheme.Colors.accentSoft)
                        }
                        if stop.amenities.hasLaundry {
                            AmenityDot(icon: "washer.fill", color: AppTheme.Colors.textSecondary)
                        }
                        if stop.amenities.hasWifi {
                            AmenityDot(icon: "wifi", color: Color(hex: "#0ea5e9"))
                        }
                    }

                    Text(stop.address)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(stop.distanceText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isReachable ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)

                    if let price = stop.amenities.dieselPrice {
                        Text(String(format: "$%.3f", price))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#f59e0b"))
                    }

                    // Parking availability indicator
                    if let slots = stop.amenities.parkingSlots {
                        let available = stop.amenities.parkingAvailable
                        ParkingIndicator(total: slots, available: available)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isReachable ? Color.clear : Color.black.opacity(0.05))
        }
    }
}

struct AmenityDot: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
    }
}

struct ParkingIndicator: View {
    let total: Int
    let available: Int?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "p.circle.fill")
                .font(.system(size: 9))
                .foregroundColor(indicatorColor)
            if let avail = available {
                Text("\(avail)/\(total)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(indicatorColor)
            } else {
                Text("\(total)")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
    }

    private var indicatorColor: Color {
        guard let avail = available else { return AppTheme.Colors.textSecondary }
        let fraction = Double(avail) / Double(max(total, 1))
        if fraction > 0.3 { return AppTheme.Colors.success }
        if fraction > 0.1 { return AppTheme.Colors.warning }
        return AppTheme.Colors.danger
    }
}

// MARK: - Truck Stop Detail Sheet

struct TruckStopDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stop: TruckStopItem
    let hos: HOSState
    let onNavigate: (TruckStopItem) -> Void

    @State private var showingCrowdsource = false
    @State private var crowdsourceReports: [CrowdsourceReport] = []
    @State private var remoteReports: [CrowdsourceReport] = []

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {

                        // MARK: Header — Network Brand
                        networkHeader

                        // MARK: HOS Reachability Banner
                        hosBanner
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.top, AppTheme.Spacing.md)

                        // MARK: Section: Parking
                        amenitySection(
                            title: "PARKING",
                            icon: "p.circle.fill",
                            color: AppTheme.Colors.accent
                        ) {
                            parkingRows
                        }

                        // MARK: Section: Showers & Hygiene
                        amenitySection(
                            title: "SHOWERS & HYGIENE",
                            icon: "shower.fill",
                            color: Color(hex: "#6366f1")
                        ) {
                            showerRows
                        }

                        // MARK: Section: Food
                        amenitySection(
                            title: "FOOD",
                            icon: "fork.knife",
                            color: Color(hex: "#10b981")
                        ) {
                            foodRows
                        }

                        // MARK: Section: Truck Care
                        amenitySection(
                            title: "TRUCK CARE",
                            icon: "wrench.and.screwdriver.fill",
                            color: Color(hex: "#f97316")
                        ) {
                            truckCareRows
                        }

                        // MARK: Crowdsource Reports
                        if !stop.crowdsourceReports.isEmpty || !crowdsourceReports.isEmpty || !remoteReports.isEmpty {
                            crowdsourceSection
                        }

                        // MARK: Action Buttons
                        actionButtons
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.vertical, AppTheme.Spacing.lg)
                    }
                }
            }
            .navigationTitle(stop.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCrowdsource = true }) {
                        Label("Report", systemImage: "square.and.pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $showingCrowdsource) {
                CrowdsourceReportSheet(stopName: stop.name) { report in
                    crowdsourceReports.insert(report, at: 0)
                    TruckStopService.shared.addReport(to: stop.id, report: report)
                    Task { await submitRemoteReport(report) }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loadRemoteReports()
        }
    }

    // MARK: - Network Header

    private var networkHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(stop.network.brandColor.opacity(0.18))
                    .frame(width: 72, height: 72)
                Image(systemName: stop.network.icon)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(stop.network.brandColor)
            }

            VStack(spacing: 4) {
                Text(stop.network.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(stop.network.brandColor)
                    .kerning(0.8)
                Text(stop.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(stop.network.tierLabel)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Rating row
            if let rating = stop.amenities.rating {
                HStack(spacing: 6) {
                    ForEach(0..<5) { i in
                        Image(systemName: Double(i) < rating ? (rating - Double(i) >= 1 ? "star.fill" : "star.leadinghalf.filled") : "star")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: "#f59e0b"))
                    }
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "#f59e0b"))
                    if let reviews = stop.amenities.reviewCount {
                        Text("(\(reviews) reviews)")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
            }

            // Distance pill
            HStack(spacing: 8) {
                Label(stop.distanceText, systemImage: "location.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.accent)

                if let phone = stop.phone {
                    Text("•")
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Text(phone)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            // Wellness score
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundColor(wellnessColor)
                Text("Wellness Score: \(stop.wellnessScore)/100")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(wellnessColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(wellnessColor.opacity(0.12))
            .cornerRadius(AppTheme.Radius.pill)
        }
        .padding(.vertical, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [stop.network.brandColor.opacity(0.12), AppTheme.Colors.background],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var wellnessColor: Color {
        if stop.wellnessScore >= 70 { return Color(hex: "#10b981") }
        if stop.wellnessScore >= 40 { return AppTheme.Colors.warning }
        return AppTheme.Colors.danger
    }

    // MARK: - HOS Banner

    private var hosBanner: some View {
        let reachable = stop.isReachable(withHoursRemaining: hos.driveTimeRemainingHours)
        return HStack(spacing: 10) {
            Image(systemName: reachable ? "clock.badge.checkmark.fill" : "clock.badge.exclamationmark.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(reachable ? AppTheme.Colors.success : AppTheme.Colors.danger)

            VStack(alignment: .leading, spacing: 2) {
                Text(reachable ? "Reachable within HOS" : "Beyond drive time limit")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(reachable ? AppTheme.Colors.success : AppTheme.Colors.danger)
                Text("You have \(hos.driveTimeText) of drive time remaining")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background((reachable ? AppTheme.Colors.success : AppTheme.Colors.danger).opacity(0.08))
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke((reachable ? AppTheme.Colors.success : AppTheme.Colors.danger).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Amenity Section Builder

    @ViewBuilder
    private func amenitySection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .kerning(1.1)
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.sm)

            VStack(spacing: 0) {
                content()
            }
            .background(AppTheme.Colors.backgroundSecond)
            .cornerRadius(AppTheme.Radius.md)
            .padding(.horizontal, AppTheme.Spacing.md)
        }
    }

    // MARK: - Parking Rows

    @ViewBuilder
    private var parkingRows: some View {
        // Parking status banner
        let status = stop.amenities.parkingStatus
        HStack(spacing: 10) {
            Image(systemName: status.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(status.color)
                if let total = stop.amenities.parkingSlots, let avail = stop.amenities.parkingAvailable {
                    Text("\(avail) of \(total) spaces open")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                } else if let total = stop.amenities.parkingSlots {
                    Text("Capacity: \(total) spaces")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                if let updated = stop.amenities.parkingUpdatedAt {
                    Text("Updated \(updated.timeAgoText)")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.7))
                }
            }
            Spacer()
            // Parking fill bar
            if let total = stop.amenities.parkingSlots {
                let fraction = stop.amenities.parkingAvailable.map { Double($0) / Double(max(total, 1)) } ?? 0.5
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppTheme.Colors.backgroundCard)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(status.color)
                                .frame(width: geo.size.width * fraction, height: 6)
                        }
                    }
                    .frame(width: 60, height: 6)
                    Text(stop.amenities.parkingAvailable.map { "\($0)" } ?? "?")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(status.color)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(status.color.opacity(0.06))

        Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 14)

        detailRow(
            icon: "calendar.badge.checkmark",
            label: "Reserve a Spot",
            value: stop.amenities.hasReservableParking ? "Available — pre-book before arrival" : "Walk-in only",
            color: stop.amenities.hasReservableParking ? AppTheme.Colors.success : AppTheme.Colors.textSecondary
        )
    }

    // MARK: - Shower Rows

    @ViewBuilder
    private var showerRows: some View {
        if let count = stop.amenities.showerCount {
            detailRow(
                icon: "shower.fill",
                label: "Showers",
                value: "\(count) private showers",
                color: Color(hex: "#6366f1")
            )
            Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)

            if let wait = stop.amenities.showerWaitMinutes {
                detailRow(
                    icon: "clock.fill",
                    label: "Wait Time",
                    value: wait < 5 ? "Available now" : "\(wait) min wait",
                    color: wait < 15 ? AppTheme.Colors.success : AppTheme.Colors.warning
                )
                Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)
            }
        }

        detailRow(
            icon: "washer.fill",
            label: "Laundry",
            value: stop.amenities.hasLaundry ? "Washers & dryers on-site" : "Not available",
            color: stop.amenities.hasLaundry ? AppTheme.Colors.success : AppTheme.Colors.textSecondary
        )
        Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)

        detailRow(
            icon: "sofa.fill",
            label: "Driver Lounge",
            value: stop.amenities.hasLounge ? "TV room & seating area" : "Not available",
            color: stop.amenities.hasLounge ? AppTheme.Colors.success : AppTheme.Colors.textSecondary
        )
        Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)

        detailRow(
            icon: "wifi",
            label: "WiFi",
            value: stop.amenities.hasWifi ? "Free driver WiFi available" : "Not available",
            color: stop.amenities.hasWifi ? AppTheme.Colors.success : AppTheme.Colors.textSecondary
        )
    }

    // MARK: - Food Rows

    @ViewBuilder
    private var foodRows: some View {
        detailRow(
            icon: foodTypeIcon,
            label: "Type",
            value: stop.amenities.foodType.rawValue,
            color: foodTypeColor
        )

        if !stop.amenities.restaurantNames.isEmpty {
            Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)
            detailRow(
                icon: "list.bullet",
                label: "Options",
                value: stop.amenities.restaurantNames.joined(separator: " • "),
                color: AppTheme.Colors.textSecondary
            )
        }

        Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)

        // Health focus highlight
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((stop.amenities.hasHealthyOptions ? Color(hex: "#10b981") : AppTheme.Colors.textSecondary).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(stop.amenities.hasHealthyOptions ? Color(hex: "#10b981") : AppTheme.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Healthy Options")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(stop.amenities.hasHealthyOptions
                     ? "Fresh food, salads, and nutritious choices available"
                     : "Fast food only — fried & processed options")
                    .font(.system(size: 11))
                    .foregroundColor(stop.amenities.hasHealthyOptions ? Color(hex: "#10b981") : AppTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            stop.amenities.hasHealthyOptions
            ? Color(hex: "#10b981").opacity(0.05)
            : Color.clear
        )
    }

    private var foodTypeIcon: String {
        switch stop.amenities.foodType {
        case .fullService: return "fork.knife.circle.fill"
        case .fastFood:    return "bag.fill"
        case .freshDeli:   return "leaf.circle.fill"
        case .vending:     return "rectangle.fill.badge.checkmark"
        case .none:        return "xmark.circle.fill"
        }
    }

    private var foodTypeColor: Color {
        switch stop.amenities.foodType {
        case .fullService: return AppTheme.Colors.success
        case .fastFood:    return AppTheme.Colors.warning
        case .freshDeli:   return Color(hex: "#10b981")
        case .vending:     return AppTheme.Colors.textSecondary
        case .none:        return AppTheme.Colors.danger
        }
    }

    // MARK: - Truck Care Rows

    @ViewBuilder
    private var truckCareRows: some View {
        detailRow(
            icon: "scalemass.fill",
            label: "CAT Scale",
            value: stop.amenities.hasCATScale ? "On-site (certified weigh)" : "Not available",
            color: stop.amenities.hasCATScale ? Color(hex: "#f59e0b") : AppTheme.Colors.textSecondary
        )
        Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)

        detailRow(
            icon: "car.side.fill",
            label: "Tire Service",
            value: stop.amenities.hasTireService ? "Love's Truck Care on-site" : "Not available",
            color: stop.amenities.hasTireService ? AppTheme.Colors.success : AppTheme.Colors.textSecondary
        )
        Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)

        detailRow(
            icon: "wrench.and.screwdriver.fill",
            label: "Mechanic",
            value: stop.amenities.hasMechanic ? "Full-service shop" : "Not available",
            color: stop.amenities.hasMechanic ? AppTheme.Colors.success : AppTheme.Colors.textSecondary
        )
        Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)

        // DEF row — show price and last-updated time if available
        let defValue: String = {
            if !stop.amenities.hasDEF { return "Not available" }
            if let p = stop.amenities.defPrice {
                let updated = stop.amenities.defUpdatedAt.map { "· Updated \($0.timeAgoText)" } ?? ""
                return String(format: "$%.3f/gal %@", p, updated)
            }
            return "Available"
        }()
        detailRow(
            icon: "fuelpump.circle.fill",
            label: "DEF",
            value: defValue,
            color: stop.amenities.hasDEF ? AppTheme.Colors.success : AppTheme.Colors.textSecondary
        )

        if let price = stop.amenities.dieselPrice {
            Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 52)
            let dieselUpdated = stop.amenities.dieselUpdatedAt.map { " · Updated \($0.timeAgoText)" } ?? ""
            detailRow(
                icon: "dollarsign.circle.fill",
                label: "Diesel",
                value: String(format: "$%.3f/gal%@", price, dieselUpdated),
                color: Color(hex: "#f59e0b")
            )
        }
    }

    // MARK: - Crowdsource Section

    private var crowdsourceSection: some View {
        let allReports = (crowdsourceReports + remoteReports + stop.crowdsourceReports)
            .sorted { $0.reportedAt > $1.reportedAt }

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.Colors.accentSoft)
                Text("DRIVER REPORTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .kerning(1.1)
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.sm)

            VStack(spacing: 0) {
                ForEach(allReports.prefix(5)) { report in
                    HStack(spacing: 10) {
                        Image(systemName: report.type.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(report.type.color)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.type.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            if !report.note.isEmpty {
                                Text(report.note)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                        }
                        Spacer()
                        Text(report.reportedAt.timeAgoText)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    if report.id != allReports.prefix(5).last?.id {
                        Divider().background(AppTheme.Colors.backgroundCard).padding(.leading, 48)
                    }
                }
            }
            .background(AppTheme.Colors.backgroundSecond)
            .cornerRadius(AppTheme.Radius.md)
            .padding(.horizontal, AppTheme.Spacing.md)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Navigate CTA
            Button(action: {
                onNavigate(stop)
                dismiss()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Navigate Here")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [AppTheme.Colors.cta, Color(hex: "#E65100")],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(AppTheme.Radius.md)
                .shadow(color: AppTheme.Colors.cta.opacity(0.5), radius: 8, y: 3)
            }

            // Report button
            Button(action: { showingCrowdsource = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Report Stop Data")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(AppTheme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.Colors.accent.opacity(0.1))
                .cornerRadius(AppTheme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Generic Detail Row

    @ViewBuilder
    private func detailRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @MainActor
    private func loadRemoteReports() async {
        do {
            let records = try await SupabaseClient.shared.fetchRoadReports(locationName: stop.name)
            remoteReports = records.compactMap { record in
                guard let type = CrowdsourceReport.ReportType.fromBackendKey(record.report_type) else { return nil }
                let reportedAt = ISO8601DateFormatter().date(from: record.reported_at) ?? Date()
                return CrowdsourceReport(
                    type: type,
                    note: "",
                    reportedAt: reportedAt,
                    thumbsUp: record.confirmations ?? 0
                )
            }
        } catch {
            print("TruckStopDetailSheet: failed to load remote reports — \(error.localizedDescription)")
        }
    }

    private func submitRemoteReport(_ report: CrowdsourceReport) async {
        let payload = RoadReportPayload(
            driver_id: SupabaseClient.shared.currentDriverId,
            report_type: report.type.backendKey,
            latitude: stop.coordinate.latitude,
            longitude: stop.coordinate.longitude,
            location_name: stop.name
        )
        do {
            try await SupabaseClient.shared.submitRoadReport(payload)
            await loadRemoteReports()
        } catch {
            print("TruckStopDetailSheet: failed to sync truck stop report — \(error.localizedDescription)")
        }
    }
}

// MARK: - Crowdsource Report Sheet

struct CrowdsourceReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stopName: String
    let onSubmit: (CrowdsourceReport) -> Void

    @State private var selectedType: CrowdsourceReport.ReportType = .parkingAvailable
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                VStack(spacing: AppTheme.Spacing.lg) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 32))
                            .foregroundColor(AppTheme.Colors.accent)
                        Text("Update Stop Info")
                            .font(AppTheme.Typography.sectionTitle())
                            .foregroundColor(.white)
                        Text("Help fellow drivers with real-time info")
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .padding(.top, AppTheme.Spacing.md)

                    // Report type grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CrowdsourceReport.ReportType.allCases, id: \.rawValue) { type in
                            Button(action: { selectedType = type }) {
                                HStack(spacing: 8) {
                                    Image(systemName: type.icon)
                                        .font(.system(size: 13, weight: .bold))
                                    Text(type.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundColor(selectedType == type ? .white : type.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedType == type ? type.color : type.color.opacity(0.12))
                                .cornerRadius(AppTheme.Radius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                        .stroke(selectedType == type ? Color.clear : type.color.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)

                    // Optional note
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ADD NOTE (OPTIONAL)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .kerning(1.1)
                            .padding(.horizontal, AppTheme.Spacing.md)

                        TextField("e.g. Diesel at pump 4 is $0.10 lower", text: $note)
                            .font(AppTheme.Typography.body())
                            .foregroundColor(.white)
                            .padding(12)
                            .background(AppTheme.Colors.backgroundInput)
                            .cornerRadius(AppTheme.Radius.md)
                            .padding(.horizontal, AppTheme.Spacing.md)
                    }

                    Spacer()

                    // Submit
                    Button(action: submit) {
                        HStack(spacing: 10) {
                            Image(systemName: "paperplane.fill")
                            Text("Submit Report")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.Colors.accent)
                        .cornerRadius(AppTheme.Radius.md)
                        .shadow(color: AppTheme.Colors.accent.opacity(0.4), radius: 8, y: 3)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.lg)
                }
            }
            .navigationTitle(stopName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let report = CrowdsourceReport(
            type: selectedType,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            reportedAt: Date()
        )
        onSubmit(report)
        dismiss()
    }
}

// MARK: - HOS Settings Sheet

struct HOSSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hos: HOSState

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                VStack(spacing: AppTheme.Spacing.lg) {
                    // Clock ring
                    ZStack {
                        Circle()
                            .stroke(AppTheme.Colors.backgroundCard, lineWidth: 12)
                            .frame(width: 120, height: 120)
                        Circle()
                            .trim(from: 0, to: hos.driveTimeRemainingHours / 11.0)
                            .stroke(hos.urgencyColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text(hos.driveTimeText)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            Text("remaining")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.top, AppTheme.Spacing.lg)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        // Drive time slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("DRIVE TIME LEFT")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                    .kerning(1.1)
                                Spacer()
                                Text(hos.driveTimeText)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(hos.urgencyColor)
                            }
                            Slider(value: $hos.driveTimeRemainingHours, in: 0...11, step: 0.5)
                                .accentColor(hos.urgencyColor)
                            HStack {
                                Text("0h").font(.system(size: 11)).foregroundColor(AppTheme.Colors.textSecondary)
                                Spacer()
                                Text("11h (legal max)").font(.system(size: 11)).foregroundColor(AppTheme.Colors.textSecondary)
                            }
                        }

                        Divider().background(AppTheme.Colors.backgroundCard)

                        // In break toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Currently in 30-min break")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Required after 8 hours of driving")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $hos.isInBreak)
                                .toggleStyle(SwitchToggleStyle(tint: AppTheme.Colors.success))
                        }

                        Divider().background(AppTheme.Colors.backgroundCard)

                        // Info card
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(AppTheme.Colors.accentSoft)
                                .font(.system(size: 16))
                            Text("FMCSA rules: 11h driving max, 14h on-duty window, 30-min break after 8h driving, 10h off-duty reset.")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .lineLimit(4)
                        }
                        .padding(10)
                        .background(AppTheme.Colors.accentSoft.opacity(0.08))
                        .cornerRadius(AppTheme.Radius.md)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)

                    Spacer()

                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.Colors.accent)
                            .cornerRadius(AppTheme.Radius.md)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.lg)
                }
            }
            .navigationTitle("Hours of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Scale Alert Banner (shown on map overlay when weigh station is ahead)

struct ScaleAlertBanner: View {
    enum ScaleStatus { case open, closed, unknown }

    let stationName: String
    let distanceMiles: Double
    let status: ScaleStatus
    let lang: AppLanguage
    let onDismiss: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(pulse ? 0.35 : 0.15))
                    .frame(width: 40, height: 40)
                    .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Distance + name — always in English (road safety)
                HStack(spacing: 5) {
                    Text(String(format: "%.1f mi", distanceMiles))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Text("—")
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .font(.system(size: 11))
                    Text(stationName)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                // Status in chosen language
                Text(statusLabel)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(statusColor)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(statusColor.opacity(0.4), lineWidth: 1.5)
        )
        .shadow(color: statusColor.opacity(0.2), radius: 8, y: 2)
        .onAppear { pulse = true }
    }

    private var statusColor: Color {
        switch status {
        case .open:    return AppTheme.Colors.danger    // open = trucks must stop
        case .closed:  return AppTheme.Colors.success   // closed = bypass
        case .unknown: return AppTheme.Colors.warning
        }
    }

    private var statusLabel: String {
        switch status {
        case .open:    return lang.scaleOpenLabel
        case .closed:  return lang.scaleClosedLabel
        case .unknown: return lang.scaleAheadLabel
        }
    }
}

// MARK: - Cheapest Diesel Banner (map overlay — highlights cheapest fuel nearby)

struct CheapestDieselBanner: View {
    let stop: TruckStopItem
    let lang: AppLanguage
    let onNavigate: () -> Void

    var body: some View {
        guard let price = stop.amenities.dieselPrice else { return AnyView(EmptyView()) }
        return AnyView(
            Button(action: onNavigate) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.Colors.accent.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: "fuelpump.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.Colors.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.cheapestNearbyLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .tracking(0.8)
                        HStack(spacing: 4) {
                            // Diesel price always shows $x.xxx format (universal)
                            Text(String(format: "$%.3f/gal", price))
                                .font(.system(size: 16, weight: .black, design: .monospaced))
                                .foregroundColor(AppTheme.Colors.accent)
                            Text("·")
                                .foregroundColor(AppTheme.Colors.textSecondary)
                            Text(stop.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Text(stop.distanceText + " away")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.Colors.backgroundCard)
                .cornerRadius(AppTheme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: AppTheme.Colors.accent.opacity(0.1), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        )
    }
}

struct DieselMarketBanner: View {
    let pricePoint: FuelPricePoint
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.accent.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.Colors.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("DIESEL MARKET")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .tracking(0.8)
                    Text(String(format: "$%.3f/gal", pricePoint.dieselPrice))
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text("\(pricePoint.sourceLabel) · \(pricePoint.locationLabel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rest Area Card (shown when .rest category is tapped)

struct RestAreaDetailCard: View {
    let name: String
    let distanceText: String
    let hasRestrooms: Bool
    let hasPicnicArea: Bool
    let hasVending: Bool
    let hasPetArea: Bool
    let lang: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundColor(AppTheme.Colors.accent)
                Text(name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(distanceText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.Colors.accent)
            }

            HStack(spacing: 12) {
                RestAreaAmenityChip(icon: "toilet.fill",   label: lang.categoryRest + " Area", active: true)
                RestAreaAmenityChip(icon: "fork.knife",    label: lang.categoryFood,            active: hasVending)
                RestAreaAmenityChip(icon: "tree.fill",     label: "Picnic",                     active: hasPicnicArea)
                RestAreaAmenityChip(icon: "pawprint.fill", label: "Pet Area",                   active: hasPetArea)
            }
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).stroke(AppTheme.Colors.accent.opacity(0.2), lineWidth: 1))
    }
}

struct RestAreaAmenityChip: View {
    let icon: String
    let label: String
    let active: Bool
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(active ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary.opacity(0.4))
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(active ? AppTheme.Colors.textPrimary.opacity(0.7) : AppTheme.Colors.textSecondary.opacity(0.3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shower Availability Widget (compact map card)

struct ShowerAvailabilityWidget: View {
    let stop: TruckStopItem
    let lang: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shower.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(showerColor)
                .frame(width: 34, height: 34)
                .background(showerColor.opacity(0.15))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(lang.categoryShower)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .tracking(0.8)
                if let count = stop.amenities.showerCount {
                    Text("\(count) showers")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                if let wait = stop.amenities.showerWaitMinutes {
                    Text(wait < 5 ? "Available now" : "~\(wait) min wait")
                        .font(.system(size: 11))
                        .foregroundColor(wait < 15 ? AppTheme.Colors.success : AppTheme.Colors.warning)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).stroke(showerColor.opacity(0.25), lineWidth: 1))
    }

    private var showerColor: Color {
        guard let wait = stop.amenities.showerWaitMinutes else { return AppTheme.Colors.accent }
        return wait < 15 ? AppTheme.Colors.success : AppTheme.Colors.warning
    }
}

// MARK: - Date extension for time-ago text

extension Date {
    var timeAgoText: String {
        let interval = -timeIntervalSinceNow
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

// MARK: - Route Stops Sidebar (left strip during navigation, like TruckerPath)

struct RouteStopsSidebar: View {
    let stops: [TruckStopItem]
    let onSelectStop: (TruckStopItem) -> Void

    /// Show up to 6 nearest stops
    private var displayedStops: [TruckStopItem] {
        Array(stops.prefix(6))
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(displayedStops) { stop in
                Button(action: { onSelectStop(stop) }) {
                    RouteStopSidebarRow(stop: stop)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RouteStopSidebarRow: View {
    let stop: TruckStopItem

    var body: some View {
        VStack(spacing: 3) {
            // Distance
            Text(stop.distanceText)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Brand circle with letter
            ZStack {
                Circle()
                    .fill(stop.network.brandColor)
                    .frame(width: 36, height: 36)
                    .shadow(color: stop.network.brandColor.opacity(0.6), radius: 4)
                Text(stop.network.shortLabel)
                    .font(.system(size: stop.network.shortLabel.count > 1 ? 11 : 15, weight: .black))
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(stop.network.brandColor.opacity(0.4), lineWidth: 1)
                )
        )
    }
}

// MARK: - Stop Review Sheet (driver rates a stop: service, showers, food)

struct StopReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let stop: TruckStopItem
    let onSubmit: (StopReview) -> Void

    @State private var serviceRating: Int = 0
    @State private var showerRating: Int = 0
    @State private var overallRating: Int = 0
    @State private var restaurantInput: String = ""
    @State private var notes: String = ""
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {

                        // Stop header
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(stop.network.brandColor)
                                    .frame(width: 48, height: 48)
                                Text(stop.network.shortLabel)
                                    .font(.system(size: stop.network.shortLabel.count > 1 ? 14 : 20, weight: .black))
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stop.name)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text(stop.network.tierLabel)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, AppTheme.Spacing.md)

                        Divider().background(AppTheme.Colors.backgroundCard)

                        // Service friendliness
                        ReviewRatingRow(
                            icon: "hand.thumbsup.fill",
                            color: Color(hex: "#10b981"),
                            title: "Atendimento",
                            subtitle: "Friendly service?",
                            rating: $serviceRating
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Shower cleanliness
                        ReviewRatingRow(
                            icon: "shower.fill",
                            color: Color(hex: "#6366f1"),
                            title: "Banheiros / Showers",
                            subtitle: "How clean were the showers?",
                            rating: $showerRating
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Overall
                        ReviewRatingRow(
                            icon: "star.fill",
                            color: Color(hex: "#f59e0b"),
                            title: "Geral / Overall",
                            subtitle: "How was the stop overall?",
                            rating: $overallRating
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)

                        Divider().background(AppTheme.Colors.backgroundCard)

                        // Restaurants
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Restaurantes / Food", systemImage: "fork.knife")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text("Which restaurants are here?")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.Colors.textSecondary)

                            // Quick-tap common names
                            let common = ["Denny's", "Subway", "Arby's", "McDonald's", "Pizza Hut", "Taco Bell", "Cinnabon", "Popeyes"]
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(common, id: \.self) { name in
                                    let selected = restaurantInput.contains(name)
                                    Button(action: {
                                        if selected {
                                            restaurantInput = restaurantInput
                                                .replacingOccurrences(of: name + ", ", with: "")
                                                .replacingOccurrences(of: ", " + name, with: "")
                                                .replacingOccurrences(of: name, with: "")
                                        } else {
                                            restaurantInput = restaurantInput.isEmpty ? name : restaurantInput + ", " + name
                                        }
                                    }) {
                                        Text(name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(selected ? .white : AppTheme.Colors.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(selected ? Color(hex: "#f59e0b").opacity(0.8) : AppTheme.Colors.backgroundCard)
                                            .cornerRadius(8)
                                    }
                                }
                            }

                            TextField("Other restaurants...", text: $restaurantInput)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(AppTheme.Colors.backgroundInput)
                                .cornerRadius(AppTheme.Radius.sm)
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Notes / Observações", systemImage: "pencil")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            TextField("Anything else drivers should know?", text: $notes, axis: .vertical)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .lineLimit(3, reservesSpace: true)
                                .padding(10)
                                .background(AppTheme.Colors.backgroundInput)
                                .cornerRadius(AppTheme.Radius.sm)
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Submit
                        Button(action: submit) {
                            HStack(spacing: 10) {
                                Image(systemName: submitted ? "checkmark.circle.fill" : "paperplane.fill")
                                Text(submitted ? "Enviado!" : "Submit Review")
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(submitted ? AppTheme.Colors.success : AppTheme.Colors.accent)
                            .cornerRadius(AppTheme.Radius.md)
                        }
                        .disabled(submitted || (serviceRating == 0 && showerRating == 0 && overallRating == 0))
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.bottom, AppTheme.Spacing.xl)
                    }
                }
            }
            .navigationTitle("Rate This Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let review = StopReview(
            stopId: stop.id,
            stopName: stop.name,
            serviceRating: serviceRating,
            showerRating: showerRating,
            overallRating: overallRating,
            restaurants: restaurantInput.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSubmit(review)
        submitted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }
}

// MARK: - Star Rating Row

private struct ReviewRatingRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
            // Star buttons
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Button(action: { rating = star }) {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 20))
                            .foregroundColor(star <= rating ? Color(hex: "#f59e0b") : AppTheme.Colors.backgroundCard)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }
}

// MARK: - Facility Review (pickup / delivery company rating)

enum FacilityReviewType {
    case pickup, delivery

    var titleLabel: String {
        self == .pickup ? "Avaliação — Carregamento" : "Avaliação — Entrega"
    }
    var subtitle: String {
        self == .pickup ? "Como foi o carregamento?" : "Como foi a entrega?"
    }
    var icon: String {
        self == .pickup ? "arrow.up.circle.fill" : "checkmark.circle.fill"
    }
    var color: Color {
        self == .pickup ? Color(hex: "#f59e0b") : Color(hex: "#10b981")
    }
}

struct FacilityReview {
    let loadNumber: String
    let companyName: String?
    let type: FacilityReviewType
    let treatmentRating: Int    // atendimento da empresa (1–5)
    let safetyRating: Int       // segurança do local (1–5)
    let accessRating: Int       // facilidade de acesso (1–5)
    let waitMinutes: Int?       // espera em minutos
    let notes: String
    let submittedAt: Date = Date()
}

struct FacilityReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let load: DispatchedLoad
    let type: FacilityReviewType
    let onSubmit: (FacilityReview) -> Void
    let onSkip: () -> Void

    @State private var treatmentRating: Int = 0
    @State private var safetyRating: Int = 0
    @State private var accessRating: Int = 0
    @State private var waitText: String = ""
    @State private var notes: String = ""
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {

                        // Header badge
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(type.color.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                Image(systemName: type.icon)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(type.color)
                            }
                            Text(type.titleLabel)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            if let company = load.companyName {
                                Text(company)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            Text("Carga #\(load.loadNumber)")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                        .padding(.top, AppTheme.Spacing.lg)

                        Divider().background(AppTheme.Colors.backgroundCard)

                        // Atendimento / Service
                        ReviewRatingRow(
                            icon: "person.2.fill",
                            color: type.color,
                            title: "Atendimento da Empresa",
                            subtitle: "The company treated you well?",
                            rating: $treatmentRating
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Segurança / Safety
                        ReviewRatingRow(
                            icon: "shield.fill",
                            color: Color(hex: "#6366f1"),
                            title: "Segurança do Local",
                            subtitle: "Was the facility safe?",
                            rating: $safetyRating
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Acesso / Access
                        ReviewRatingRow(
                            icon: "truck.box.badge.clock.fill",
                            color: Color(hex: "#0ea5e9"),
                            title: "Facilidade de Acesso",
                            subtitle: "Easy access for your truck?",
                            rating: $accessRating
                        )
                        .padding(.horizontal, AppTheme.Spacing.md)

                        Divider().background(AppTheme.Colors.backgroundCard)

                        // Wait time
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Tempo de Espera (minutos)", systemImage: "clock")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            HStack(spacing: 10) {
                                // Quick-tap chips
                                ForEach(["0", "15", "30", "60", "120"], id: \.self) { val in
                                    Button(action: { waitText = val }) {
                                        Text(val == "0" ? "Sem espera" : "\(val) min")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(waitText == val ? .white : AppTheme.Colors.textSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(waitText == val ? Color(hex: "#0ea5e9").opacity(0.8) : AppTheme.Colors.backgroundCard)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            TextField("Outro valor...", text: $waitText)
                                .keyboardType(.numberPad)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(AppTheme.Colors.backgroundInput)
                                .cornerRadius(AppTheme.Radius.sm)
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Notes
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Observações", systemImage: "pencil")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            TextField("Algo que outros motoristas devem saber...", text: $notes, axis: .vertical)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .lineLimit(3, reservesSpace: true)
                                .padding(10)
                                .background(AppTheme.Colors.backgroundInput)
                                .cornerRadius(AppTheme.Radius.sm)
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // Buttons
                        VStack(spacing: 10) {
                            Button(action: submit) {
                                HStack(spacing: 10) {
                                    Image(systemName: submitted ? "checkmark.circle.fill" : "paperplane.fill")
                                    Text(submitted ? "Enviado!" : "Enviar Avaliação")
                                        .font(.system(size: 17, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(submitted ? AppTheme.Colors.success : type.color)
                                .cornerRadius(AppTheme.Radius.md)
                            }
                            .disabled(submitted)

                            Button(action: {
                                onSkip()
                                dismiss()
                            }) {
                                Text("Pular / Skip")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.bottom, AppTheme.Spacing.xl)
                    }
                }
            }
            .navigationTitle(type.subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") {
                        onSkip()
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        let review = FacilityReview(
            loadNumber: load.loadNumber,
            companyName: load.companyName,
            type: type,
            treatmentRating: treatmentRating,
            safetyRating: safetyRating,
            accessRating: accessRating,
            waitMinutes: Int(waitText),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSubmit(review)
        submitted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}

// MARK: - Stop Review Model

struct StopReview {
    let stopId: UUID
    let stopName: String
    let serviceRating: Int      // 0 = not rated, 1-5
    let showerRating: Int
    let overallRating: Int
    let restaurants: String
    let notes: String
    let submittedAt: Date = Date()
}

// MARK: - Preview

#Preview {
    let sampleStop = TruckStopItem(
        name: "Pilot Travel Center",
        address: "1234 Interstate Dr, Nashville, TN 37201",
        coordinate: CLLocationCoordinate2D(latitude: 36.1627, longitude: -86.7816),
        distanceMeters: 24140,
        phone: "(615) 555-0182",
        network: .pilotFlyingJ,
        amenities: TruckStopAmenities(
            rating: 4.2, reviewCount: 318,
            parkingSlots: 120, parkingAvailable: 34, hasReservableParking: true,
            parkingUpdatedAt: Date(timeIntervalSinceNow: -900),
            showerCount: 20, showerWaitMinutes: 8, hasLaundry: true, hasLounge: true, hasWifi: true,
            foodType: .fastFood, hasHealthyOptions: false,
            restaurantNames: ["Arby's", "Subway", "Cinnabon"],
            hasCATScale: true, hasTireService: false, hasMechanic: false,
            hasDEF: true, defPrice: 2.499, defUpdatedAt: Date(timeIntervalSinceNow: -3600),
            dieselPrice: 3.789, dieselUpdatedAt: Date(timeIntervalSinceNow: -1800),
            acceptsTruckCard: true
        )
    )

    TruckStopDetailSheet(
        stop: sampleStop,
        hos: HOSState.mock,
        onNavigate: { _ in }
    )
}
