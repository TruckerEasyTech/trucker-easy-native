import SwiftUI
import MapKit
import CoreLocation

// MARK: - Weigh Station Collaborative Status

enum WeighStationStatus: String, CaseIterable, Identifiable {
    case open       = "Open"
    case closed     = "Closed"
    case monitoring = "Monitoring"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .open:       return "scalemass.fill"
        case .closed:     return "lock.fill"
        case .monitoring: return "eye.fill"
        }
    }

    var color: Color {
        switch self {
        case .open:       return Color(hex: "#ef4444")   // red – stop required
        case .closed:     return Color(hex: "#10b981")   // green – pass through
        case .monitoring: return Color(hex: "#f59e0b")   // amber – varies
        }
    }

    var subtitle: String {
        switch self {
        case .open:       return "Scale is open – trucks must enter"
        case .closed:     return "Scale is closed – bypass freely"
        case .monitoring: return "Monitoring only – no stops at this time"
        }
    }
}

/// What happened to the driver when the scale was Open
enum WeighStationOpenOutcome: String, CaseIterable, Identifiable {
    case bypass        = "Bypass"
    case rollingAcross = "Rolling Across"
    case inspection    = "Inspection"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bypass:        return "arrow.right.circle.fill"
        case .rollingAcross: return "arrow.forward.circle.fill"
        case .inspection:    return "doc.text.magnifyingglass"
        }
    }

    var color: Color {
        switch self {
        case .bypass:        return Color(hex: "#10b981")  // green – good news
        case .rollingAcross: return Color(hex: "#f59e0b")  // amber – moving through
        case .inspection:    return Color(hex: "#ef4444")  // red – detained
        }
    }

    var description: String {
        switch self {
        case .bypass:        return "Got the green light – no stop needed"
        case .rollingAcross: return "Rolled across the scale in motion"
        case .inspection:    return "Was pulled in for a full inspection"
        }
    }
}

struct WeighStationReport: Identifiable {
    let id = UUID()
    let status: WeighStationStatus
    let outcome: WeighStationOpenOutcome?   // only set when status == .open
    let reportedBy: String
    let reportedAt: Date
    var confirmations: Int
    let latitude: Double?
    let longitude: Double?

    var timeAgo: String {
        let interval = Date().timeIntervalSince(reportedAt)
        if interval < 60   { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }

    /// Human-readable summary shown in the feed
    var summaryText: String {
        switch status {
        case .open:
            if let outcome = outcome { return "Open · \(outcome.rawValue)" }
            return "Open"
        case .closed:     return "Closed"
        case .monitoring: return "Monitoring"
        }
    }
}

/// Target scale for a driver report — Supabase POI, MapKit, or GPS fallback (nationwide).
struct WeighStationReportTarget: Identifiable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let poiPlaceId: UUID?
    let distanceMeters: Double?
    let govStatus: String?
    let govSource: String?
    let countryCode: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func from(_ row: PlacesNearRow) -> WeighStationReportTarget {
        WeighStationReportTarget(
            id: row.id,
            name: row.name ?? "Weigh Station",
            latitude: row.lat,
            longitude: row.lon,
            poiPlaceId: row.id,
            distanceMeters: row.distance_m,
            govStatus: row.gov_weigh_status,
            govSource: row.gov_weigh_source,
            countryCode: row.country_code
        )
    }

    static func fallback(at coordinate: CLLocationCoordinate2D?, name: String) -> WeighStationReportTarget {
        let coord = coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        return WeighStationReportTarget(
            id: UUID(),
            name: name,
            latitude: coord.latitude,
            longitude: coord.longitude,
            poiPlaceId: nil,
            distanceMeters: nil,
            govStatus: nil,
            govSource: nil,
            countryCode: nil
        )
    }
}

// MARK: - Status provenance (safety: official vs community vs location-only)

enum WeighStationStatusProvenance: Equatable {
    case official(source: String)
    case community
    case locationOnly

    var isOfficial: Bool {
        if case .official = self { return true }
        return false
    }

    static func isOfficialSource(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let s = raw.lowercased()
        if s.isEmpty || s == "crowd" || s.contains("driver") { return false }
        return s.contains("511")
            || s.contains("on511")
            || s.contains("cvse")
            || s.contains("bc_cvse")
            || s.contains("ntad")
            || s.contains("usdot")
            || s.contains("dot")
            || s.contains("gov")
            || s.contains("caltrans")
            || s.contains("ohgo")
            || s.contains("tpims")
            || s.contains("road511")
            || s.contains("ntad")
            || s.contains("official")
    }

    static func prettySource(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Government" }
        let s = raw.lowercased()
        if s.contains("on511") || s.contains("511on") { return "Ontario 511" }
        if s.contains("bc_cvse") || s.contains("cvse") { return "BC CVSE" }
        if s.contains("ntad") || s.contains("usdot") { return "USDOT NTAD" }
        if s.contains("ut_udot") || s.contains("udot") { return "Utah UDOT" }
        if s.contains("caltrans") { return "Caltrans" }
        if s.contains("ohgo") { return "OHGO" }
        if s.contains("tpims") { return "TPIMS" }
        if s.contains("road511") { return "511/DOT" }
        if s.contains("ntad") { return "USDOT NTAD" }
        if s.contains("crowd") { return "Drivers" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Aggregated recent driver reports for a station — drives the Community confidence badge.
struct WeighStationCommunitySummary: Equatable {
    enum Confidence: Equatable {
        case high, medium, low
    }

    let status: WeighStationStatus
    let outcome: WeighStationOpenOutcome?
    /// Reports within the last 2 h agreeing with the latest status.
    let recentCount: Int
    let latestAt: Date

    var confidence: Confidence {
        let age = Date().timeIntervalSince(latestAt)
        if recentCount >= 3 && age <= 3_600 { return .high }
        if recentCount >= 2 || age <= 1_800 { return .medium }
        return .low
    }
}

struct WeighStationResolvedStatus: Equatable {
    let displayStatus: ScaleAlertBanner.ScaleStatus
    let provenance: WeighStationStatusProvenance
    /// Community hint when official data is missing — shown as advisory, not primary safety signal.
    let communityHint: WeighStationStatus?
    /// Recent driver-report aggregation (count + age) backing the community signal.
    var communitySummary: WeighStationCommunitySummary? = nil
}

// MARK: - WeighStation Status Service (Supabase-backed, crowdsourced)

@Observable
final class WeighStationStatusService {
    static let shared = WeighStationStatusService()

    // keyed by station name — shared across all drivers via Supabase
    private(set) var reports: [String: [WeighStationReport]] = [:]
    private(set) var isSyncing = false
    private var partnerOverrides: [String: (status: WeighStationStatus, updatedAt: Date, source: String?)] = [:]

    func latestStatus(for stationName: String) -> WeighStationStatus? {
        latestStatus(for: stationName, near: nil)
    }

    /// Name match first, then partner/crowd reports within ~600 m (government + driver reports).
    func latestStatus(for stationName: String, near coordinate: CLLocationCoordinate2D?) -> WeighStationStatus? {
        if let partner = partnerOverrides[stationName],
           Date().timeIntervalSince(partner.updatedAt) <= 900 {
            return partner.status
        }
        if let coord = coordinate,
           let geo = latestPartnerEntry(near: coord, withinMeters: 600, officialOnly: false) {
            return geo.status
        }
        if let direct = reports[stationName]?.first?.status {
            return direct
        }
        if let coord = coordinate {
            return latestCrowdStatus(near: coord, withinMeters: 800)
        }
        return nil
    }

    /// When weigh feed is static `monitoring`, prefer `site_open` (e.g. ON511 rest areas) for open/closed display.
    static func effectiveGovernmentStatus(weighStatus: String?, siteOpen: Bool?) -> String? {
        let normalized = weighStatus?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "open" || normalized == "closed" { return normalized }
        if let siteOpen {
            return siteOpen ? "open" : "closed"
        }
        if normalized == "monitoring" { return "monitoring" }
        return weighStatus
    }

    /// Safety-first resolution: official status drives UI; community is advisory only.
    func resolve(
        stationName: String,
        near coordinate: CLLocationCoordinate2D?,
        govStatus: String?,
        govSource: String?,
        govSiteOpen: Bool? = nil
    ) -> WeighStationResolvedStatus {
        let effectiveGov = Self.effectiveGovernmentStatus(weighStatus: govStatus, siteOpen: govSiteOpen)
        let summary = communitySummary(for: stationName, near: coordinate)
        if let gov = Self.statusFromGovernmentField(effectiveGov) {
            return WeighStationResolvedStatus(
                displayStatus: scaleStatus(from: gov),
                provenance: .official(source: WeighStationStatusProvenance.prettySource(govSource)),
                communityHint: latestCommunityHint(for: stationName, near: coordinate),
                communitySummary: summary
            )
        }

        if let partner = latestOfficialPartner(for: stationName, near: coordinate) {
            return WeighStationResolvedStatus(
                displayStatus: scaleStatus(from: partner.status),
                provenance: .official(source: WeighStationStatusProvenance.prettySource(partner.source)),
                communityHint: latestCommunityHint(for: stationName, near: coordinate),
                communitySummary: summary
            )
        }

        if let crowd = latestCommunityHint(for: stationName, near: coordinate) {
            return WeighStationResolvedStatus(
                displayStatus: communityDisplayStatus(for: crowd, summary: summary),
                provenance: .community,
                communityHint: crowd,
                communitySummary: summary
            )
        }

        return WeighStationResolvedStatus(
            displayStatus: .unknown,
            provenance: .locationOnly,
            communityHint: nil,
            communitySummary: nil
        )
    }

    /// Community-led display: dominant status from the latest report; Open + bypass outcome shows BYPASS.
    private func communityDisplayStatus(
        for status: WeighStationStatus,
        summary: WeighStationCommunitySummary?
    ) -> ScaleAlertBanner.ScaleStatus {
        if status == .open, summary?.outcome == .bypass { return .bypass }
        return scaleStatus(from: status)
    }

    /// Aggregate driver reports for a station (name match first, then ~800 m geo match).
    func communitySummary(
        for stationName: String,
        near coordinate: CLLocationCoordinate2D?
    ) -> WeighStationCommunitySummary? {
        var pool = reports[stationName] ?? []
        if pool.isEmpty, let coord = coordinate {
            let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            for (_, stationReports) in reports {
                for report in stationReports {
                    guard let lat = report.latitude, let lon = report.longitude else { continue }
                    if here.distance(from: CLLocation(latitude: lat, longitude: lon)) <= 800 {
                        pool.append(report)
                    }
                }
            }
        }
        let sorted = pool.sorted { $0.reportedAt > $1.reportedAt }
        guard let latest = sorted.first else { return nil }
        let cutoff = Date().addingTimeInterval(-7_200)
        let recentMatching = sorted.filter { $0.reportedAt >= cutoff && $0.status == latest.status }.count
        return WeighStationCommunitySummary(
            status: latest.status,
            outcome: latest.outcome,
            recentCount: recentMatching,
            latestAt: latest.reportedAt
        )
    }

    private func scaleStatus(from status: WeighStationStatus) -> ScaleAlertBanner.ScaleStatus {
        switch status {
        case .open: return .open
        case .closed: return .closed
        case .monitoring: return .monitoring
        }
    }

    private func latestOfficialPartner(
        for stationName: String,
        near coordinate: CLLocationCoordinate2D?
    ) -> (status: WeighStationStatus, source: String?)? {
        if let partner = partnerOverrides[stationName],
           Date().timeIntervalSince(partner.updatedAt) <= 900,
           WeighStationStatusProvenance.isOfficialSource(partner.source) {
            return (partner.status, partner.source)
        }
        if let coord = coordinate,
           let geo = latestPartnerEntry(near: coord, withinMeters: 600, officialOnly: true) {
            return geo
        }
        return nil
    }

    private func latestCommunityHint(
        for stationName: String,
        near coordinate: CLLocationCoordinate2D?
    ) -> WeighStationStatus? {
        if let direct = reports[stationName]?.first?.status { return direct }
        if let coord = coordinate {
            return latestCrowdStatus(near: coord, withinMeters: 800)
        }
        return nil
    }

    private func latestPartnerEntry(
        near coordinate: CLLocationCoordinate2D,
        withinMeters: CLLocationDistance,
        officialOnly: Bool
    ) -> (status: WeighStationStatus, source: String?)? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var best: (WeighStationStatus, Date, String?)?
        for (_, entry) in partnerOverrides {
            guard Date().timeIntervalSince(entry.updatedAt) <= 900 else { continue }
            if officialOnly, !WeighStationStatusProvenance.isOfficialSource(entry.source) { continue }
            _ = here
            if best == nil || entry.updatedAt > best!.1 {
                best = (entry.status, entry.updatedAt, entry.source)
            }
        }
        guard let best else { return nil }
        return (best.0, best.2)
    }

    private func latestCrowdStatus(near coordinate: CLLocationCoordinate2D, withinMeters: CLLocationDistance) -> WeighStationStatus? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var best: (WeighStationStatus, Date)?
        for (_, stationReports) in reports {
            for report in stationReports {
                guard let lat = report.latitude, let lon = report.longitude else { continue }
                let dist = here.distance(from: CLLocation(latitude: lat, longitude: lon))
                guard dist <= withinMeters else { continue }
                if best == nil || report.reportedAt > best!.1 {
                    best = (report.status, report.reportedAt)
                }
            }
        }
        return best?.0
    }

    /// Government / partner feed status (OHGO, TPIMS, NTAD-derived) from `places_near`.
    static func statusFromGovernmentField(_ raw: String?) -> WeighStationStatus? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "open": return .open
        case "closed": return .closed
        case "monitoring": return .monitoring
        default: return nil
        }
    }

    func setPartnerStatus(
        _ status: WeighStationStatus,
        for stationName: String,
        updatedAt: Date = Date(),
        source: String? = nil
    ) {
        partnerOverrides[stationName] = (status, updatedAt, source)
    }

    /// Submit a report locally and sync to Supabase backend
    func submit(status: WeighStationStatus,
                outcome: WeighStationOpenOutcome? = nil,
                for stationName: String,
                latitude: Double? = nil,
                longitude: Double? = nil,
                poiPlaceId: UUID? = nil,
                prepass: Bool? = nil,
                by user: String = "You") {
        // 1. Update local state immediately for instant UI feedback
        let report = WeighStationReport(
            status: status,
            outcome: outcome,
            reportedBy: user,
            reportedAt: Date(),
            confirmations: 0,
            latitude: latitude,
            longitude: longitude
        )
        reports[stationName, default: []].insert(report, at: 0)
        if (reports[stationName]?.count ?? 0) > 10 {
            reports[stationName]?.removeLast()
        }

        // 2. Sync to Supabase so all drivers see it
        Task {
            let payload = WeighStationReportPayload(
                station_name: stationName,
                driver_id: SupabaseClient.shared.currentDriverId,
                status: status.rawValue.lowercased(),
                latitude: latitude,
                longitude: longitude,
                poi_place_id: poiPlaceId?.uuidString,
                details: WeighStationReportDetailsPayload(
                    outcome: outcome?.rawValue.lowercased(),
                    source: "trucker_easy_app",
                    prepass: prepass
                )
            )
            do {
                try await SupabaseClient.shared.submitWeighStationReport(payload)
            } catch {
                // Non-fatal: local report still visible to this driver
                #if DEBUG
                print("WeighStationStatusService: sync failed — \(error.localizedDescription)")
                #endif
            }
        }
    }

    func confirm(report: WeighStationReport, for stationName: String) {
        guard let idx = reports[stationName]?.firstIndex(where: { $0.id == report.id }) else { return }
        reports[stationName]![idx].confirmations += 1
    }

    /// Fetch recent crowdsourced reports from Supabase and merge with local state.
    /// When `near` is set, only reports within `radiusKm` are loaded (nationwide corridor use).
    func fetchRemoteReports(
        near coordinate: CLLocationCoordinate2D? = nil,
        radiusKm: Double = 150
    ) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let records: [WeighStationReportRecord]
            if let coordinate {
                records = try await SupabaseClient.shared.fetchWeighStationReportsNear(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    radiusKm: radiusKm
                )
            } else {
                records = try await SupabaseClient.shared.fetchWeighStationReports()
            }
            await MainActor.run {
                if coordinate == nil {
                    reports = [:]
                }
                for record in records {
                    let status: WeighStationStatus
                    switch record.status.lowercased() {
                    case "open":       status = .open
                    case "closed":     status = .closed
                    case "monitoring": status = .monitoring
                    default:           continue
                    }
                    let outcome: WeighStationOpenOutcome?
                    switch record.outcome?.lowercased() {
                    case "bypass":        outcome = .bypass
                    case "rollingacross": outcome = .rollingAcross
                    case "inspection":    outcome = .inspection
                    default:              outcome = nil
                    }
                    let reporter = record.driver_id != nil ? "Driver" : "Anonymous"
                    // Parse date (ISO8601)
                    let reportedAt = ISO8601DateFormatter().date(from: record.reported_at) ?? Date()
                    let report = WeighStationReport(
                        status: status,
                        outcome: outcome,
                        reportedBy: reporter,
                        reportedAt: reportedAt,
                        confirmations: record.confirmations ?? 0,
                        latitude: record.latitude,
                        longitude: record.longitude
                    )
                    reports[record.station_name, default: []].append(report)
                }
                // Sort each station's reports newest first and cap at 20
                for key in reports.keys {
                    if let existing = reports[key] {
                        reports[key] = Array(existing.sorted { $0.reportedAt > $1.reportedAt }.prefix(20))
                    }
                }
            }
        } catch {
            // Non-fatal: app still works with local reports
            #if DEBUG
            print("WeighStationStatusService: fetch failed — \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - WeighStation Status Sheet (2-step flow)

struct WeighStationStatusSheet: View {
    let driverLocation: CLLocation?
    let prefilledTarget: WeighStationReportTarget?
    let lang: AppLanguage
    let formatDistance: (Double) -> String
    @Binding var isPresented: Bool

    @State private var service = WeighStationStatusService.shared
    @State private var selectedStatus: WeighStationStatus? = nil
    @State private var selectedOutcome: WeighStationOpenOutcome? = nil
    @State private var prepassOn: Bool? = nil
    @State private var submitted = false
    @State private var nearbyTargets: [WeighStationReportTarget] = []
    @State private var selectedTargetId: UUID?
    @State private var isLoadingStations = false

    private var activeTarget: WeighStationReportTarget {
        if let id = selectedTargetId,
           let match = nearbyTargets.first(where: { $0.id == id }) {
            return match
        }
        if let prefilledTarget { return prefilledTarget }
        if let first = nearbyTargets.first { return first }
        return WeighStationReportTarget.fallback(
            at: driverLocation?.coordinate,
            name: lang.horizonGenericWeighStation
        )
    }

    private var stationName: String { activeTarget.name }

    private var latestReport: WeighStationReport? { service.reports[stationName]?.first }
    private var recentReports: [WeighStationReport] {
        (service.reports[stationName] ?? []).prefix(5).map { $0 }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {

                    stationPickerCard
                        .padding(.top, 16)
                        .padding(.horizontal, 20)

                    // ── Current status banner ──────────────────────────────
                    currentStatusBanner
                        .padding(.top, 16)
                        .padding(.horizontal, 20)

                    // ── Prediction (Trends): tendência histórica neste horário ──
                    predictionCard
                        .padding(.top, 12)
                        .padding(.horizontal, 20)

                    Divider()
                        .background(AppTheme.Colors.textSecondary.opacity(0.15))
                        .padding(.vertical, 20)

                    if submitted {
                        // ── Thank-you card ─────────────────────────────────
                        thanksCard
                            .padding(.horizontal, 20)
                    } else {
                        // ── Step 1: Choose status ──────────────────────────
                        stepOneCard
                            .padding(.horizontal, 20)

                        // ── Step 2: Choose outcome (only when Open is picked) ──
                        if selectedStatus == .open {
                            stepTwoCard
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // ── PrePass (optional, any status) ─────────────────
                        if selectedStatus != nil {
                            prepassCard
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // ── Submit button ──────────────────────────────────
                        submitButton
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    // ── Recent reports feed ────────────────────────────────
                    if !recentReports.isEmpty {
                        recentFeed
                            .padding(.top, 24)
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(AppTheme.Colors.backgroundSecond)
            .navigationTitle("Weigh Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
            .animation(.spring(response: 0.35), value: selectedStatus)
            .animation(.spring(response: 0.35), value: submitted)
        }
        .preferredColorScheme(.dark)
        .task {
            await loadNearbyStations()
        }
    }

    // MARK: Sub-views

    private var stationPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.scaleSelectStationLabel, systemImage: "scalemass.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            if isLoadingStations {
                HStack(spacing: 10) {
                    ProgressView().tint(AppTheme.Colors.accent)
                    Text(lang.scaleLoadingNearbyLabel)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if nearbyTargets.count <= 1 {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(AppTheme.Colors.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeTarget.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        if let meters = activeTarget.distanceMeters {
                            Text(formatDistance(meters))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.Colors.backgroundCard)
                .cornerRadius(AppTheme.Radius.md)
            } else {
                VStack(spacing: 8) {
                    ForEach(nearbyTargets.prefix(12)) { target in
                        stationTargetRow(target)
                    }
                }
            }
        }
    }

    private func stationTargetRow(_ target: WeighStationReportTarget) -> some View {
        let selected = selectedTargetId == target.id
        return Button {
            selectedTargetId = target.id
            selectedStatus = nil
            selectedOutcome = nil
            prepassOn = nil
            submitted = false
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let meters = target.distanceMeters {
                            Text(formatDistance(meters))
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                        if let code = target.countryCode, !code.isEmpty {
                            Text(code.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.8))
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(selected ? AppTheme.Colors.accent.opacity(0.1) : AppTheme.Colors.backgroundCard)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? AppTheme.Colors.accent.opacity(0.45) : Color.clear, lineWidth: 1.5)
            )
        }
    }

    // MARK: - Prediction (Trends) — tendência histórica por hora-do-dia, SÓ de reports reais

    struct HourlyPrediction {
        let likelyStatus: WeighStationStatus?   // nil = histórico insuficiente (NUNCA inventa)
        let sampleCount: Int
    }

    /// Agrega os reports reais da estação por hora-do-dia (janela ±1h p/ amostra) e devolve a
    /// tendência aberta/fechada neste horário. < 2 amostras → nil (honesto, sem fabricar).
    static func hourlyPrediction(reports: [WeighStationReport], atHour hour: Int) -> HourlyPrediction {
        let cal = Calendar.current
        let band = reports.filter { r in
            let h = cal.component(.hour, from: r.reportedAt)
            let raw = abs(h - hour)
            return min(raw, 24 - raw) <= 1
        }
        let open = band.filter { $0.status == .open }.count
        let closed = band.filter { $0.status == .closed }.count
        let total = open + closed
        guard total >= 2 else { return HourlyPrediction(likelyStatus: nil, sampleCount: total) }
        return HourlyPrediction(likelyStatus: closed >= open ? .closed : .open, sampleCount: total)
    }

    @ViewBuilder private var predictionCard: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let p = Self.hourlyPrediction(reports: service.reports[stationName] ?? [], atHour: hour)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").font(.system(size: 12, weight: .bold))
                Text("Prediction").font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(AppTheme.Colors.textSecondary)

            if let status = p.likelyStatus {
                HStack(spacing: 8) {
                    Image(systemName: status.icon).foregroundColor(status.color)
                    Text("Geralmente \(status.rawValue.uppercased()) por volta deste horário")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                Text("Baseado em \(p.sampleCount) report\(p.sampleCount == 1 ? "" : "s") reais neste horário (±1h).")
                    .font(.system(size: 11)).foregroundColor(AppTheme.Colors.textSecondary)
            } else {
                Text("Histórico insuficiente neste horário — ainda coletando reports reais dos motoristas.")
                    .font(.system(size: 12)).foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.Colors.textSecondary.opacity(0.08)))
    }

    private var currentStatusBanner: some View {
        HStack(spacing: 14) {
            if let latest = latestReport {
                ZStack {
                    Circle()
                        .fill(latest.status.color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: latest.status.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(latest.status.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(latest.summaryText)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(latest.status.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Text("Reported \(latest.timeAgo) · \(latest.reportedBy)")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.7))
                }
                Spacer()
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No reports yet")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text("Be the first driver to report this scale")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }

    private var stepOneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("What is the scale status?", systemImage: "1.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 10) {
                ForEach(WeighStationStatus.allCases) { status in
                    statusOptionRow(status)
                }
            }
        }
        .padding(16)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }

    private func statusOptionRow(_ status: WeighStationStatus) -> some View {
        let selected = selectedStatus == status
        return Button(action: {
            selectedStatus = status
            if status != .open { selectedOutcome = nil }
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(selected ? status.color : status.color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: status.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(selected ? .white : status.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.rawValue)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(status.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(status.color)
                        .font(.system(size: 20))
                }
            }
            .padding(12)
            .background(selected ? status.color.opacity(0.08) : Color.clear)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? status.color.opacity(0.5) : AppTheme.Colors.textSecondary.opacity(0.15), lineWidth: 1.5)
            )
        }
    }

    private var stepTwoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("What happened when you passed?", systemImage: "2.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 10) {
                ForEach(WeighStationOpenOutcome.allCases) { outcome in
                    outcomeOptionRow(outcome)
                }
            }
        }
        .padding(16)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(WeighStationStatus.open.color.opacity(0.3), lineWidth: 1)
        )
    }

    private var prepassCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Is the PrePass on?", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            HStack(spacing: 10) {
                prepassChoice(label: "PrePass ON", icon: "checkmark.seal.fill", value: true, tint: AppTheme.Colors.success)
                prepassChoice(label: "PrePass OFF", icon: "xmark.seal.fill", value: false, tint: AppTheme.Colors.danger)
            }
        }
        .padding(16)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 1)
        )
    }

    private func prepassChoice(label: String, icon: String, value: Bool, tint: Color) -> some View {
        let selected = prepassOn == value
        return Button(action: {
            // Toggle off if tapped again — PrePass is an optional hint, not required to submit.
            prepassOn = selected ? nil : value
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(selected ? .white : tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? tint.opacity(0.85) : tint.opacity(0.10))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? tint : AppTheme.Colors.textSecondary.opacity(0.15), lineWidth: 1.5)
            )
        }
    }

    private func outcomeOptionRow(_ outcome: WeighStationOpenOutcome) -> some View {
        let selected = selectedOutcome == outcome
        return Button(action: { selectedOutcome = outcome }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(selected ? outcome.color : outcome.color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: outcome.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(selected ? .white : outcome.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.rawValue)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(outcome.description)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(outcome.color)
                        .font(.system(size: 20))
                }
            }
            .padding(12)
            .background(selected ? outcome.color.opacity(0.08) : Color.clear)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? outcome.color.opacity(0.5) : AppTheme.Colors.textSecondary.opacity(0.15), lineWidth: 1.5)
            )
        }
    }

    private var submitButton: some View {
        let canSubmit: Bool = {
            guard let status = selectedStatus else { return false }
            if status == .open { return selectedOutcome != nil }
            return true
        }()

        return Button(action: submitReport) {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14))
                Text("Submit Report")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary.opacity(0.3))
            .cornerRadius(12)
        }
        .disabled(!canSubmit)
    }

    private var thanksCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.Colors.success)
            Text("Report submitted!")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text("Your update is now visible to other drivers approaching this scale.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button(action: {
                selectedStatus = nil
                selectedOutcome = nil
                prepassOn = nil
                submitted = false
            }) {
                Text("Report Again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.accent)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }

    private var recentFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Reports")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            // Anti-poluição: vários reports IGUAIS e consecutivos (ex: "Closed, Closed, Closed…")
            // colapsam num accordion "N similar reports" em vez de N linhas idênticas. Só agrupa
            // dados REAIS já carregados — nada é fabricado.
            ForEach(groupConsecutiveSimilarReports(recentReports)) { run in
                if run.reports.count == 1 {
                    WeighStationReportRow(report: run.reports[0]) {
                        service.confirm(report: run.reports[0], for: stationName)
                    }
                } else {
                    SimilarReportsGroup(run: run) { report in
                        service.confirm(report: report, for: stationName)
                    }
                }
            }
        }
    }

    /// Colapsa RUNS consecutivos de reports com o mesmo status+resumo num único grupo expansível.
    /// Mantém a ordem cronológica (não reordena) — só funde vizinhos idênticos.
    private func groupConsecutiveSimilarReports(_ reports: [WeighStationReport]) -> [GroupedReportRun] {
        var runs: [[WeighStationReport]] = []
        for r in reports {
            if let head = runs.last?.first, head.status == r.status, head.summaryText == r.summaryText {
                runs[runs.count - 1].append(r)
            } else {
                runs.append([r])
            }
        }
        return runs.map { GroupedReportRun(id: $0[0].id, reports: $0) }
    }

    // MARK: Actions

    private func submitReport() {
        guard let status = selectedStatus else { return }
        let target = activeTarget
        service.submit(
            status: status,
            outcome: status == .open ? selectedOutcome : nil,
            for: target.name,
            latitude: target.latitude,
            longitude: target.longitude,
            poiPlaceId: target.poiPlaceId,
            prepass: prepassOn
        )
        withAnimation { submitted = true }
    }

    private func loadNearbyStations() async {
        await MainActor.run { isLoadingStations = true }
        defer { Task { @MainActor in isLoadingStations = false } }

        var targets: [WeighStationReportTarget] = []
        if let location = driverLocation {
            if let rows = try? await PoiPlacesService.shared.fetchWeighStationsNear(
                location: location,
                radiusMeters: 120_000,
                limit: 50
            ) {
                targets = rows.map { WeighStationReportTarget.from($0) }
            }
            if targets.isEmpty {
                targets = await mapKitWeighTargets(near: location)
            }
            await service.fetchRemoteReports(near: location.coordinate, radiusKm: 150)
        } else {
            await service.fetchRemoteReports()
        }

        await MainActor.run {
            if let prefilled = prefilledTarget,
               !targets.contains(where: { $0.id == prefilled.id }) {
                targets.insert(prefilled, at: 0)
            }
            if targets.isEmpty, let coord = driverLocation?.coordinate {
                targets = [
                    WeighStationReportTarget.fallback(
                        at: coord,
                        name: lang.horizonGenericWeighStation
                    )
                ]
            }
            nearbyTargets = targets
            if selectedTargetId == nil {
                selectedTargetId = prefilledTarget?.id ?? targets.first?.id
            }
        }
    }

    private func mapKitWeighTargets(near location: CLLocation) async -> [WeighStationReportTarget] {
        let queries = await MainActor.run { CountryComplianceManager.shared.weighQueries }
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 120_000,
            longitudinalMeters: 120_000
        )
        var allItems: [MKMapItem] = []
        for query in queries {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = query
            req.region = region
            let items = (try? await MKLocalSearch(request: req).start())?.mapItems ?? []
            allItems.append(contentsOf: items)
        }
        var deduped: [MKMapItem] = []
        for item in allItems {
            let itemLoc = CLLocation(
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
            if !deduped.contains(where: {
                CLLocation(
                    latitude: $0.placemark.coordinate.latitude,
                    longitude: $0.placemark.coordinate.longitude
                ).distance(from: itemLoc) < 500
            }) {
                deduped.append(item)
            }
        }
        return deduped.map { item in
            let coord = item.placemark.coordinate
            let itemLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return WeighStationReportTarget(
                id: UUID(),
                name: item.name ?? lang.horizonGenericWeighStation,
                latitude: coord.latitude,
                longitude: coord.longitude,
                poiPlaceId: nil,
                distanceMeters: location.distance(from: itemLoc),
                govStatus: nil,
                govSource: nil,
                countryCode: item.placemark.isoCountryCode
            )
        }
        .sorted { ($0.distanceMeters ?? .greatestFiniteMagnitude) < ($1.distanceMeters ?? .greatestFiniteMagnitude) }
        .prefix(25)
        .map { $0 }
    }
}

// MARK: - Agrupamento anti-poluição (reports similares consecutivos)

/// Um run de reports idênticos e consecutivos (mesmo status+resumo). `id` = id do primeiro report.
private struct GroupedReportRun: Identifiable {
    let id: UUID
    let reports: [WeighStationReport]
}

/// Accordion "N similar reports" — colapsa um run de reports idênticos numa linha expansível.
private struct SimilarReportsGroup: View {
    let run: GroupedReportRun
    let onConfirm: (WeighStationReport) -> Void
    @State private var isExpanded = false

    private var status: WeighStationStatus { run.reports[0].status }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: status.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(status.color)
                        .frame(width: 22)
                    Text("\(run.reports.count) similar reports · \(run.reports[0].summaryText)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(run.reports) { report in
                    WeighStationReportRow(report: report) { onConfirm(report) }
                }
            }
        }
    }
}

// MARK: - Report Row

private struct WeighStationReportRow: View {
    let report: WeighStationReport
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            ZStack {
                Circle()
                    .fill(report.status.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: report.status.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(report.status.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(report.summaryText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    // Outcome badge (when Open)
                    if let outcome = report.outcome {
                        Text(outcome.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(outcome.color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(outcome.color.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
                Text("\(report.reportedBy) · \(report.timeAgo)")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }

            Spacer()

            // Confirm (+1) button
            Button(action: onConfirm) {
                HStack(spacing: 3) {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 10))
                    Text("\(report.confirmations)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(AppTheme.Colors.success)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.Colors.success.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)

        Divider()
            .background(AppTheme.Colors.textSecondary.opacity(0.1))
            .padding(.leading, 68)
    }
}

// MARK: - Weather Service (stub – ready for WeatherKit)

struct TruckWeather {
    let condition: String      // e.g. "Partly Cloudy"
    let temperatureF: Double   // Fahrenheit
    let windSpeedMPH: Double
    let windGustMPH: Double?
    let visibility: Double     // miles
    let precipChance: Double   // 0–1
    let icon: String           // SF Symbol

    var temperatureText: String { "\(Int(temperatureF))°F" }
    var windText: String {
        if let gust = windGustMPH { return "\(Int(windSpeedMPH)) mph gusts \(Int(gust))" }
        return "\(Int(windSpeedMPH)) mph"
    }
    var visibilityText: String { "\(Int(visibility)) mi" }
    var precipText: String { "\(Int(precipChance * 100))%" }

    /// Danger level for truck operations
    var dangerLevel: WeatherDanger {
        if windGustMPH ?? 0 > 50 || windSpeedMPH > 40 { return .high }
        if windSpeedMPH > 25 || precipChance > 0.7 || visibility < 2 { return .moderate }
        return .low
    }
}

enum WeatherDanger {
    case low, moderate, high
    var color: Color {
        switch self {
        case .low:      return AppTheme.Colors.success
        case .moderate: return AppTheme.Colors.warning
        case .high:     return AppTheme.Colors.danger
        }
    }
    var label: String {
        switch self {
        case .low:      return "Good conditions"
        case .moderate: return "Drive with caution"
        case .high:     return "Hazardous – high wind"
        }
    }
}

// WeatherService is now provided by ServicesWeatherService.swift (RealWeatherService)
// This typealias keeps backward compatibility with all existing call sites.
typealias WeatherService = RealWeatherService

// MARK: - Weather Panel Overlay

struct WeatherPanel: View {
    let weather: TruckWeather
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: weather.icon)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text(weather.condition)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(weather.temperatureText)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()
                // Danger badge
                Text(weather.dangerLevel.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(weather.dangerLevel.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(weather.dangerLevel.color.opacity(0.15))
                    .cornerRadius(8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            Divider().background(AppTheme.Colors.textSecondary.opacity(0.2))

            // Metrics grid
            HStack(spacing: 0) {
                WeatherMetric(icon: "wind", label: "Wind", value: weather.windText)
                Divider().background(AppTheme.Colors.textSecondary.opacity(0.2)).frame(height: 32)
                WeatherMetric(icon: "eye.fill", label: "Visibility", value: weather.visibilityText)
                Divider().background(AppTheme.Colors.textSecondary.opacity(0.2)).frame(height: 32)
                WeatherMetric(icon: "cloud.rain.fill", label: "Precip", value: weather.precipText)
            }
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundCard.opacity(0.96))
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(weather.dangerLevel.color.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 10)
    }
}

private struct WeatherMetric: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quiet Parking Badge

extension NearbyStopItem {
    /// Heuristic: a parking stop is "quiet" if it is ≥ 0.5 mi off the main route corridor.
    /// Here we simply check if the name contains known truck stop names that are
    /// typically quieter independent stops (off-highway). This can be refined with
    /// actual distance-from-polyline math once a route is available.
    var isQuietParking: Bool {
        guard category == .parking else { return false }
        let lower = name.lowercased()
        // Flag independent or rest-area parking as "quiet"
        let quietKeywords = ["rest area", "rest stop", "state park", "county", "independent", "private lot"]
        return quietKeywords.contains { lower.contains($0) }
    }
}

// MARK: - Share Trip Progress Sheet — Family View (Trucker Easy Differential)

struct ShareTripProgressSheet: View {
    let trip: Trip?
    let route: MKRoute?
    let locationManager: LocationManager
    @Binding var isPresented: Bool

    @State private var driverNote = ""
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var copiedLink = false
    @State private var selectedTab = 0  // 0 = Family, 1 = Dispatcher
    @Environment(RegionalSettingsManager.self) private var regionalSettings

    /// Unique per-device trip link code (persisted across launches)
    private var familyCode: String {
        if let saved = UserDefaults.standard.string(forKey: "familyShareCode") { return saved }
        let code = String(UUID().uuidString.prefix(8).uppercased())
        UserDefaults.standard.set(code, forKey: "familyShareCode")
        return code
    }

    private var familyLink: String { "truckereasy://track/\(familyCode)" }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {

                        // Tab selector
                        HStack(spacing: 0) {
                            tabButton("Família / Family", icon: "house.fill", index: 0)
                            tabButton("Dispatcher", icon: "headphones", index: 1)
                        }
                        .padding(4)
                        .background(AppTheme.Colors.backgroundCard)
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        if selectedTab == 0 {
                            familyTab
                        } else {
                            dispatcherTab
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Compartilhar Viagem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") { isPresented = false }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Family Tab

    private var familyTab: some View {
        VStack(spacing: 16) {

            // Explanation banner
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppTheme.Colors.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vista da Família — Somente Visualização")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Sua família vê apenas: onde você está, ETA e status. Nenhum dado de carga ou rota completa.")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(3)
                }
            }
            .padding(14)
            .background(AppTheme.Colors.accent.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.Colors.accent.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 20)

            // Family view preview card
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.accent)
                            .frame(width: 42, height: 42)
                        Image(systemName: "truck.box.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Motorista está na estrada")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Atualizado agora · Trucker Easy")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    Spacer()
                    // Status dot
                    Circle()
                        .fill(Color(hex: "#10b981"))
                        .frame(width: 10, height: 10)
                }

                Divider().background(AppTheme.Colors.textSecondary.opacity(0.15))

                if let route = route {
                    familyInfoRow(icon: "clock.fill", color: Color(hex: "#10b981"),
                                  label: "ETA", value: etaString(for: route))
                    familyInfoRow(icon: "road.lanes", color: AppTheme.Colors.accent,
                                  label: "Restante", value: regionalSettings.formatDistance(route.distance))
                }
                if let trip = trip, let dest = trip.endLocation {
                    familyInfoRow(icon: "mappin.and.ellipse", color: Color(hex: "#ef4444"),
                                  label: "Destino", value: dest)
                }

                // Driver note
                if !driverNote.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.accent)
                        Text(driverNote)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .background(AppTheme.Colors.accent.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(AppTheme.Colors.backgroundCard)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.Colors.backgroundCard, lineWidth: 1))
            .padding(.horizontal, 20)

            // Note to family
            VStack(alignment: .leading, spacing: 6) {
                Label("Mensagem para a família (opcional)", systemImage: "message")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                TextField("Ex: Tudo bem, chego em algumas horas!", text: $driverNote)
                    .foregroundColor(.white)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(AppTheme.Colors.backgroundInput)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 20)

            // Share actions
            VStack(spacing: 10) {
                // WhatsApp / Messages style share
                Button(action: {
                    shareItems = [buildFamilyPayload()]
                    showingShareSheet = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Compartilhar com Família")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.Colors.accent)
                    .cornerRadius(14)
                }

                // Copy link
                Button(action: copyFamilyLink) {
                    HStack(spacing: 8) {
                        Image(systemName: copiedLink ? "checkmark" : "link")
                            .font(.system(size: 14, weight: .bold))
                        Text(copiedLink ? "Link Copiado!" : "Copiar Link de Rastreamento")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(copiedLink ? AppTheme.Colors.success : AppTheme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(copiedLink ? AppTheme.Colors.success.opacity(0.1) : AppTheme.Colors.accent.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(copiedLink ? AppTheme.Colors.success.opacity(0.4) : AppTheme.Colors.accent.opacity(0.3), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Dispatcher Tab

    private var dispatcherTab: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                if let loc = locationManager.currentLocation {
                    familyInfoRow(icon: "location.fill", color: AppTheme.Colors.accent,
                                  label: "GPS", value: String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                    familyInfoRow(icon: "speedometer", color: AppTheme.Colors.textSecondary,
                                  label: "Velocidade", value: String(format: "%.0f mph", max(0, loc.speed) * 2.237))
                }
                if let route = route {
                    familyInfoRow(icon: "clock.fill", color: Color(hex: "#10b981"),
                                  label: "ETA", value: etaString(for: route))
                    familyInfoRow(icon: "road.lanes", color: AppTheme.Colors.accent,
                                  label: "Restante", value: regionalSettings.formatDistance(route.distance))
                }
            }
            .padding(16)
            .background(AppTheme.Colors.backgroundCard)
            .cornerRadius(14)
            .padding(.horizontal, 20)

            TextField("Nota para o dispatcher...", text: $driverNote)
                .foregroundColor(.white)
                .font(.system(size: 14))
                .padding(10)
                .background(AppTheme.Colors.backgroundInput)
                .cornerRadius(10)
                .padding(.horizontal, 20)

            Button(action: {
                shareItems = [buildDispatcherPayload()]
                showingShareSheet = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Enviar Status ao Dispatcher")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "#6366f1"))
                .cornerRadius(14)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func tabButton(_ title: String, icon: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(selectedTab == index ? .white : AppTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selectedTab == index ? AppTheme.Colors.accent : Color.clear)
            .cornerRadius(9)
        }
    }

    private func familyInfoRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color).frame(width: 20)
            Text(label).font(.system(size: 13)).foregroundColor(AppTheme.Colors.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
        }
    }

    private func copyFamilyLink() {
        UIPasteboard.general.string = buildFamilyPayload()
        withAnimation { copiedLink = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { copiedLink = false }
    }

    private func etaString(for route: MKRoute) -> String {
        let seconds = route.expectedTravelTime
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes) min"
    }

    private func buildFamilyPayload() -> String {
        var lines: [String] = ["🚛 Trucker Easy — Localização do Motorista"]
        lines.append("📡 Última atualização: \(Date().formatted(date: .omitted, time: .shortened))")
        if let route = route {
            lines.append("⏱ ETA: \(etaString(for: route))")
            lines.append("📏 Distância restante: \(regionalSettings.formatDistance(route.distance))")
        }
        if let trip = trip, let dest = trip.endLocation {
            lines.append("🏁 Destino: \(dest)")
        }
        if !driverNote.isEmpty { lines.append("💬 \(driverNote)") }
        lines.append("\n✅ Seguro na estrada com Trucker Easy")
        return lines.joined(separator: "\n")
    }

    private func buildDispatcherPayload() -> String {
        var lines: [String] = ["📍 STATUS DO MOTORISTA — TRUCKER EASY"]
        if let loc = locationManager.currentLocation {
            lines.append("GPS: \(String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))")
            let speed = String(format: "%.0f mph", max(0, loc.speed) * 2.237)
            lines.append("Velocidade: \(speed)")
        }
        if let route = route {
            lines.append("ETA: \(etaString(for: route)) | Restante: \(regionalSettings.formatDistance(route.distance))")
        }
        if !driverNote.isEmpty { lines.append("Nota: \(driverNote)") }
        lines.append("Horário: \(Date().formatted())")
        return lines.joined(separator: "\n")
    }
}

private struct InfoRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
}

/// UIKit UIActivityViewController wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Logistics News (Geo-fenced by country, not driver language)

struct LogisticsNewsItem: Identifiable {
    let id = UUID()
    let headline: String
    let summary: String
    let source: String
    let publishedAt: Date
    let country: String        // ISO country code detected from geofence
    let category: NewsCategory
    let url: String?

    enum NewsCategory: String {
        case regulations = "Regulations"
        case fuel        = "Fuel"
        case weather     = "Weather Alert"
        case strike      = "Strike / Labor"
        case roads       = "Roads"
        case industry    = "Industry"

        var icon: String {
            switch self {
            case .regulations: return "doc.text.fill"
            case .fuel:        return "fuelpump.fill"
            case .weather:     return "cloud.bolt.fill"
            case .strike:      return "person.3.fill"
            case .roads:       return "road.lanes"
            case .industry:    return "building.2.fill"
            }
        }

        var color: Color {
            switch self {
            case .regulations: return Color(hex: "#6366f1")
            case .fuel:        return Color(hex: "#f59e0b")
            case .weather:     return Color(hex: "#0ea5e9")
            case .strike:      return Color(hex: "#ef4444")
            case .roads:       return Color(hex: "#10b981")
            case .industry:    return Color(hex: "#a855f7")
            }
        }
    }
}

/// Detects the driver's country from GPS coordinates (geofence) and returns
/// relevant logistics/trucking news for that country.
/// When real RSS/API feeds are added, replace `loadStubNews(for:)` body only.
@Observable
final class LogisticsNewsService {
    static let shared = LogisticsNewsService()

    private(set) var items: [LogisticsNewsItem] = []
    private(set) var detectedCountry: String = ""   // e.g. "US", "BR", "MX"
    private(set) var isLoading = false
    private var lastRefreshCoordinate: CLLocationCoordinate2D?

    /// Load default news immediately when no location is available yet.
    /// Uses language to pick the most relevant country stub.
    func loadDefaultIfEmpty(language: AppLanguage = .english) async {
        guard items.isEmpty && !isLoading else { return }
        isLoading = true
        let country = defaultCountry(for: language)
        let news = await loadRealNews(for: country)
        await MainActor.run {
            if items.isEmpty {
                detectedCountry = ""
                items = news
            }
            isLoading = false
        }
    }

    /// Refresh news content when the user manually changes language.
    func refreshForLanguage(_ language: AppLanguage) async {
        guard !isLoading else { return }
        isLoading = true
        let country = !detectedCountry.isEmpty ? detectedCountry : defaultCountry(for: language)
        let news = await loadRealNews(for: country, language: language)
        await MainActor.run {
            items = news
            isLoading = false
        }
    }

    /// Map language to a default country code for news fetching
    private func defaultCountry(for language: AppLanguage) -> String {
        switch language {
        case .portuguese:   return "BR"
        case .spanishLatam: return "MX"
        case .spanish:      return "MX"
        default:            return "US"
        }
    }

    /// Refresh news for the given GPS coordinate.
    /// Country is resolved via reverse geocode — NOT driver language.
    func refresh(for coordinate: CLLocationCoordinate2D) async {
        // Avoid hammering the service on every location tick
        if let last = lastRefreshCoordinate {
            let prev = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let curr = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard curr.distance(from: prev) > 80_000 else { return }  // refresh every ~80 km
        }
        guard !isLoading else { return }
        isLoading = true
        lastRefreshCoordinate = coordinate

        // Resolve country from coordinates (geofence, not language)
        let country = await resolveCountry(for: coordinate)

        // Load news via official RSS feeds — falls back to curated content
        let news = await loadRealNews(for: country)

        await MainActor.run {
            detectedCountry = country
            items = news
            isLoading = false
        }
    }

    // MARK: Geo-resolve country from coordinates

    private func resolveCountry(for coordinate: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return "US" }
            return await withCheckedContinuation { continuation in
                request.getMapItems { mapItems, _ in
                    if let repr = mapItems?.first?.addressRepresentations,
                       let region = repr.region {
                        continuation.resume(returning: region.identifier.uppercased().prefix(2).description)
                    } else {
                        continuation.resume(returning: "US")
                    }
                }
            }
        } else {
            do {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                return placemarks.first?.isoCountryCode?.uppercased() ?? "US"
            } catch {
                return "US"
            }
        }
    }

    // MARK: - News: real RSS feeds + curated fallback

    /// Primary: fetch from official government/trucking RSS feeds.
    /// Falls back to curated content when RSS is unavailable.
    private func loadRealNews(for country: String, language: AppLanguage? = nil) async -> [LogisticsNewsItem] {
        let effectiveCountry: String
        if let lang = language {
            switch lang {
            case .portuguese:               effectiveCountry = "BR"
            case .spanishLatam, .spanish:   effectiveCountry = "MX"
            default:                        effectiveCountry = country
            }
        } else {
            effectiveCountry = country
        }

        // Official government and industry RSS feeds — free, no API key required
        let feedURLs: [String]
        switch effectiveCountry {
        case "US":
            // Feeds free, sem chave, que RESPONDEM 200 (testados ao vivo 16/06). FMCSA e Overdrive
            // dão 403 (bloqueiam bot) — trocados pelos que funcionam de verdade.
            feedURLs = [
                "https://www.freightwaves.com/news/feed",
                "https://www.ttnews.com/rss.xml"
            ]
        case "CA":
            feedURLs = ["https://www.tc.gc.ca/en/news/rss.xml"]
        case "BR":
            feedURLs = ["https://cnt.org.br/feed"]
        case "MX":
            feedURLs = ["https://www.gob.mx/sct/rss"]
        default:
            feedURLs = []
        }

        for urlString in feedURLs {
            guard let url = URL(string: urlString) else { continue }
            if let items = await fetchRSSFeed(from: url, country: effectiveCountry) {
                return items
            }
        }

        // Sem feed real → VAZIO (honesto). Antes retornava `curatedFallbackNews`, com fontes e
        // timestamps SINTÉTICOS ("CDOT · 15 min atrás") apresentados ao motorista como reais/recentes.
        // Melhor seção vazia do que notícia fabricada. (curatedFallbackNews fica como dead code.)
        return []
    }

    /// Downloads and parses an RSS 2.0 / Atom feed, returns nil on any failure.
    private func fetchRSSFeed(from url: URL, country: String) async -> [LogisticsNewsItem]? {
        do {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            let entries = SimpleRSSParser().parse(data: data)
            guard !entries.isEmpty else { return nil }
            let items: [LogisticsNewsItem] = entries.prefix(6).compactMap { entry in
                guard !entry.title.isEmpty else { return nil }
                return LogisticsNewsItem(
                    headline: entry.title,
                    summary: entry.summary ?? "",
                    source: url.host?.replacingOccurrences(of: "www.", with: "") ?? "Official Source",
                    publishedAt: entry.pubDate ?? Date(),
                    country: country,
                    category: classifyNewsTitle(entry.title),
                    url: entry.link
                )
            }
            return items.isEmpty ? nil : items
        } catch {
            return nil
        }
    }

    private func classifyNewsTitle(_ title: String) -> LogisticsNewsItem.NewsCategory {
        let t = title.lowercased()
        if t.contains("fuel") || t.contains("diesel") || t.contains("combustível") || t.contains("preço") { return .fuel }
        if t.contains("weather") || t.contains("snow") || t.contains("ice") || t.contains("storm") || t.contains("chuva") { return .weather }
        if t.contains("strike") || t.contains("labor") || t.contains("greve") || t.contains("huelga") { return .strike }
        if t.contains("road") || t.contains("highway") || t.contains("closure") || t.contains("rodovia") { return .roads }
        if t.contains("rule") || t.contains("regulation") || t.contains("fmcsa") || t.contains("antt") { return .regulations }
        return .industry
    }

    // MARK: - Curated fallback content (used when RSS feeds are unavailable)

    private func curatedFallbackNews(for country: String, language: AppLanguage? = nil) -> [LogisticsNewsItem] {
        let effectiveCountry: String
        if let lang = language {
            switch lang {
            case .portuguese:   effectiveCountry = "BR"
            case .spanishLatam: effectiveCountry = "MX"
            case .spanish:      effectiveCountry = "MX"
            default:            effectiveCountry = country
            }
        } else {
            effectiveCountry = country
        }

        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        switch effectiveCountry {
        case "US":
            return [
                LogisticsNewsItem(headline: "FMCSA Proposes New HOS Electronic Logging Exemptions",
                                  summary: "The Federal Motor Carrier Safety Administration is seeking comments on proposed exemptions for ELD mandate compliance for short-haul operators.",
                                  source: "FreightWaves", publishedAt: ago(40), country: effectiveCountry, category: .regulations, url: nil),
                LogisticsNewsItem(headline: "Diesel Prices Drop 3¢ Nationally – Highest in CA",
                                  summary: "National average diesel fell to $3.89/gal this week. California remains highest at $4.82/gal due to refinery maintenance.",
                                  source: "DOE EIA", publishedAt: ago(120), country: effectiveCountry, category: .fuel, url: nil),
                LogisticsNewsItem(headline: "I-70 Eastbound Closed at Vail Pass – Chain Law in Effect",
                                  summary: "CDOT has closed I-70 EB at Vail Pass due to whiteout conditions. Chain law is in effect for commercial vehicles on the entire corridor.",
                                  source: "CDOT", publishedAt: ago(15), country: effectiveCountry, category: .weather, url: nil),
                LogisticsNewsItem(headline: "Port of Los Angeles Dockworkers Vote on New Contract",
                                  summary: "ILWU members at the Port of LA and Long Beach are voting on a tentative agreement that would end work-to-rule actions affecting container flow.",
                                  source: "JOC", publishedAt: ago(200), country: effectiveCountry, category: .strike, url: nil),
                LogisticsNewsItem(headline: "Texas Oversize Load Permit Fees Increase March 15",
                                  summary: "TxDMV updates blanket permit fees for single-trip and annual oversize/overweight permits effective March 15.",
                                  source: "TxDMV", publishedAt: ago(300), country: effectiveCountry, category: .regulations, url: nil),
            ]

        case "BR":
            return [
                LogisticsNewsItem(headline: "ANTT Lança Nova Plataforma de Controle de Jornada",
                                  summary: "A Agência Nacional de Transportes Terrestres liberou acesso ao novo portal de monitoramento de jornada dos motoristas profissionais.",
                                  source: "ANTT", publishedAt: ago(90), country: effectiveCountry, category: .regulations, url: nil),
                LogisticsNewsItem(headline: "Greve de Caminhoneiros: Bloqueios na BR-116",
                                  summary: "Caminhoneiros autônomos realizaram bloqueios parciais na BR-116 em protesto ao preço do diesel. PRF acompanha situação.",
                                  source: "CNT", publishedAt: ago(30), country: effectiveCountry, category: .strike, url: nil),
                LogisticsNewsItem(headline: "Diesel S-10 Sobe R$0,12 nas Bombas da Região Sul",
                                  summary: "O preço médio do diesel S-10 registrou alta de R$0,12 por litro na Região Sul nas últimas 48 horas, segundo levantamento da ANP.",
                                  source: "ANP", publishedAt: ago(180), country: effectiveCountry, category: .fuel, url: nil),
                LogisticsNewsItem(headline: "Operação Especial DNIT: Pesagem em Foco na BR-101",
                                  summary: "DNIT intensifica fiscalização de excesso de peso na BR-101 trecho RJ-ES com postos de pesagem móveis.",
                                  source: "DNIT", publishedAt: ago(240), country: effectiveCountry, category: .regulations, url: nil),
            ]

        case "MX":
            return [
                LogisticsNewsItem(headline: "SCT Actualiza Límites de Peso en Carreteras Federales",
                                  summary: "La Secretaría de Infraestructura actualiza los límites de peso permitido para vehículos de carga en carreteras federales de cuota.",
                                  source: "SCT México", publishedAt: ago(60), country: effectiveCountry, category: .regulations, url: nil),
                LogisticsNewsItem(headline: "Precio del Diésel Sube 2% en la Frontera Norte",
                                  summary: "El precio del diésel en la región fronteriza norte registró un incremento del 2% esta semana según la CRE.",
                                  source: "CRE", publishedAt: ago(150), country: effectiveCountry, category: .fuel, url: nil),
                LogisticsNewsItem(headline: "Operativo en Autopista México-Puebla: Retención de Unidades",
                                  summary: "La Guardia Nacional realiza operativo de verificación de documentación en la autopista México-Puebla. Se prevén demoras de 45 minutos.",
                                  source: "Guardia Nacional", publishedAt: ago(20), country: effectiveCountry, category: .roads, url: nil),
            ]

        case "CA":
            return [
                LogisticsNewsItem(headline: "Transport Canada Proposes Mandatory Speed Limiters at 105 km/h",
                                  summary: "Transport Canada has published proposed amendments requiring all new heavy trucks to have speed limiters set to 105 km/h.",
                                  source: "Transport Canada", publishedAt: ago(100), country: effectiveCountry, category: .regulations, url: nil),
                LogisticsNewsItem(headline: "Diesel Average $1.74/L Nationally – BC Highest at $1.98",
                                  summary: "Diesel averages $1.74 per litre nationally this week. British Columbia remains highest driven by carbon levy.",
                                  source: "NRCan", publishedAt: ago(220), country: effectiveCountry, category: .fuel, url: nil),
                LogisticsNewsItem(headline: "Hwy 1 Rogers Pass Restricted to Commercial Traffic",
                                  summary: "BC Ministry of Transportation has restricted commercial traffic on Hwy 1 at Rogers Pass to chains-required between 06:00–18:00.",
                                  source: "DriveBC", publishedAt: ago(50), country: effectiveCountry, category: .weather, url: nil),
            ]

        default:
            return [
                LogisticsNewsItem(headline: "Global Freight Rates Rise for Third Consecutive Week",
                                  summary: "Container shipping rates on major trade lanes continued their upward trend for the third consecutive week amid Red Sea diversions.",
                                  source: "Drewry", publishedAt: ago(80), country: effectiveCountry, category: .industry, url: nil),
                LogisticsNewsItem(headline: "IEA: Diesel Demand Forecast Revised Upward for Q2",
                                  summary: "The International Energy Agency revised its Q2 diesel demand forecast upward by 1.2%, citing stronger-than-expected road freight growth.",
                                  source: "IEA", publishedAt: ago(300), country: effectiveCountry, category: .fuel, url: nil),
            ]
        }
    }
}

// MARK: - Simple RSS / Atom XML Parser

private final class SimpleRSSParser: NSObject, XMLParserDelegate {
    struct Entry {
        var title: String = ""
        var summary: String?
        var link: String?
        var pubDate: Date?
    }

    private(set) var entries: [Entry] = []
    private var current: Entry?
    private var element: String = ""
    private var buffer: String = ""

    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    func parse(data: Data) -> [Entry] {
        entries = []
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        element = name.lowercased()
        buffer = ""
        if element == "item" || element == "entry" { current = Entry() }
        // Atom <link href="...">
        if element == "link", let href = attributes["href"], current != nil {
            current?.link = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        let el = name.lowercased()
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != nil else { return }
        switch el {
        case "title":
            current?.title = stripTags(text)
        case "description", "summary", "content:encoded", "content":
            let stripped = stripTags(text)
            if current?.summary == nil || (current?.summary?.isEmpty == true) {
                current?.summary = stripped
            }
        case "link" where current?.link == nil:
            if !text.isEmpty { current?.link = text }
        case "pubdate", "published", "updated":
            current?.pubDate = parseDate(text)
        case "item", "entry":
            if let e = current, !e.title.isEmpty { entries.append(e) }
            current = nil
        default: break
        }
    }

    private func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
         .replacingOccurrences(of: "&amp;",  with: "&")
         .replacingOccurrences(of: "&lt;",   with: "<")
         .replacingOccurrences(of: "&gt;",   with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseDate(_ s: String) -> Date? {
        if let d = SimpleRSSParser.rfc822.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - Logistics News Feed View (embedded in HorizonView / My Horizon)

struct LogisticsNewsFeed: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @State private var service = LogisticsNewsService.shared

    var lang: AppLanguage { regionalSettings.currentLanguage }

    var newsHeaderLabel: String {
        switch lang {
        case .portuguese:   return "Notícias de Logística"
        case .spanish, .spanishLatam: return "Noticias de Logística"
        case .french:       return "Actualités Logistique"
        case .german:       return "Logistik-Nachrichten"
        case .hindi:        return "लॉजिस्टिक्स समाचार"
        case .arabic:       return "أخبار اللوجستيات"
        case .russian:      return "Логистические новости"
        case .polish:       return "Wiadomości logistyczne"
        default:            return "Logistics News"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#00d4c8"))
                Text(newsHeaderLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                if !service.detectedCountry.isEmpty {
                    Text("· \(service.detectedCountry)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()
                if service.isLoading {
                    ProgressView()
                        .te_uniformScale(0.7)
                        .tint(Color(hex: "#00d4c8"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            if service.items.isEmpty && !service.isLoading {
                Text("Loading news…")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 1) {
                    ForEach(service.items) { item in
                        LogisticsNewsRow(item: item)
                        if item.id != service.items.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 0)
            }
        }
        .task {
            // Load default content immediately so the feed is never blank on first open.
            // When the location becomes available, ViewsHorizonView will call refresh(for:)
            // which will replace this with geo-fenced content.
            await service.loadDefaultIfEmpty(language: lang)
        }
        .onChange(of: lang) { _, newLang in
            Swift.Task { await service.refreshForLanguage(newLang) }
        }
    }
}

private struct LogisticsNewsRow: View {
    let item: LogisticsNewsItem
    @State private var expanded = false

    var body: some View {
        Button(action: { withAnimation(.spring(response: 0.3)) { expanded.toggle() } }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    // Category icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(item.category.color.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: item.category.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(item.category.color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.headline)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(expanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(item.source)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(item.category.color)
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                            Text(item.timeAgo)
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .padding(.top, 4)
                }

                if expanded {
                    Text(item.summary)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .padding(.leading, 42)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

private extension LogisticsNewsItem {
    var timeAgo: String {
        let interval = Date().timeIntervalSince(publishedAt)
        if interval < 60    { return "just now" }
        if interval < 3600  { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
