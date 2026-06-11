// HorizonNavigationOverlays.swift — Step banner, ETA bar, route steps, arrival card
// Navigation-specific overlays shown during active route following.

import SwiftUI
import MapKit

// MARK: - Shared maneuver icon (banner + “Then” strip)

enum NavigationManeuverIcon {
    static func symbol(for instructions: String) -> String {
        let t = instructions.lowercased()
        if t.contains("u-turn") || t.contains("u turn") { return "arrow.uturn.left" }
        if t.contains("turn left sharply") || t.contains("sharp left") { return "arrow.turn.up.left" }
        if t.contains("turn right sharply") || t.contains("sharp right") { return "arrow.turn.up.right" }
        if t.contains("turn left") || t.contains("left turn") || t.contains("bear left") || t.contains("keep left") || t.contains("slight left") { return "arrow.turn.down.left" }
        if t.contains("turn right") || t.contains("right turn") || t.contains("bear right") || t.contains("keep right") || t.contains("slight right") { return "arrow.turn.down.right" }
        if t.contains("roundabout") || t.contains("rotary") || t.contains("traffic circle") { return "arrow.clockwise.circle" }
        if t.contains("merge") || t.contains("ramp") || t.contains("highway") { return "arrow.merge" }
        if t.contains("exit") { return "arrow.up.right.circle" }
        if t.contains("arrive") || t.contains("destination") || t.contains("reached") { return "mappin.circle.fill" }
        if t.contains("ferry") { return "ferry.fill" }
        return "arrow.up"
    }
}

// MARK: - Navigation Step Banner

struct HorizonNavigationStepBanner: View {
    let step: DisplayRouteStep
    let stepIndex: Int
    let totalSteps: Int
    let formatDistance: (Double) -> String
    var nextStepInstruction: String? = nil
    let onPrevStep: () -> Void
    let onNextStep: () -> Void
    let onToggleList: () -> Void
    /// Microfone / IA no banner de manobra (opcional — UI limpa em navegação).
    var onMicTap: (() -> Void)? = nil
    var speedText: String? = nil

    private var bannerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: 16,
                bottomTrailing: 16,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    private var maneuverLabel: String {
        let t = step.instructions.lowercased()
        if t.contains("stay on") || t.contains("continue") { return "Stay on" }
        if t.contains("turn left") || t.contains("bear left") || t.contains("keep left") { return "Turn left" }
        if t.contains("turn right") || t.contains("bear right") || t.contains("keep right") { return "Turn right" }
        if t.contains("u-turn") || t.contains("u turn") { return "U-turn" }
        if t.contains("merge") { return "Merge onto" }
        if t.contains("exit") { return "Take exit" }
        if t.contains("ramp") { return "Take ramp" }
        if t.contains("roundabout") { return "Roundabout" }
        if t.contains("arrive") || t.contains("destination") { return "Arrive at" }
        return "Head to"
    }

    private var mainStreetName: String {
        let raw = step.instructions
        let lower = raw.lowercased()
        for keyword in [" onto ", " on ", " para ", " to "] {
            if let range = lower.range(of: keyword) {
                return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return raw
    }

    private var nextRoadNumber: String? {
        let name = mainStreetName
        let patterns = ["I-", "US-", "SR-", "Hwy ", "Route "]
        for p in patterns {
            if name.lowercased().hasPrefix(p.lowercased()) { return name }
        }
        if name.first?.isNumber == true { return name }
        return nil
    }

    private var formattedDistance: String {
        step.distance > 0 ? formatDistance(step.distance) : ""
    }

    private var maneuverIcon: String {
        NavigationManeuverIcon.symbol(for: step.instructions)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
            // Large maneuver arrow (competitor-style prominence)
            Image(systemName: maneuverIcon)
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())

            // Distance first, then street — matches common truck nav / competitor hierarchy
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formattedDistance.isEmpty ? "—" : formattedDistance)
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    if let road = nextRoadNumber {
                        Text(road)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(GPSDesignSystem.Colors.textPrimary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(GPSDesignSystem.Colors.routeActive)
                            .clipShape(RoundedRectangle(cornerRadius: GPSDesignSystem.Metrics.cornerMedium, style: .continuous))
                    }
                }

                Text(mainStreetName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(maneuverLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            // Mic + list in one horizontal row — avoids vertical icon stacking / overlap
            HStack(spacing: 10) {
                if let onMicTap {
                    Button(action: onMicTap) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onToggleList) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.Colors.accent)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Route steps")
            }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: GPSDesignSystem.Metrics.navHeaderHeight, alignment: .leading)
        }
        .background(bannerShape.fill(GPSDesignSystem.Colors.chromeBackground.opacity(0.96)))
        .overlay(bannerShape.stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        .zIndex(500)
    }
}

// MARK: - Navigation Info Strip

struct HorizonNavigationInfoStrip: View {
    let stops: [TruckStopItem]
    let scaleAlertName: String
    let scaleAlertDistanceMiles: Double
    let scaleAlertStatus: ScaleAlertBanner.ScaleStatus
    let hasScaleAhead: Bool
    let onSelectStop: (TruckStopItem) -> Void
    var useMiles: Bool = true
    /// Limita cartões na coluna direita para não empilhar sobre zoom/ETA.
    var maxCards: Int = 2

    private var nearestFuelStop: TruckStopItem? {
        stops.min(by: { $0.distanceMeters < $1.distanceMeters })
    }

    private var nearestReeferStop: TruckStopItem? {
        let withDEF = stops.filter { $0.amenities.hasDEF }
        return withDEF.min(by: { $0.distanceMeters < $1.distanceMeters })
    }

    var body: some View {
        VStack(spacing: 8) {
            if maxCards >= 1, let fuel = nearestFuelStop {
                Button(action: { onSelectStop(fuel) }) {
                    NavInfoCard(
                        icon: "fuelpump.fill",
                        color: Color(hex: "#f59e0b"),
                        topLine: fuelTopLine(for: fuel),
                        bottomLine: distText(fuel.distanceMeters)
                    )
                }
                .buttonStyle(.plain)
            }

            if maxCards >= 2 {
                NavInfoCard(
                    icon: "scalemass.fill",
                    color: scaleColor,
                    topLine: hasScaleAhead ? String(format: "%.1f mi", scaleAlertDistanceMiles) : "–",
                    bottomLine: hasScaleAhead ? scaleStatusLabel : "Scale"
                )
            }

            if maxCards >= 3, let reefer = nearestReeferStop {
                Button(action: { onSelectStop(reefer) }) {
                    NavInfoCard(
                        icon: "snowflake",
                        color: Color(hex: "#38bdf8"),
                        topLine: reefer.network.shortLabel,
                        bottomLine: distText(reefer.distanceMeters)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func distText(_ meters: Double) -> String {
        if useMiles {
            if meters < 1609 { return String(format: "%.0f ft", meters * 3.28084) }
            return String(format: "%.1f mi", meters / 1609.34)
        } else {
            if meters < 1000 { return String(format: "%.0f m", meters) }
            return String(format: "%.1f km", meters / 1000)
        }
    }

    private func fuelTopLine(for stop: TruckStopItem) -> String {
        if let price = stop.amenities.dieselPrice {
            return String(format: "$%.3f", price)
        }
        return stop.network.shortLabel
    }

    private var scaleColor: Color {
        switch scaleAlertStatus {
        case .open:       return Color(hex: "#ef4444")
        case .closed:     return Color(hex: "#22d474")
        case .monitoring: return Color(hex: "#f59e0b")
        case .unknown:    return AppTheme.Colors.textSecondary
        }
    }

    private var scaleStatusLabel: String {
        switch scaleAlertStatus {
        case .open:       return "OPEN"
        case .closed:     return "CLOSED"
        case .monitoring: return "MONITOR"
        case .unknown:    return "AHEAD"
        }
    }
}

// MARK: - Nav Info Card

struct NavInfoCard: View {
    let icon: String
    let color: Color
    let topLine: String
    let bottomLine: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(color)
                .frame(height: 20)
            Text(topLine)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(bottomLine)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .frame(width: 64)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Color(hex: "#1a1d23"))
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(color.opacity(0.35), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
    }
}

// MARK: - Route Steps List

struct HorizonRouteStepsList: View {
    let steps: [DisplayRouteStep]
    let currentIndex: Int
    let formatDistance: (Double) -> String
    let onSelect: (Int) -> Void
    let onClose: () -> Void
    var lang: AppLanguage = .english

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(lang.routeStepsLabel)
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

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                        Button(action: { onSelect(idx) }) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(idx == currentIndex ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                Text(step.instructions)
                                    .font(.system(size: 13))
                                    .foregroundColor(idx == currentIndex ? .white : AppTheme.Colors.textSecondary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Text(formatDistance(step.distance))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        Divider().background(AppTheme.Colors.textSecondary.opacity(0.1)).padding(.leading, 32)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .background(AppTheme.Colors.backgroundCard.opacity(0.97))
        .cornerRadius(AppTheme.Radius.md)
        .shadow(color: .black.opacity(0.4), radius: 12)
    }
}

// MARK: - Voice Navigation ViewModifier

struct VoiceNavigationModifier: ViewModifier {
    let voiceManager: VoiceNavigationManager
    let lang: AppLanguage
    let currentStepIndex: Int
    let routeSteps: [DisplayRouteStep]
    let isNavigating: Bool
    let truckRoute: TruckRoute?
    let showingScaleAlert: Bool
    let scaleAlertName: String
    let scaleAlertDistanceMiles: Double
    let mapAlerts: [MapAlert]
    let formatDistance: (Double) -> String

    func body(content: Content) -> some View {
        content
            .onChange(of: currentStepIndex) { _, newIndex in
                guard isNavigating, !routeSteps.isEmpty, newIndex < routeSteps.count else { return }
                let step = routeSteps[newIndex]
                voiceManager.announceStep(
                    instructions: step.instructions,
                    stepIndex: newIndex,
                    distanceText: formatDistance(step.distance),
                    lang: lang
                )
            }
            .onChange(of: truckRoute?.distanceMeters) { _, newDist in
                guard let _ = newDist else {
                    voiceManager.resetForNewRoute()
                    return
                }
                if let first = routeSteps.first {
                    voiceManager.announceStep(
                        instructions: first.instructions,
                        stepIndex: 0,
                        distanceText: formatDistance(first.distance),
                        lang: lang
                    )
                }
            }
            .onChange(of: showingScaleAlert) { _, showing in
                guard showing else { return }
                let distText = String(format: "%.1f mi", scaleAlertDistanceMiles)
                voiceManager.announceScaleAhead(
                    stationName: scaleAlertName,
                    distanceText: distText,
                    lang: lang
                )
            }
            .onChange(of: mapAlerts.count) { oldCount, newCount in
                guard newCount > oldCount, let latest = mapAlerts.last else { return }
                switch latest.type {
                case .police, .accident, .hazmat:
                    voiceManager.announceRoadAlert(
                        type: latest.type.rawValue,
                        alertId: latest.id,
                        lang: lang
                    )
                default:
                    break
                }
            }
    }
}

// MARK: - Quantum / route-optimize badge (stop order vs road geometry)

/// Shown when `POST /v1/optimize` succeeded for this leg — clarifies that the **purple line** (if shown) is still road geometry.
struct HorizonQuantumRouteBadge: View {
    let provenance: TruckRouteProvenance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: provenance.usesQuantumAccentPolyline ? "atom" : "arrow.triangle.swap")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(provenance.driverBadgeTitle)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
            }
            Text(provenance.driverBadgeSubtitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.15, blue: 0.55).opacity(0.96),
                            Color(red: 0.22, green: 0.08, blue: 0.38).opacity(0.96)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}
