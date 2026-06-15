// UtilitiesDotHOS.swift
// TruckerEasy — DOT Hours of Service Engine
// © 2024–2026 TruckerEasy. All rights reserved.
//
// Four components:
//  1. DotHosContext   — @Observable class, 1-second timer, status machine
//  2. DotSpeedFeeder  — feeds live GPS speed into the context, auto-detects DRIVING
//  3. DotHosBar       — pill DOT (Horizon idle + rota/navegação, canto superior direito)
//  4. DotHosColorLine  — linha de cor (uso interno / legado)

import SwiftUI
import Observation
import CoreLocation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 1 — DotHosContext
// ─────────────────────────────────────────────────────────────────────────────

enum DotDutyStatus: String, CaseIterable {
    case offDuty    = "OFF DUTY"
    case sleeper    = "SLEEPER"
    case onDuty     = "ON DUTY"
    case driving    = "DRIVING"

    var icon: String {
        switch self {
        case .offDuty:  return "moon.zzz.fill"
        case .sleeper:  return "bed.double.fill"
        case .onDuty:   return "briefcase.fill"
        case .driving:  return "truck.box.fill"
        }
    }

    var color: Color {
        switch self {
        case .offDuty:  return Color(hex: "#64748b")
        case .sleeper:  return Color(hex: "#6366f1")
        case .onDuty:   return Color(hex: "#f59e0b")
        case .driving:  return Color(hex: "#00d4ff")
        }
    }
}

@Observable
final class DotHosContext {

    // MARK: Current rules (injected from RegionalSettings)
    var maxDrivingSeconds: Double    = 11 * 3600   // default: USA 11h
    var serviceWindowSeconds: Double = 14 * 3600   // default: USA 14h
    var breakAfterSeconds: Double    = 8  * 3600   // USA: break after 8h driving
    var breakDurationSeconds: Double = 30 * 60     // USA: 30-min break

    // MARK: Elapsed counters (seconds)
    private(set) var drivingElapsed: Double  = 0
    private(set) var dutyElapsed: Double     = 0
    private(set) var breakElapsed: Double    = 0   // continuous rest/off-duty time
    private(set) var breakDrivingElapsed: Double = 0 // driving since last qualifying 30-min break
    private(set) var shiftElapsed: Double    = 0   // total on-duty window

    // MARK: Current status
    private(set) var status: DotDutyStatus = .offDuty

    // MARK: Speed feed (set by DotSpeedFeeder)
    var currentSpeedMph: Double = 0

    // MARK: Violation / warning flags
    private(set) var needsMandatoryBreak: Bool  = false  // driving > breakAfterSeconds without 30-min break
    private(set) var isViolation: Bool           = false  // driving > maxDrivingSeconds

    /// Active route ETA (seconds) — drives green/yellow/red vs trip time while navigating.
    private(set) var routeEtaSeconds: Double = 0

    // MARK: Timer
    private var timer: Timer?

    // Speed thresholds & debounce (seconds)
    private let drivingSpeedThreshold: Double = 5    // mph — above this = driving candidate
    private let stoppedSpeedThreshold: Double = 1    // mph — below this = definitely stopped
    private let autoDriveDelay: Double        = 60   // seconds above threshold before auto-DRIVING
    private let autoStopDelay: Double         = 120  // seconds below threshold before stopping DRIVING counter

    private var speedAboveThresholdSeconds: Double = 0
    private var speedBelowThresholdSeconds: Double  = 0

    // MARK: Persist keys
    private let kDriving    = "dot_drivingElapsed"
    private let kDuty       = "dot_dutyElapsed"
    private let kShift      = "dot_shiftElapsed"
    private let kBreakDrive = "dot_breakDrivingElapsed"
    private let kStatus     = "dot_statusRaw"
    private let kResetDate  = "dot_lastResetDate"

    init() {
        restoreState()
        autoResetIfNewDay()
        startTimer()
    }

    deinit { timer?.invalidate() }

    // MARK: - Public control

    func setStatus(_ newStatus: DotDutyStatus) {
        guard newStatus != status else { return }
        // Reset break counter when transitioning away from rest
        if status == .offDuty || status == .sleeper {
            if newStatus == .driving || newStatus == .onDuty {
                breakElapsed = 0
            }
        }
        status = newStatus
        UserDefaults.standard.set(newStatus.rawValue, forKey: kStatus)
    }

    func updateRules(maxDriving: Double, serviceWindow: Double, breakAfter: Double, breakMinutes: Int) {
        maxDrivingSeconds    = maxDriving    * 3600
        serviceWindowSeconds = serviceWindow * 3600
        breakAfterSeconds    = breakAfter    * 3600
        breakDurationSeconds = Double(breakMinutes) * 60
    }

    func resetDay() {
        drivingElapsed = 0
        dutyElapsed    = 0
        shiftElapsed   = 0
        breakElapsed   = 0
        breakDrivingElapsed = 0
        needsMandatoryBreak = false
        isViolation         = false
        routeEtaSeconds     = 0
        saveState()
    }

    func beginRouteSession(estimatedDrivingSeconds: Double) {
        routeEtaSeconds = max(0, estimatedDrivingSeconds)
    }

    func endRouteSession() {
        routeEtaSeconds = 0
    }

    /// Horizon idle open — parked drivers should not see a red HOS bar from stale on-duty persistence.
    func reconcileParkedAtLaunch(isNavigating: Bool, speedMph: Double) {
        guard !isNavigating else { return }
        autoResetIfNewDay()
        if speedMph < stoppedSpeedThreshold, status == .driving || status == .onDuty {
            setStatus(.offDuty)
        }
    }

    // MARK: - Speed feed (called by DotSpeedFeeder every update)

    func feedSpeed(_ mph: Double) {
        currentSpeedMph = mph
    }

    // MARK: - Derived helpers

    var drivingRemaining: Double  { max(0, maxDrivingSeconds - drivingElapsed) }
    var shiftRemaining: Double    { max(0, serviceWindowSeconds - shiftElapsed) }
    var drivingFraction: Double   { min(1, drivingElapsed / maxDrivingSeconds) }
    var shiftFraction: Double     { min(1, shiftElapsed   / serviceWindowSeconds) }
    var criticalRemainingSeconds: Double { min(drivingRemaining, shiftRemaining) }

    /// Fractions remaining (used for bar fill: 1 = full legal time, 0 = no legal time left).
    var drivingRemainingFraction: Double { 1 - drivingFraction }
    var shiftRemainingFraction: Double   { 1 - shiftFraction }
    var criticalRemainingFraction: Double { min(drivingRemainingFraction, shiftRemainingFraction) }

    var formattedDrivingRemaining: String { formatHMS(drivingRemaining) }
    var formattedShiftRemaining: String   { formatHMS(shiftRemaining) }
    var formattedCriticalRemaining: String { formatHMS(criticalRemainingSeconds) }

    /// Violation counts for UI only while driver is on duty / driving (not parked off-duty).
    var isActiveViolation: Bool {
        isViolation && (status == .driving || status == .onDuty)
    }

    // Color logic — green at route start; yellow when tight; red when HOS almost gone.
    var barColor: Color {
        if routeEtaSeconds > 0 { return routeAwareBarColor }
        // Parked / off-duty: never flash red on map open — only warn once driver is on duty.
        if status == .offDuty || status == .sleeper {
            return Color(hex: "#22c55e")
        }
        if isActiveViolation { return Color(hex: "#ef4444") }
        if criticalRemainingFraction < 0.15 { return Color(hex: "#ef4444") }
        if criticalRemainingFraction < 0.35 || needsMandatoryBreak { return Color(hex: "#f59e0b") }
        return Color(hex: "#22c55e")
    }

    private var routeAwareBarColor: Color {
        let remaining = criticalRemainingSeconds
        let eta = routeEtaSeconds
        // Vermelho fixo quando a chegada prevista estoura o tempo legal restante
        // (substitui o antigo modal "Routing Notice" — indicador discreto, sem pop-up).
        if isActiveViolation || remaining < eta { return Color(hex: "#ef4444") }
        if needsMandatoryBreak || remaining < eta * 1.30 { return Color(hex: "#f59e0b") }
        return Color(hex: "#22c55e")
    }

    var isRedFlashing: Bool {
        if status == .offDuty || status == .sleeper { return false }
        if routeEtaSeconds > 0 {
            return isActiveViolation || criticalRemainingSeconds < routeEtaSeconds * 0.12
        }
        return criticalRemainingFraction < 0.15 || isActiveViolation
    }
    var flashInterval: TimeInterval {
        if isViolation || criticalRemainingFraction < 0.02 { return 0.25 }
        if criticalRemainingFraction < 0.05 { return 0.50 }
        return 1.00
    }

    // MARK: - Timer tick

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    private func tick() {
        // Auto-detect DRIVING via speed debounce
        handleSpeedDebounce()

        // Auto-reset if calendar day has changed
        autoResetIfNewDay()

        switch status {
        case .driving:
            drivingElapsed += 1
            dutyElapsed    += 1
            shiftElapsed   += 1
            breakDrivingElapsed += 1
            breakElapsed = 0
            speedBelowThresholdSeconds = 0

        case .onDuty:
            dutyElapsed  += 1
            shiftElapsed += 1
            breakElapsed = 0

        case .offDuty, .sleeper:
            breakElapsed += 1

        }

        if breakElapsed >= breakDurationSeconds {
            breakDrivingElapsed = 0
        }
        if breakElapsed >= 10 * 3600 {
            resetDay()
            return
        }

        // Update violation flags from the critical FMCSA clocks.
        needsMandatoryBreak = breakDrivingElapsed >= breakAfterSeconds
        isViolation = drivingElapsed > maxDrivingSeconds || shiftElapsed > serviceWindowSeconds

        // Autosave every 60 ticks
        if Int(drivingElapsed) % 60 == 0 { saveState() }
    }

    private func handleSpeedDebounce() {
        if currentSpeedMph >= drivingSpeedThreshold {
            speedAboveThresholdSeconds += 1
            speedBelowThresholdSeconds  = 0
            // Auto-promote to DRIVING after 60s above threshold
            if speedAboveThresholdSeconds >= autoDriveDelay && status != .driving {
                setStatus(.driving)
            }
        } else if currentSpeedMph < stoppedSpeedThreshold {
            speedBelowThresholdSeconds += 1
            speedAboveThresholdSeconds  = 0
            // Auto-stop DRIVING counter after 120s below threshold
            if speedBelowThresholdSeconds >= autoStopDelay && status == .driving {
                setStatus(.onDuty)
            }
        }
    }

    private func calendarDayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func autoResetIfNewDay() {
        let today = calendarDayKey()
        let stored = UserDefaults.standard.string(forKey: kResetDate) ?? ""
        if stored != today {
            resetDay()
            UserDefaults.standard.set(today, forKey: kResetDate)
        }
    }

    // MARK: - Persistence

    private func saveState() {
        UserDefaults.standard.set(drivingElapsed, forKey: kDriving)
        UserDefaults.standard.set(dutyElapsed,    forKey: kDuty)
        UserDefaults.standard.set(shiftElapsed,   forKey: kShift)
        UserDefaults.standard.set(breakDrivingElapsed, forKey: kBreakDrive)
    }

    private func restoreState() {
        drivingElapsed = UserDefaults.standard.double(forKey: kDriving)
        dutyElapsed    = UserDefaults.standard.double(forKey: kDuty)
        shiftElapsed   = UserDefaults.standard.double(forKey: kShift)
        breakDrivingElapsed = UserDefaults.standard.double(forKey: kBreakDrive)
        let raw        = UserDefaults.standard.string(forKey: kStatus) ?? DotDutyStatus.offDuty.rawValue
        if let s = DotDutyStatus(rawValue: raw) { status = s }
    }

    // MARK: - Formatting

    private func formatHMS(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600
        let m = (s % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 2 — DotSpeedFeeder
// ─────────────────────────────────────────────────────────────────────────────

/// Bridges live CLLocation speed from `LocationManager` (`LocationManager.swift`) into DotHosContext.
/// Drop this into any view with access to both objects.
struct DotSpeedFeeder: ViewModifier {
    let locationManager: LocationManager
    let hosContext: DotHosContext

    func body(content: Content) -> some View {
        content
            .onChange(of: locationManager.currentLocation) { _, newLoc in
                guard let loc = newLoc else { return }
                // CLLocation speed is m/s; convert to mph
                let mph = max(0, loc.speed * 2.23694)
                hosContext.feedSpeed(mph)
            }
    }
}

extension View {
    func dotSpeedFeeder(locationManager: LocationManager, hosContext: DotHosContext) -> some View {
        modifier(DotSpeedFeeder(locationManager: locationManager, hosContext: hosContext))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 3 — DotHosBar  (map overlay widget)
// ─────────────────────────────────────────────────────────────────────────────

struct DotHosBar: View {
    let hosContext: DotHosContext
    let onTap: () -> Void

    @State private var flash = false
    @State private var flashTimer: Timer? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                // "DOT" header row
                HStack(spacing: 4) {
                    Image(systemName: hosContext.status.icon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(hosContext.status.color)

                    Text("DOT")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                        .tracking(1.2)

                    Spacer()

                    // Warning icons
                    if hosContext.isActiveViolation {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#ef4444"))
                    } else if hosContext.needsMandatoryBreak {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#f59e0b"))
                    }
                }

                // Tempo crítico restante
                HStack(spacing: 2) {
                    Text(hosContext.formattedCriticalRemaining)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(hosColor)
                        .opacity(hosContext.isRedFlashing ? (flash ? 1 : 0.35) : 1)
                    Text("left")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "#94a3b8"))
                    Spacer()
                }

                // Linha única — cor muda com tempo HOS (sem barra de shift separada)
                Rectangle()
                    .fill(hosColor)
                    .frame(height: 3)
                    .opacity(hosContext.isRedFlashing ? (flash ? 1 : 0.4) : 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 120)
            .background(.ultraThinMaterial)
            .background(Color(hex: "#0d1b2a").opacity(0.82))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(hosContext.barColor.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: hosContext.barColor.opacity(0.25), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .onAppear { startFlash() }
        .onDisappear { flashTimer?.invalidate() }
        .onChange(of: hosContext.isRedFlashing) { _, flashing in
            if flashing { startFlash() } else { flashTimer?.invalidate(); flash = true }
        }
        .onChange(of: hosContext.flashInterval) { _, _ in
            startFlash()
        }
    }

    // MARK: - Helpers

    private var hosColor: Color { hosContext.barColor }

    private func startFlash() {
        flashTimer?.invalidate()
        guard hosContext.isRedFlashing else { flash = true; return }
        let interval = hosContext.flashInterval
        flashTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: min(0.45, interval * 0.8))) { flash.toggle() }
        }
        if let ft = flashTimer { RunLoop.main.add(ft, forMode: .common) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 3b — DotHosMiniWidget  (compact glance widget, top-right while navigating)
// ─────────────────────────────────────────────────────────────────────────────

/// Compact always-visible HOS widget for the navigation screen (top-right corner).
/// Shows Drive and Shift time remaining, each with a thin progress bar
/// (green = drive, amber = shift). Read-only — no tap, no pop-ups.
struct DotHosMiniWidget: View {
    let hosContext: DotHosContext

    private let driveColor = Color(hex: "#22c55e")
    private let shiftColor = Color(hex: "#f59e0b")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            miniRow(
                time: hosContext.formattedDrivingRemaining,
                label: "drive",
                timeColor: driveColor,
                barColor: driveColor,
                fraction: hosContext.drivingRemainingFraction
            )
            miniRow(
                time: hosContext.formattedShiftRemaining,
                label: "shift",
                timeColor: Color(hex: "#cbd5e1"),
                barColor: shiftColor,
                fraction: hosContext.shiftRemainingFraction
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: 96)
        .background(Color(hex: "#0d1117").opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drive time left \(hosContext.formattedDrivingRemaining), shift time left \(hosContext.formattedShiftRemaining)")
    }

    private func miniRow(time: String, label: String, timeColor: Color, barColor: Color, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(time)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(timeColor)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#94a3b8"))
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(3, geo.size.width * CGFloat(min(1, max(0, fraction)))))
                }
            }
            .frame(height: 3)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 4 — DotHosColorLine  (one line, color = time remaining; tap for detail)
// ─────────────────────────────────────────────────────────────────────────────

struct DotHosColorLine: View {
    let hosContext: DotHosContext
    let onTap: () -> Void

    @State private var flash = false
    @State private var flashTimer: Timer? = nil

    var body: some View {
        Button(action: onTap) {
            Rectangle()
                .fill(hosContext.barColor)
                .frame(height: 3)
                .frame(maxWidth: .infinity)
                .opacity(hosContext.isRedFlashing ? (flash ? 1 : 0.4) : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("DOT hours remaining \(hosContext.formattedCriticalRemaining)")
        .onAppear { startFlash() }
        .onDisappear { flashTimer?.invalidate() }
        .onChange(of: hosContext.isRedFlashing) { _, flashing in
            if flashing { startFlash() } else { flashTimer?.invalidate(); flash = true }
        }
        .onChange(of: hosContext.flashInterval) { _, _ in startFlash() }
    }

    private func startFlash() {
        flashTimer?.invalidate()
        guard hosContext.isRedFlashing else { flash = true; return }
        let interval = hosContext.flashInterval
        flashTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: min(0.45, interval * 0.8))) { flash.toggle() }
        }
        if let ft = flashTimer { RunLoop.main.add(ft, forMode: .common) }
    }
}

/// Backward-compatible alias (same component — no separate row with clock text).
typealias DotHosNavStrip = DotHosColorLine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 5 — DotHosDetailSheet  (full HOS panel, shown on tap)
// ─────────────────────────────────────────────────────────────────────────────

struct DotHosDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let hosContext: DotHosContext

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#020810").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // Status selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DUTY STATUS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "#64748b"))
                                .tracking(1.2)

                            HStack(spacing: 8) {
                                ForEach(DotDutyStatus.allCases, id: \.self) { s in
                                    DotStatusChip(
                                        status: s,
                                        isSelected: hosContext.status == s,
                                        onTap: { hosContext.setStatus(s) }
                                    )
                                }
                            }
                        }
                        .padding()
                        .background(Color(hex: "#0d1b2a"))
                        .cornerRadius(14)

                        // Driving hours card
                        HosDetailCard(
                            icon: "truck.box.fill",
                            iconColor: Color(hex: "#00d4ff"),
                            title: "Driving Hours",
                            elapsed: hosContext.drivingElapsed,
                            limit: hosContext.maxDrivingSeconds,
                            color: hosContext.barColor
                        )

                        // Shift window card
                        HosDetailCard(
                            icon: "clock.fill",
                            iconColor: Color(hex: "#f59e0b"),
                            title: "Shift Window",
                            elapsed: hosContext.shiftElapsed,
                            limit: hosContext.serviceWindowSeconds,
                            color: Color(hex: "#f59e0b")
                        )

                        // Alerts
                        if hosContext.isActiveViolation {
                            HosAlertBanner(
                                icon: "exclamationmark.triangle.fill",
                                color: Color(hex: "#ef4444"),
                                message: "HOS VIOLATION — Driving limit exceeded. Pull over immediately."
                            )
                        } else if hosContext.needsMandatoryBreak {
                            HosAlertBanner(
                                icon: "cup.and.saucer.fill",
                                color: Color(hex: "#f59e0b"),
                                message: "Mandatory 30-min break required before continuing to drive."
                            )
                        }

                        // Current speed
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(Color(hex: "#00d4ff"))
                            Text("Current Speed")
                                .foregroundColor(.white)
                                .font(.system(size: 14))
                            Spacer()
                            Text(String(format: "%.0f mph", hosContext.currentSpeedMph))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#00d4ff"))
                        }
                        .padding()
                        .background(Color(hex: "#0d1b2a"))
                        .cornerRadius(12)

                        // Reset button
                        Button(action: { hosContext.resetDay() }) {
                            Label("Reset for New Day", systemImage: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "#1e3a5f"))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#00d4ff").opacity(0.3), lineWidth: 1))
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("DOT Hours of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "#0d1b2a"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "#00d4ff"))
                        .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sub-components for Detail Sheet

struct DotStatusChip: View {
    let status: DotDutyStatus
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.system(size: 14))
                Text(status.rawValue)
                    .font(.system(size: 8, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(isSelected ? .white : Color(hex: "#64748b"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? status.color.opacity(0.25) : Color(hex: "#1e2d3d"))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? status.color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct HosDetailCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let elapsed: Double
    let limit: Double
    let color: Color

    private var remaining: Double { max(0, limit - elapsed) }
    private var fraction: Double  { min(1, elapsed / limit) }

    private func fmt(_ s: Double) -> String {
        let sec = Int(max(0, s))
        return String(format: "%d:%02d", sec / 3600, (sec % 3600) / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(fmt(remaining) + " left")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * (1 - fraction)), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("Used: \(fmt(elapsed))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "#64748b"))
                Spacer()
                Text("Limit: \(fmt(limit))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "#64748b"))
            }
        }
        .padding(14)
        .background(Color(hex: "#0d1b2a"))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

struct HosAlertBanner: View {
    let icon: String
    let color: Color
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(color.opacity(0.12))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
    }
}
