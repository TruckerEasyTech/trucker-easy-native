//
//  HorizonTruckerPathNavigationChrome.swift
//  Full-screen driving UI aligned with professional truck nav (Trucker Path–style).
//

import SwiftUI
import MapKit

// MARK: - Unified navigation layer

struct HorizonTruckerPathNavigationChrome: View {
    let step: DisplayRouteStep
    var nextStepInstruction: String?
    /// Live road distance (m) to the upcoming maneuver, from NavigationEngine — counts down each GPS
    /// fix. When nil/0 the bar falls back to the step's static Valhalla length.
    var liveManeuverDistanceMeters: Double? = nil
    let formatDistance: (Double) -> String
    let roadLine: String
    let totalDistanceText: String
    let totalDurationText: String
    let arrivalText: String
    let speedLimit: String
    let currentSpeed: String
    let speedUnit: String
    var isOverspeeding: Bool = false
    var showLaneBar: Bool = false

    @Binding var selectedMapStyle: MapStyleOption
    var voiceManager: VoiceNavigationManager
    var lang: AppLanguage
    var corridorRailItems: [HorizonCorridorRailItem] = []
    var hosContext: DotHosContext? = nil
    var onHosTap: (() -> Void)? = nil
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onRecenter: () -> Void
    var onReroute: (() -> Void)?
    var onStopNavigation: () -> Void
    var onToggleSteps: () -> Void
    var onTogglePOIs: () -> Void
    var poisHidden: Bool

    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 48
    }

    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    TruckerPathTopManeuverBar(
                        step: step,
                        nextStepInstruction: nextStepInstruction,
                        liveManeuverDistanceMeters: liveManeuverDistanceMeters,
                        formatDistance: formatDistance,
                        onToggleSteps: onToggleSteps
                    )
                    .padding(.top, safeTop)

                    if showLaneBar {
                        HorizonLaneGuidanceBar(totalLanes: 4)
                            .padding(.horizontal, 12)
                            .padding(.top, 2)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                TruckerPathBottomTripBar(
                    roadLine: roadLine,
                    totalDistanceText: totalDistanceText,
                    totalDurationText: totalDurationText,
                    arrivalText: arrivalText,
                    speedLimit: speedLimit,
                    currentSpeed: currentSpeed,
                    speedUnit: speedUnit,
                    isOverspeeding: isOverspeeding,
                    hosContext: hosContext,
                    onHosTap: onHosTap,
                    poisHidden: poisHidden,
                    onTogglePOIs: onTogglePOIs,
                    onReroute: onReroute,
                    onStopNavigation: onStopNavigation,
                    onToggleSteps: onToggleSteps
                )
                .padding(.bottom, max(safeBottom, 6))
            }
            .overlay(alignment: .topTrailing) {
                // Compact HOS glance widget — Drive/Shift remaining, read-only (no tap).
                if let hosContext {
                    DotHosMiniWidget(hosContext: hosContext)
                        .padding(.trailing, 8)
                        .padding(.top, safeTop + (showLaneBar ? 118 : 96))
                }
            }
            .overlay(alignment: .trailing) {
                TruckerPathRightControls(
                    selectedMapStyle: $selectedMapStyle,
                    voiceManager: voiceManager,
                    lang: lang,
                    onZoomIn: onZoomIn,
                    onZoomOut: onZoomOut,
                    onRecenter: onRecenter
                )
                .padding(.trailing, 8)
                // Extra top room keeps the zoom/recenter column clear of the HOS mini widget.
                .padding(.top, safeTop + (showLaneBar ? 118 : 96) + (hosContext != nil ? 64 : 0))
                .padding(.bottom, safeBottom + 92)
            }
            .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Top maneuver bar

private struct TruckerPathTopManeuverBar: View {
    let step: DisplayRouteStep
    var nextStepInstruction: String?
    var liveManeuverDistanceMeters: Double? = nil
    let formatDistance: (Double) -> String
    let onToggleSteps: () -> Void

    private var stayOnTitle: String {
        let raw = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "—" }
        let lower = raw.lowercased()
        // Routing already returns localized turn text — don't prepend English "Stay on".
        if lower.contains("vire") || lower.contains("virar") || lower.contains("continue")
            || lower.contains("stay on") || lower.contains("turn") || lower.contains("head")
            || lower.contains("merge") || lower.contains("take") || lower.contains("keep")
            || lower.contains("sigaa") || lower.contains("siga") {
            return raw
        }
        if lower.contains(" on ") || lower.contains(" onto ") || lower.contains(" para ") {
            return raw
        }
        return raw
    }

    private var distanceText: String {
        // Prefer the live counting-down distance to the turn; fall back to the static step length.
        if let live = liveManeuverDistanceMeters, live > 0 {
            return formatDistance(live)
        }
        return step.distance > 0 ? formatDistance(step.distance) : "—"
    }

    private var exitShield: String? {
        // ESTRUTURADO primeiro: o número EXATO do `sign.exit_number` do Valhalla — nada de adivinhar.
        if let n = step.exitNumber, !n.isEmpty { return n }
        // Fallback (fonte sem sign estruturado): regex no texto.
        let sources = [nextStepInstruction, step.instructions].compactMap { $0 }
        for text in sources {
            if let n = TruckerPathTopManeuverBar.parseExitNumber(from: text) {
                return n
            }
        }
        return nil
    }

    /// Destino da saída ("...toward X" / "...para X") — a cidade/via pra onde a saída leva.
    /// Vem direto do texto da instrução do Valhalla (campo `sign.exit_toward`).
    private var exitToward: String? {
        // ESTRUTURADO primeiro: `sign.exit_toward` do Valhalla (destino exato da saída).
        if let t = step.exitToward, !t.isEmpty { return t }
        let sources = [nextStepInstruction, step.instructions].compactMap { $0 }
        for text in sources {
            if let t = TruckerPathTopManeuverBar.parseToward(from: text) { return t }
        }
        return nil
    }

    static func parseToward(from text: String) -> String? {
        let patterns = [#"toward\s+(.+?)[\.,;]*$"#, #"\bpara\s+(.+?)[\.,;]*$"#, #"rumo a\s+(.+?)[\.,;]*$"#]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: text) {
                let s = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if s.count >= 2 && s.count <= 42 { return s }
            }
        }
        return nil
    }

    static func parseExitNumber(from text: String) -> String? {
        let lower = text.lowercased()
        let patterns = [#"exit\s+(\d+[a-z]?)"#, #"take\s+exit\s+(\d+[a-z]?)"#, #"\bexits?\s+(\d+[a-z]?)\b"#]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: lower) {
                return String(lower[r]).uppercased()
            }
        }
        // BUG corrigido (road test "saída errada"): o fallback antigo retornava o número de um
        // INTERESTADUAL (ex.: "Merge onto I-84") como se fosse a saída → mostrava "EXIT I-84". Uma
        // rodovia NÃO é uma saída. Sem um "exit N" real, NÃO há shield de saída.
        return nil
    }

    private var maneuverIcon: String {
        NavigationManeuverIcon.symbol(for: step.instructions)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: maneuverIcon)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(distanceText)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(stayOnTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let exit = exitShield {
                    // Placa de saída estilo rodovia US — grande e alto contraste, p/ o motorista
                    // bater o olho e saber ONDE sair e PRA ONDE (cidade/via). Antes: texto verde 11pt.
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("EXIT")
                                .font(.system(size: 12, weight: .heavy))
                            Text(exit)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#16a34a"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        if let toward = exitToward {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.turn.up.right")
                                    .font(.system(size: 11, weight: .bold))
                                Text(toward)
                                    .font(.system(size: 15, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundColor(Color(hex: "#4ade80"))
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 4)

            Button(action: onToggleSteps) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.Colors.accent)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.88), Color.black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(true)
    }
}

// MARK: - Right controls (satellite / mute / zoom)

private struct TruckerPathRightControls: View {
    @Binding var selectedMapStyle: MapStyleOption
    var voiceManager: VoiceNavigationManager
    var lang: AppLanguage
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onRecenter: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Menu {
                ForEach(MapStyleOption.allCases, id: \.self) { style in
                    Button { selectedMapStyle = style } label: {
                        Label(style.rawValue, systemImage: style.icon)
                    }
                }
            } label: {
                controlIcon(
                    selectedMapStyle == .hybrid || selectedMapStyle == .satellite
                        ? "globe.americas.fill" : "map",
                    accent: selectedMapStyle == .hybrid
                )
            }

            Button(action: { voiceManager.isEnabled.toggle() }) {
                controlIcon(
                    voiceManager.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    accent: false,
                    warn: !voiceManager.isEnabled
                )
            }
            .accessibilityLabel(voiceManager.isEnabled ? lang.voiceNavOnLabel : lang.voiceNavOffLabel)

            Button(action: onZoomOut) {
                controlIcon("minus", accent: false)
            }
            Button(action: onZoomIn) {
                controlIcon("plus", accent: false)
            }
            Button(action: onRecenter) {
                controlIcon("location.fill", accent: true)
            }
        }
    }

    private func controlIcon(_ name: String, accent: Bool, warn: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(warn ? AppTheme.Colors.warning : (accent ? AppTheme.Colors.accent : .white))
            .frame(width: 44, height: 44)
            .background(Color(hex: "#0d1117").opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}

// MARK: - Bottom trip bar

private struct TruckerPathBottomTripBar: View {
    let roadLine: String
    let totalDistanceText: String
    let totalDurationText: String
    let arrivalText: String
    let speedLimit: String
    let currentSpeed: String
    let speedUnit: String
    var isOverspeeding: Bool
    var hosContext: DotHosContext?
    var onHosTap: (() -> Void)?
    var poisHidden: Bool
    var onTogglePOIs: () -> Void
    var onReroute: (() -> Void)?
    var onStopNavigation: () -> Void
    var onToggleSteps: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                TruckerPathSpeedPanel(
                    speedLimit: speedLimit,
                    currentSpeed: currentSpeed,
                    unitLabel: speedUnit,
                    isOverspeeding: isOverspeeding
                )

                VStack(alignment: .leading, spacing: 2) {
                    if !roadLine.isEmpty {
                        Text(roadLine)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    Text("\(totalDistanceText) · \(totalDurationText)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)   // distância·duração cabe inteira, sem cortar em "...10h…"
                    Text(arrivalText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.65))
                }

                Spacer(minLength: 0)

                if let hosContext {
                    Button(action: { onHosTap?() }) {
                        VStack(spacing: 2) {
                            Text("DOT")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.white.opacity(0.7))
                            Text(hosContext.formattedCriticalRemaining)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(hosContext.barColor)
                        }
                        .frame(width: 52, height: 44)
                        .background(Color(hex: "#2a2a2e"))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    Button(action: onToggleSteps) {
                        Label("Route steps", systemImage: "list.bullet")
                    }
                    Button(action: onTogglePOIs) {
                        Label(poisHidden ? "Show POIs" : "Hide POIs", systemImage: poisHidden ? "eye" : "eye.slash")
                    }
                    if let onReroute {
                        Button(action: onReroute) {
                            Label("Reroute", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    Button(role: .destructive, action: onStopNavigation) {
                        Label("Stop navigation", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 40, height: 44)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "#141418").opacity(0.94))
        )
        .padding(.horizontal, 10)
        .allowsHitTesting(true)
    }
}

// MARK: - Speed (competitor twin boxes)

private struct TruckerPathSpeedPanel: View {
    let speedLimit: String
    let currentSpeed: String
    let unitLabel: String
    var isOverspeeding: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(speedLimit)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                Text("LIMIT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
            }
            .frame(width: 54, height: 54)
            .background(Color.white)

            VStack(spacing: 0) {
                Text(currentSpeed)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundColor(isOverspeeding ? Color(hex: "#ef4444") : Color(hex: "#ea580c"))
                Text(unitLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.55))
            }
            .frame(width: 54, height: 54)
            .background(Color(hex: "#2a2a2e"))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}
