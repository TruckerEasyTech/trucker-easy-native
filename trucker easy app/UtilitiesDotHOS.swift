// UtilitiesDotHOS.swift
// TruckerEasy — DOT Hours of Service Engine
// © 2024–2025 TruckerEasy. All rights reserved.
//
// Three components:
//  1. DotHosContext   — @Observable class, 1-second timer, status machine
//  2. DotSpeedFeeder  — feeds live GPS speed into the context, auto-detects DRIVING
//  3. DotHosBar       — compact visual bar for the map overlay (top-right)

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
    private(set) var breakElapsed: Double    = 0   // time resting since last driving stint
    private(set) var shiftElapsed: Double    = 0   // total on-duty window

    // MARK: Current status
    private(set) var status: DotDutyStatus = .offDuty

    // MARK: Speed feed (set by DotSpeedFeeder)
    var currentSpeedMph: Double = 0

    // MARK: Violation / warning flags
    private(set) var needsMandatoryBreak: Bool  = false  // driving > breakAfterSeconds without 30-min break
    private(set) var isViolation: Bool           = false  // driving > maxDrivingSeconds

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
    private let kStatus     = "dot_statusRaw"
    private let kResetDate  = "dot_lastResetDate"

    init() {
        restoreState()
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
        needsMandatoryBreak = false
        isViolation         = false
        saveState()
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

    /// Fraction of driving hours *remaining* (used for bar fill: 1 = full tank, 0 = empty)
    var drivingRemainingFraction: Double { 1 - drivingFraction }
    var shiftRemainingFraction: Double   { 1 - shiftFraction }

    var formattedDrivingRemaining: String { formatHMS(drivingRemaining) }
    var formattedShiftRemaining: String   { formatHMS(shiftRemaining) }

    // Color logic
    var barColor: Color {
        if isViolation { return Color(hex: "#ef4444") }
        if drivingRemainingFraction < 0.10 { return Color(hex: "#ef4444") }
        if drivingRemainingFraction < 0.25 { return Color(hex: "#f59e0b") }
        return Color(hex: "#22c55e")
    }

    var isRedFlashing: Bool { drivingRemainingFraction < 0.10 || isViolation }

    // MARK: - Timer tick

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
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
            speedBelowThresholdSeconds = 0

        case .onDuty:
            dutyElapsed  += 1
            shiftElapsed += 1

        case .offDuty, .sleeper:
            breakElapsed += 1

        }

        // Update violation flags
        needsMandatoryBreak = drivingElapsed >= breakAfterSeconds && breakElapsed < breakDurationSeconds
        isViolation         = drivingElapsed > maxDrivingSeconds

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

    private func autoResetIfNewDay() {
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
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
    }

    private func restoreState() {
        drivingElapsed = UserDefaults.standard.double(forKey: kDriving)
        dutyElapsed    = UserDefaults.standard.double(forKey: kDuty)
        shiftElapsed   = UserDefaults.standard.double(forKey: kShift)
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
                    if hosContext.isViolation {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#ef4444"))
                    } else if hosContext.needsMandatoryBreak {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#f59e0b"))
                    }
                }

                // Driving remaining label
                HStack(spacing: 2) {
                    Text(hosContext.formattedDrivingRemaining)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(hosColor)
                        .opacity(hosContext.isRedFlashing ? (flash ? 1 : 0.35) : 1)
                    Text("drive")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "#94a3b8"))
                    Spacer()
                }

                // Progress bar — driving hours remaining
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 5)

                        // Fill (remaining, not consumed)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barGradient)
                            .frame(width: max(4, geo.size.width * hosContext.drivingRemainingFraction), height: 5)
                            .opacity(hosContext.isRedFlashing ? (flash ? 1 : 0.4) : 1)
                    }
                }
                .frame(height: 5)

                // Shift window remaining (smaller secondary bar)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#f59e0b").opacity(0.7))
                            .frame(width: max(3, geo.size.width * hosContext.shiftRemainingFraction), height: 3)
                    }
                }
                .frame(height: 3)

                // Shift label
                HStack(spacing: 2) {
                    Text(hosContext.formattedShiftRemaining)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "#94a3b8"))
                    Text("shift")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "#64748b"))
                    Spacer()
                }
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
    }

    // MARK: - Helpers

    private var hosColor: Color { hosContext.barColor }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [hosColor, hosColor.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func startFlash() {
        flashTimer?.invalidate()
        guard hosContext.isRedFlashing else { flash = true; return }
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.45)) { flash.toggle() }
        }
        RunLoop.main.add(flashTimer!, forMode: .common)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: 4 — DotHosDetailSheet  (full HOS panel, shown on tap)
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
                        if hosContext.isViolation {
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
