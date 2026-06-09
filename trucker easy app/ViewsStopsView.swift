import SwiftUI
import MapKit
import CoreLocation

// MARK: - Stop Item Model

struct StopItem: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let distanceMiles: Double
    let category: StopCategory
    let availability: StopAvailability
    let rating: Double?
    let reviewCount: Int
    let coordinate: CLLocationCoordinate2D

    enum StopAvailability {
        case available, limited, full, open, closed, unknown

        var label: String {
            switch self {
            case .available: return "Available"
            case .limited:   return "Limited"
            case .full:      return "Full"
            case .open:      return "Open"
            case .closed:    return "Closed"
            case .unknown:   return ""
            }
        }
        var color: Color {
            switch self {
            case .available, .open: return Color(hex: "#10b981")
            case .limited:          return Color(hex: "#f59e0b")
            case .full, .closed:    return Color(hex: "#ef4444")
            case .unknown:          return Color.clear
            }
        }
    }

    enum StopCategory: String, CaseIterable {
        case nearMe       = "Near Me"
        case truckStops   = "Truck Stops"
        case weighStations = "Weigh Stations"
        case restAreas    = "Rest Areas"
        case restaurants  = "Restaurants"
        case parking      = "Parking"

        var icon: String {
            switch self {
            case .nearMe:        return "location.fill"
            case .truckStops:    return "fuelpump.fill"
            case .weighStations: return "scalemass.fill"
            case .restAreas:     return "bed.double.fill"
            case .restaurants:   return "fork.knife"
            case .parking:       return "p.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .nearMe:        return Color(hex: "#00d4c8")
            case .truckStops:    return Color(hex: "#f59e0b")
            case .weighStations: return Color(hex: "#ef4444")
            case .restAreas:     return Color(hex: "#8b5cf6")
            case .restaurants:   return Color(hex: "#10b981")
            case .parking:       return Color(hex: "#6366f1")
            }
        }
        var searchQuery: String {
            switch self {
            case .nearMe:        return "truck stop fuel"
            case .truckStops:    return "Loves Pilot Flying J TA Petro truck stop travel center"
            case .weighStations: return "weigh station"
            case .restAreas:     return "rest area highway interstate rest stop"
            case .restaurants:   return "restaurant diner"
            case .parking:       return "truck parking"
            }
        }
    }
}

// MARK: - Stops View

struct StopsView: View {
    @State private var locationManager = LocationManager()
    @State private var selectedCategory: StopItem.StopCategory = .nearMe
    @State private var stops: [StopItem] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedStop: StopItem? = nil
    @State private var parkingFullNames: Set<String> = []

    private let weighStationService = WeighStationStatusService.shared
    private let categories: [StopItem.StopCategory] = [.nearMe, .truckStops, .weighStations, .restAreas, .restaurants, .parking]

    var filteredStops: [StopItem] {
        if searchText.isEmpty { return stops }
        return stops.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.address.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#000d1a").ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────
                headerBar

                // ── Category Filter Tabs ──────────────────────────────────
                categoryTabs
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // ── Search ────────────────────────────────────────────────
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                // ── List ──────────────────────────────────────────────────
                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(Color(hex: "#00d4c8"))
                        .te_uniformScale(1.2)
                    Spacer()
                } else if filteredStops.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredStops) { stop in
                                StopRow(stop: stop)
                                    .onTapGesture { selectedStop = stop }
                                    .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.bottom, 80)
                    }
                }
            }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startTracking()
            loadStops()
            Task { await weighStationService.fetchRemoteReports() }
            Task { await loadParkingFullReports() }
        }
        .onChange(of: selectedCategory) { _, _ in loadStops() }
        .sheet(item: $selectedStop) { stop in
            StopDetailSheet(stop: stop)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stops")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(.white)
                if let loc = locationManager.currentLocation {
                    Text(String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#00d4c8").opacity(0.7))
                } else {
                    Text("Locating…")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#00d4c8").opacity(0.5))
                }
            }
            Spacer()
            Button(action: loadStops) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Refresh")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#00d4c8"))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(hex: "#00d4c8").opacity(0.12))
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 8)
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Button(action: { selectedCategory = cat }) {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(cat.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(selectedCategory == cat ? .black : cat.color)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedCategory == cat ? cat.color : cat.color.opacity(0.12))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selectedCategory == cat ? Color.clear : cat.color.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.4))
            TextField("Search facilities...", text: $searchText)
                .font(.system(size: 14))
                .foregroundColor(.white)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: selectedCategory.icon)
                .font(.system(size: 48))
                .foregroundColor(selectedCategory.color.opacity(0.4))
            Text("No \(selectedCategory.rawValue) Found")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Text("Allow location access and refresh to see nearby stops")
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Load Stops

    private func loadStops() {
        guard let location = locationManager.currentLocation else {
            // Try again after brief delay if location not yet available
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { loadStops() }
            return
        }
        isLoading = true
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = selectedCategory.searchQuery
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
            )
            let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
            await MainActor.run {
                stops = items.prefix(20).compactMap { item in
                    let coord: CLLocationCoordinate2D
                    let addr: String
                    if #available(iOS 26, *) {
                        coord = item.location.coordinate
                        let addrParts = [item.addressRepresentations?.cityName, item.addressRepresentations?.regionName]
                            .compactMap { $0 }.filter { !$0.isEmpty }
                        addr = addrParts.isEmpty
                            ? (item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true) ?? "")
                            : addrParts.joined(separator: ", ")
                    } else {
                        coord = item.placemark.coordinate
                        let addrParts = [item.placemark.thoroughfare, item.placemark.locality, item.placemark.administrativeArea]
                            .compactMap { $0 }.filter { !$0.isEmpty }
                        addr = addrParts.isEmpty ? (item.placemark.title ?? "") : addrParts.joined(separator: ", ")
                    }
                    let itemLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let distMeters = location.distance(from: itemLoc)
                    let distMi = distMeters / 1609.34

                    // Availability: real data for scales and parking, default for others
                    let avail: StopItem.StopAvailability
                    let itemName = item.name ?? "Unknown"
                    switch selectedCategory {
                    case .weighStations:
                        switch weighStationService.latestStatus(for: itemName, near: coord) {
                        case .open:       avail = .open
                        case .closed:     avail = .closed
                        case .monitoring: avail = .limited
                        case nil:         avail = .unknown
                        }
                    case .parking:
                        avail = parkingFullNames.contains(itemName) ? .full : .available
                    default:
                        avail = .available
                    }
                    return StopItem(
                        name: item.name ?? "Unknown",
                        address: addr,
                        distanceMiles: distMi,
                        category: selectedCategory,
                        availability: avail,
                        rating: nil,
                        reviewCount: 0,
                        coordinate: coord
                    )
                }
                .sorted { $0.distanceMiles < $1.distanceMiles }
                isLoading = false
            }
        }
    }

    // Fetch recent parkingFull reports and store location names
    private func loadParkingFullReports() async {
        guard let loc = locationManager.currentLocation else { return }
        let reports = (try? await SupabaseClient.shared.fetchRecentRoadReports(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            radiusKm: 80
        )) ?? []
        let cutoff = Date().addingTimeInterval(-3600 * 4) // ignore reports older than 4h
        let fullNames = Set(reports.compactMap { r -> String? in
            guard r.report_type == "parkingFull",
                  let name = r.location_name,
                  (ISO8601DateFormatter().date(from: r.reported_at) ?? .distantPast) > cutoff
            else { return nil }
            return name
        })
        await MainActor.run { parkingFullNames = fullNames }
    }
}

// MARK: - Stop Row

private struct StopRow: View {
    let stop: StopItem

    var body: some View {
        HStack(spacing: 14) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(stop.category.color.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: stop.category.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(stop.category.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(stop.address)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    // Distance
                    Text(String(format: "%.1f mi", stop.distanceMiles))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#00d4c8"))

                    // Availability dot
                    if stop.availability != .unknown {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stop.availability.color)
                                .frame(width: 6, height: 6)
                            Text(stop.availability.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(stop.availability.color)
                        }
                    }

                    // Star rating
                    if let rating = stop.rating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#f59e0b"))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#f59e0b"))
                            Text("(\(stop.reviewCount))")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.25))
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Stop Detail Sheet

struct StopDetailSheet: View {
    let stop: StopItem
    @Environment(\.dismiss) private var dismiss
    @State private var showingRoute = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0d1117").ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header card
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(stop.category.color.opacity(0.15))
                                    .frame(width: 70, height: 70)
                                Image(systemName: stop.category.icon)
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(stop.category.color)
                            }

                            Text(stop.name)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text(stop.address)
                                .font(.system(size: 13))
                                .foregroundColor(Color.white.opacity(0.55))
                                .multilineTextAlignment(.center)

                            // Stats row
                            HStack(spacing: 24) {
                                statPill(value: String(format: "%.1f mi", stop.distanceMiles), label: "Distance", color: Color(hex: "#00d4c8"))
                                if stop.availability != .unknown {
                                    statPill(value: stop.availability.label, label: "Status", color: stop.availability.color)
                                }
                                if let rating = stop.rating {
                                    statPill(value: String(format: "%.1f ★", rating), label: "Rating", color: Color(hex: "#f59e0b"))
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(16)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        // Navigate button
                        Button(action: { dismiss() }) {
                            HStack(spacing: 10) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Navigate")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "#00d4c8"))
                            .cornerRadius(14)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        Spacer(minLength: 32)
                    }
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .topTrailing) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Color.white.opacity(0.3))
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.45))
        }
    }
}

// MARK: - Double rounding helper

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
