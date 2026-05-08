// HorizonIdleOverlays.swift — TopHUD, map controls, category sidebar, map-level UI
// Components visible when the driver is NOT actively navigating.

import SwiftUI
import MapKit

// MARK: - Top HUD

struct HorizonTopHUD: View {
    let activeTrip: Trip?
    let regionalSettings: RegionalSettingsManager
    @Binding var truckProfile: TruckProfile
    let truckWarnings: [TruckRestrictionWarning]
    @Binding var showingTruckSettings: Bool
    @Binding var selectedMapStyle: MapStyleOption
    let onReportAlert: (MapAlert.AlertType) -> Void
    @Binding var showingTruckStops: Bool
    let locationManager: LocationManager
    let truckStopService: TruckStopService
    @Binding var selectedNearbyCategory: NearbyCategory?
    @Binding var showingHOSSettings: Bool
    @Binding var showingGlobalSearch: Bool
    @Binding var showingWeighStation: Bool
    var voiceManager: VoiceNavigationManager = .shared

    var body: some View {
        HStack(alignment: .top) {
            VStack(spacing: 8) {
                Menu {
                    ForEach(MapStyleOption.allCases, id: \.self) { style in
                        Button(style.rawValue) { selectedMapStyle = style }
                    }
                } label: {
                    hudButton(icon: "map.fill")
                }

                Menu {
                    ForEach(MapAlert.AlertType.allCases, id: \.self) { type in
                        Button { onReportAlert(type) } label: {
                            Label(type.rawValue, systemImage: type.icon)
                        }
                    }
                } label: {
                    hudButton(icon: "exclamationmark.triangle.fill", tint: AppTheme.Colors.warning)
                }

                Button(action: { voiceManager.isEnabled.toggle() }) {
                    hudButton(
                        icon: voiceManager.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        tint: voiceManager.isEnabled ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary
                    )
                }
                .accessibilityLabel(
                    voiceManager.isEnabled
                    ? regionalSettings.lang.voiceNavOnLabel
                    : regionalSettings.lang.voiceNavOffLabel
                )
            }
            .padding(.leading, AppTheme.Spacing.md)
            .padding(.top, 56)

            Spacer()
        }
    }

    @ViewBuilder
    private func hudButton(icon: String, tint: Color? = nil) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(tint ?? .white)
            .frame(width: 38, height: 38)
            .background(Color(hex: "#1a1d23"))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

// MARK: - Map Controls Panel

struct HorizonMapControlsPanel: View {
    let onZoomIn:   () -> Void
    let onZoomOut:  () -> Void
    let onRecenter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            mapControlButton(icon: "plus", action: onZoomIn)
            Divider().frame(width: 44).background(Color.white.opacity(0.1))
            mapControlButton(icon: "minus", action: onZoomOut)
            Divider().frame(width: 44).background(Color.white.opacity(0.1)).padding(.vertical, 2)
            mapControlButton(icon: "location.fill", action: onRecenter, isAccent: true)
        }
        .background(Color(hex: "#1a1d23"))
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func mapControlButton(icon: String, action: @escaping () -> Void, isAccent: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isAccent ? Color(hex: "#c9a84c") : .white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Sidebar

struct HorizonCategorySidebar: View {
    let categories: [NearbyCategory]
    let lang: AppLanguage
    let onSelect: (NearbyCategory) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(categories, id: \.self) { cat in
                Button(action: { onSelect(cat) }) {
                    VStack(spacing: 3) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(cat.color)
                        Text(cat.sidebarLabel(for: lang))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(AppTheme.Colors.textPrimary.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(width: 44, height: 44)
                    .background(AppTheme.Colors.backgroundCard)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(cat.color.opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                }
            }
        }
    }
}

// MARK: - Nearby Stops Panel

struct HorizonNearbyStopsPanel: View {
    let category: NearbyCategory
    let items: [NearbyStopItem]
    let truckStops: [TruckStopItem]
    let isLoading: Bool
    let onClose: () -> Void
    let onSelect: (NearbyStopItem) -> Void
    var lang: AppLanguage = .english
    @State private var favoriteKeys: Set<String> = []
    private static let favoritesStorageKey = "nearby.stop.favorites.v1"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(category.color)
                Text(category.label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .padding(14)

            Divider().background(AppTheme.Colors.textSecondary.opacity(0.2))

            if isLoading {
                ProgressView()
                    .tint(AppTheme.Colors.accent)
                    .padding(20)
            } else if items.isEmpty {
                Text(lang.noResultsNearby)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            nearbyRow(item)
                            Divider().background(AppTheme.Colors.textSecondary.opacity(0.1)).padding(.leading, 14)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .shadow(color: .black.opacity(0.4), radius: 12)
        .onAppear { loadFavorites() }
    }

    @ViewBuilder
    private func nearbyRow(_ item: NearbyStopItem) -> some View {
        let signal = signalForItem(item)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let score = signal.communityRating {
                        Label(String(format: "%.1f", score), systemImage: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#fbbf24"))
                    }
                }
                Text(item.address)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let parking = signal.parkingLabel {
                        Label(parking, systemImage: signal.parkingIcon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(signal.parkingColor)
                            .lineLimit(1)
                    }
                    if let wellness = signal.wellnessLabel {
                        Label(wellness, systemImage: "leaf.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "#34d399"))
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(item.distanceText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(category.color)
                Button {
                    toggleFavorite(item)
                } label: {
                    Image(systemName: isFavorite(item) ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isFavorite(item) ? Color(hex: "#ef4444") : AppTheme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.Colors.backgroundInput)
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(item) }
    }

    private func signalForItem(_ item: NearbyStopItem) -> (
        parkingLabel: String?, parkingIcon: String, parkingColor: Color,
        communityRating: Double?, wellnessLabel: String?
    ) {
        guard let match = closestTruckStop(to: item) else {
            let wellnessFallback: String? = {
                if item.category == .healthy { return "Wellness stop" }
                if item.category == .rest { return "Rest recovery" }
                return nil
            }()
            return (
                parkingLabel: item.category == .parking ? "Parking signal unavailable" : nil,
                parkingIcon: "questionmark.circle.fill",
                parkingColor: AppTheme.Colors.textSecondary,
                communityRating: nil,
                wellnessLabel: wellnessFallback
            )
        }
        let parkingStatus = match.amenities.parkingStatus
        let rating = match.amenities.rating
        let wellnessLabel = match.wellnessScore >= 70 ? "Driver wellness friendly" : nil
        return (
            parkingLabel: parkingStatus.label,
            parkingIcon: parkingStatus.icon,
            parkingColor: parkingStatus.color,
            communityRating: rating,
            wellnessLabel: wellnessLabel
        )
    }

    private func closestTruckStop(to item: NearbyStopItem) -> TruckStopItem? {
        let itemLocation = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
        return truckStops
            .map { stop in
                let stopLocation = CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude)
                return (stop, itemLocation.distance(from: stopLocation))
            }
            .filter { $0.1 <= 2_000 }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }

    private func key(for item: NearbyStopItem) -> String {
        let lat = String(format: "%.4f", item.coordinate.latitude)
        let lon = String(format: "%.4f", item.coordinate.longitude)
        return "\(item.category.rawValue)|\(item.name.lowercased())|\(lat)|\(lon)"
    }

    private func isFavorite(_ item: NearbyStopItem) -> Bool {
        favoriteKeys.contains(key(for: item))
    }

    private func toggleFavorite(_ item: NearbyStopItem) {
        let itemKey = key(for: item)
        if favoriteKeys.contains(itemKey) {
            favoriteKeys.remove(itemKey)
        } else {
            favoriteKeys.insert(itemKey)
        }
        saveFavorites()
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: Self.favoritesStorageKey),
              let keys = try? JSONDecoder().decode([String].self, from: data) else { return }
        favoriteKeys = Set(keys)
    }

    private func saveFavorites() {
        let keys = Array(favoriteKeys)
        guard let data = try? JSONEncoder().encode(keys) else { return }
        UserDefaults.standard.set(data, forKey: Self.favoritesStorageKey)
    }
}

// MARK: - HealthKit Manager

#if canImport(HealthKit)
import HealthKit
final class HealthKitManager {
    static var shared: HealthKitManager? = nil
    private let healthStore = HKHealthStore()

    func requestAuthorization() {
        var readTypes = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            readTypes.insert(steps)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleep)
        }
        guard !readTypes.isEmpty else { return }
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { _, _ in }
    }

    func fetchTodaySteps(completion: @escaping (Int) -> Void) {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            completion(0); return
        }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let query = HKSampleQuery(
            sampleType: stepType, predicate: predicate,
            limit: HKObjectQueryNoLimit, sortDescriptors: nil
        ) { _, samples, _ in
            let steps = (samples as? [HKQuantitySample])?.reduce(0) { sum, s in
                sum + Int(s.quantity.doubleValue(for: .count()))
            } ?? 0
            DispatchQueue.main.async { completion(steps) }
        }
        healthStore.execute(query)
    }

    func fetchLastNightSleep(completion: @escaping (Double) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(0); return
        }
        let now = Date()
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        guard
            let windowStart = cal.date(byAdding: .hour, value: -14, to: startOfToday),
            let windowEnd   = cal.date(byAdding: .hour, value: 10,  to: startOfToday)
        else { completion(0); return }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            let totalSeconds = (samples as? [HKCategorySample])?.filter {
                $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
            }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
            let hours = totalSeconds / 3600
            DispatchQueue.main.async { completion(hours) }
        }
        healthStore.execute(query)
    }
}
#endif
