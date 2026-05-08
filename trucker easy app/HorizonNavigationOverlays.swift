// HorizonNavigationOverlays.swift — Step banner, ETA bar, route steps, arrival card
// Navigation-specific overlays shown during active route following.

import SwiftUI
import MapKit

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

    private var compactHeight: CGFloat { 72 }

    private var mainStreetName: String {
        let raw = step.instructions
        let lower = raw.lowercased()
        if let range = lower.range(of: " onto ") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = lower.range(of: " on ") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = lower.range(of: " para ") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw
    }

    private var maneuverIcon: String {
        let t = step.instructions.lowercased()
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

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Image(systemName: maneuverIcon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 28)

                Text(step.distance > 0 ? formatDistance(step.distance) : "")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(width: 58)
            .padding(.vertical, 4)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(mainStreetName)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(step.instructions)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(spacing: 6) {
                if let onMicTap {
                    Button(action: onMicTap) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color(hex: "#20242b"))
                            .clipShape(Circle())
                    }
                }

                Button(action: onToggleList) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.Colors.accent)
                        .frame(width: 40, height: 36)
                        .accessibilityLabel("Route steps")
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .frame(height: compactHeight)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                // Keep the bar only in its own compact top lane; avoid material bleed over map.
                .fill(Color.black.opacity(0.97))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .zIndex(500)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        // #region agent log
                        let minY = Int(proxy.frame(in: .global).minY)
                        print("[DBG][H-ui-11][H-banner-size] h=\(Int(proxy.size.height)) w=\(Int(proxy.size.width)) minY=\(minY) hasThen=\((nextStepInstruction?.isEmpty == false)) streetLen=\(mainStreetName.count)")
                        // #endregion
                    }
            }
        )
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

    private var nearestFuelStop: TruckStopItem? {
        stops.min(by: { $0.distanceMeters < $1.distanceMeters })
    }

    private var nearestReeferStop: TruckStopItem? {
        let withDEF = stops.filter { $0.amenities.hasDEF }
        return withDEF.min(by: { $0.distanceMeters < $1.distanceMeters })
    }

    var body: some View {
        VStack(spacing: 8) {
            if let fuel = nearestFuelStop {
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

            NavInfoCard(
                icon: "scalemass.fill",
                color: scaleColor,
                topLine: hasScaleAhead ? String(format: "%.1f mi", scaleAlertDistanceMiles) : "–",
                bottomLine: hasScaleAhead ? scaleStatusLabel : "Balança"
            )

            if let reefer = nearestReeferStop {
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
        case .open:    return Color(hex: "#ef4444")
        case .closed:  return Color(hex: "#22d474")
        case .unknown: return AppTheme.Colors.textSecondary
        }
    }

    private var scaleStatusLabel: String {
        switch scaleAlertStatus {
        case .open:    return "OPEN"
        case .closed:  return "FECHADA"
        case .unknown: return "à frente"
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
