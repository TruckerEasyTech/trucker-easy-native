// Driving HUD — satellite/hybrid + mute (competitor-style; visible while navigating).

import SwiftUI

struct HorizonNavigationDrivingControls: View {
    @Binding var selectedMapStyle: MapStyleOption
    var voiceManager: VoiceNavigationManager
    var lang: AppLanguage
    var onReroute: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Menu {
                ForEach(MapStyleOption.allCases, id: \.self) { style in
                    Button { selectedMapStyle = style } label: {
                        Label(style.rawValue, systemImage: style.icon)
                    }
                }
            } label: {
                navHudButton(
                    icon: selectedMapStyle == .satellite || selectedMapStyle == .hybrid
                        ? "globe.americas.fill"
                        : selectedMapStyle.icon,
                    highlighted: selectedMapStyle == .hybrid || selectedMapStyle == .satellite
                )
            }
            .accessibilityLabel("Map style")

            Button(action: { voiceManager.isEnabled.toggle() }) {
                navHudButton(
                    icon: voiceManager.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    highlighted: !voiceManager.isEnabled,
                    warnWhenOff: true
                )
            }
            .accessibilityLabel(
                voiceManager.isEnabled ? lang.voiceNavOnLabel : lang.voiceNavOffLabel
            )

            if let onReroute {
                Button(action: onReroute) {
                    navHudButton(icon: "arrow.triangle.2.circlepath", highlighted: false)
                }
                .accessibilityLabel("Reroute")
            }
        }
    }

    @ViewBuilder
    private func navHudButton(icon: String, highlighted: Bool, warnWhenOff: Bool = false) -> some View {
        let tint: Color = {
            if warnWhenOff && highlighted { return AppTheme.Colors.warning }
            if highlighted { return AppTheme.Colors.accent }
            return .white
        }()
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 40, height: 40)
            .background(Color(hex: "#0d1117").opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

// MARK: - Upcoming corridor rail (stops + weigh status)

struct HorizonCorridorRailItem: Identifiable {
    enum Kind { case truckStop, weighStation, restArea, fuel }
    let id: String
    let kind: Kind
    let title: String
    let distanceMiles: Double
    /// open / closed / unknown — weigh stations & parking crowdsource
    var status: ScaleAlertBanner.ScaleStatus?
    /// True when weigh status comes from government / 511 feed.
    var isOfficialStatus: Bool = false
}

struct HorizonNavigationCorridorRail: View {
    let items: [HorizonCorridorRailItem]
    var formatDistance: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.prefix(5)) { item in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(iconBackground(for: item))
                            .frame(width: 28, height: 28)
                        Text(iconLabel(for: item))
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%.0f mi", item.distanceMiles))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                        if let status = item.status {
                            Text(item.isOfficialStatus ? statusLabel(status) : "?")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(statusColor(status))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(hex: "#0d1117").opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func iconLabel(for item: HorizonCorridorRailItem) -> String {
        switch item.kind {
        case .truckStop: return "T"
        case .weighStation: return "W"
        case .restArea: return "R"
        case .fuel: return "F"
        }
    }

    private func iconBackground(for item: HorizonCorridorRailItem) -> Color {
        switch item.kind {
        case .truckStop: return Color(hex: "#c2410c")
        case .weighStation:
            if item.isOfficialStatus, item.status == .open { return Color(hex: "#16a34a") }
            if item.isOfficialStatus, item.status == .closed { return Color(hex: "#ea580c") }
            if item.status == .monitoring { return Color(hex: "#f59e0b") }
            return Color(hex: "#57534e")
        case .restArea: return Color(hex: "#2563eb")
        case .fuel: return AppTheme.Colors.accent
        }
    }

    private func statusLabel(_ s: ScaleAlertBanner.ScaleStatus) -> String {
        switch s {
        case .open: return "OPEN"
        case .closed: return "CLOSED"
        case .monitoring: return "MON"
        case .unknown: return "?"
        }
    }

    private func statusColor(_ s: ScaleAlertBanner.ScaleStatus) -> Color {
        switch s {
        case .open: return Color(hex: "#4ade80")
        case .closed: return Color(hex: "#fb923c")
        case .monitoring: return Color(hex: "#f59e0b")
        case .unknown: return AppTheme.Colors.textSecondary
        }
    }
}
