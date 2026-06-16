import SwiftUI
import SwiftData
import CoreLocation
import MapKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - News Article Model
struct NewsArticle: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String?
    let url: String
    let urlToImage: String?
    let publishedAt: String
    let source: NewsSource

    struct NewsSource: Codable {
        let name: String
    }
}

struct NewsResponse: Codable {
    let status: String?
    let totalResults: Int?
    let articles: [NewsArticle]
}

// NewsAPI returns this on error (e.g. invalid key, rate limit)
struct NewsAPIError: Decodable {
    let status: String
    let code: String?
    let message: String
}

// MARK: - AI Chat Message
struct EasyMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp = Date()
}

// MARK: - Road Talk View (Tab 4)
struct RoadTalkView: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @State private var selectedSection: RoadTalkSection = .ptt

    enum RoadTalkSection: CaseIterable {
        case ptt, radio, news, report, community, chat

        func label(lang: AppLanguage) -> String {
            switch self {
            case .ptt:       return "📻 Ch.19"
            case .radio:     return CommunityTheme.current.isCopa ? "🎧 Copa" : "🎧 Rádio"
            case .news:      return lang.roadTalkNewsLabel
            case .report:    return lang.roadTalkReportLabel
            case .community: return lang.roadTalkCommunityLabel
            case .chat:      return lang.roadTalkAILabel
            }
        }
    }

    var lang: AppLanguage { regionalSettings.currentLanguage }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // MARK: Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(lang.tabRoadTalk)
                                    .font(AppTheme.Typography.heroTitle())
                                    .foregroundColor(.white)
                                // Tema Copa 2026 (auto-reverte pra logística após 19/07) — só um toque visual.
                                Image(systemName: CommunityTheme.current.icon)
                                    .foregroundColor(CommunityTheme.current.accent)
                            }
                            Text(CommunityTheme.current.isCopa ? CommunityTheme.current.subtitle : lang.roadTalkSubtitle)
                                .font(AppTheme.Typography.caption())
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.md)

                    // Section Picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(RoadTalkSection.allCases, id: \.self) { section in
                                Button(action: { withAnimation { selectedSection = section } }) {
                                    VStack(spacing: 6) {
                                        Text(section.label(lang: lang))
                                            .font(AppTheme.Typography.bodyBold())
                                            .foregroundColor(selectedSection == section ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
                                        Rectangle()
                                            .fill(selectedSection == section ? AppTheme.Colors.accent : Color.clear)
                                            .frame(height: 2)
                                            .cornerRadius(1)
                                    }
                                    .padding(.horizontal, AppTheme.Spacing.md)
                                }
                            }
                        }
                    }
                    .padding(.top, AppTheme.Spacing.sm)

                    Divider()
                        .background(AppTheme.Colors.textSecondary.opacity(0.2))

                    // Content
                    switch selectedSection {
                    case .radio:
                        RadioView(theme: CommunityTheme.current)
                    case .news:
                        ScrollView(showsIndicators: false) {
                            LogisticsNewsFeed()
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .padding(.top, AppTheme.Spacing.md)
                                .padding(.bottom, AppTheme.Spacing.lg)
                        }
                    case .report:
                        RoadReportPanel()
                    case .community:
                        CommunityView()
                    case .chat:
                        RoadTalkChatHubView()
                    case .ptt:
                        Channel19View()
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Rádio (ouvir ao vivo — Copa 2026 / notícias / música)
private struct RadioView: View {
    let theme: CommunityTheme
    @State private var radio = RadioService.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if theme.isCopa {
                    HStack(spacing: 10) {
                        Image(systemName: "soccerball").font(.system(size: 22))
                        Text("Copa 2026 está rolando! Sintonize e ouça os jogos na estrada. 🌎⚽")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(14)
                    .background(theme.accent.opacity(0.92))
                    .cornerRadius(14)
                }

                ForEach(radio.stations) { station in
                    let isCurrent = radio.currentStation == station
                    Button(action: { radio.toggle(station) }) {
                        HStack(spacing: 12) {
                            Image(systemName: isCurrent && radio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 34))
                                .foregroundColor(theme.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(station.name).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                                Text(station.genre).font(.system(size: 12)).foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                            if isCurrent && radio.isBuffering {
                                ProgressView().tint(theme.accent)
                            } else if isCurrent && radio.isPlaying {
                                Image(systemName: "waveform").foregroundColor(theme.accent)
                            }
                        }
                        .padding(14)
                        .background(AppTheme.Colors.backgroundCard)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(isCurrent ? theme.accent.opacity(0.6) : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }

                Text("Estações são atualizáveis sem novo update do app — a do jogo entra quando o stream estiver no ar.")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.md)
        }
    }
}

private struct RoadTalkChatHubView: View {
    @State private var selectedMode: ChatMode = .drivers

    enum ChatMode: String, CaseIterable {
        case drivers = "Drivers"
        case ai = "Easy AI"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Chat Mode", selection: $selectedMode) {
                ForEach(ChatMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)

            if selectedMode == .drivers {
                ChatView()
            } else {
                EasyAIChat()
            }
        }
    }
}

// MARK: - Road Report Panel

struct RoadReportPanel: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @State private var locationManager = LocationManager()
    @State private var submittedType: RoadReportType? = nil
    @State private var showingConfirmation = false
    @State private var recentReports: [RoadReportRecord] = []
    @State private var isLoadingRecentReports = false

    var lang: AppLanguage { regionalSettings.currentLanguage }
    var reportInfoBannerText: String { lang.reportInfoBannerText }
    var reportSectionParkingText: String { lang.reportSectionParkingText }
    var reportSectionWeighText: String { lang.reportSectionWeighText }
    var reportSectionAlertsText: String { lang.reportSectionAlertsText }
    var recentReportsText: String { lang.recentReportsText }

    enum RoadReportType: String, CaseIterable, Identifiable {
        case parkingFull      = "parkingFull"
        case parkingAvailable = "parkingAvailable"
        case scaleOpen        = "scaleOpen"
        case scaleClosed      = "scaleClosed"
        case hazard           = "hazard"
        case roadCondition    = "roadCondition"
        case mechanical       = "mechanical"
        case police           = "police"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .parkingFull:      return "p.circle.fill"
            case .parkingAvailable: return "p.circle"
            case .scaleOpen:        return "scalemass.fill"
            case .scaleClosed:      return "scalemass"
            case .hazard:           return "exclamationmark.triangle.fill"
            case .roadCondition:    return "cloud.bolt.road.lane.fill"
            case .mechanical:       return "wrench.and.screwdriver.fill"
            case .police:           return "car.side.fill"
            }
        }

        var color: Color {
            switch self {
            case .parkingFull:      return Color(hex: "#ef4444")
            case .parkingAvailable: return Color(hex: "#10b981")
            case .scaleOpen:        return Color(hex: "#ef4444")
            case .scaleClosed:      return Color(hex: "#10b981")
            case .hazard:           return Color(hex: "#f59e0b")
            case .roadCondition:    return Color(hex: "#6366f1")
            case .mechanical:       return Color(hex: "#f97316")
            case .police:           return Color(hex: "#64748b")
            }
        }

        func title(lang: AppLanguage) -> String {
            switch self {
            case .parkingFull:      return lang.reportParkingFull
            case .parkingAvailable: return lang.reportParkingAvailable
            case .scaleOpen:        return lang.reportScaleOpen
            case .scaleClosed:      return lang.reportScaleClosed
            case .hazard:           return lang.reportHazard
            case .roadCondition:    return lang.reportRoadCondition
            case .mechanical:       return lang.reportMechanical
            case .police:           return lang.reportPolice
            }
        }

        func subtitle(lang: AppLanguage) -> String {
            switch self {
            case .parkingFull:      return lang.reportSubParkingFull
            case .parkingAvailable: return lang.reportSubParkingAvailable
            case .scaleOpen:        return lang.reportSubScaleOpen
            case .scaleClosed:      return lang.reportSubScaleClosed
            case .hazard:           return lang.reportSubHazard
            case .roadCondition:    return lang.reportSubRoadCondition
            case .mechanical:       return lang.reportSubMechanical
            case .police:           return lang.reportSubPolice
            }
        }
    }

    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let mockReports: [MockRoadReport] = [
        MockRoadReport(type: .scaleOpen, location: "I-80 MM 342", minutesAgo: 12, votes: 5),
        MockRoadReport(type: .parkingFull, location: "TA Truckstop Exit 44", minutesAgo: 28, votes: 3),
        MockRoadReport(type: .hazard, location: "I-40 WB", minutesAgo: 60, votes: 7)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {

                // Info banner
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(AppTheme.Colors.accent)
                        .font(.system(size: 16))
                    Text(reportInfoBannerText)
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(AppTheme.Spacing.sm)
                .background {
                    AppTheme.Colors.accent.opacity(0.08)
                }
                .cornerRadius(AppTheme.Radius.sm)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.md)

                // Section: Parking
                ReportSectionHeader(title: reportSectionParkingText, icon: "p.circle.fill", color: .green)
                LazyVGrid(columns: columns, spacing: 12) {
                    ReportButton(type: .parkingAvailable, lang: lang) { submit(.parkingAvailable) }
                    ReportButton(type: .parkingFull, lang: lang)      { submit(.parkingFull) }
                }
                .padding(.horizontal, AppTheme.Spacing.md)

                // Section: Weigh Station
                ReportSectionHeader(title: reportSectionWeighText, icon: "scalemass.fill", color: Color(hex: "#ef4444"))
                LazyVGrid(columns: columns, spacing: 12) {
                    ReportButton(type: .scaleOpen, lang: lang)   { submit(.scaleOpen) }
                    ReportButton(type: .scaleClosed, lang: lang) { submit(.scaleClosed) }
                }
                .padding(.horizontal, AppTheme.Spacing.md)

                // Section: Road Alerts
                ReportSectionHeader(title: reportSectionAlertsText, icon: "exclamationmark.triangle.fill", color: Color(hex: "#f59e0b"))
                LazyVGrid(columns: columns, spacing: 12) {
                    ReportButton(type: .hazard, lang: lang)        { submit(.hazard) }
                    ReportButton(type: .roadCondition, lang: lang) { submit(.roadCondition) }
                    ReportButton(type: .mechanical, lang: lang)    { submit(.mechanical) }
                    ReportButton(type: .police, lang: lang)        { submit(.police) }
                }
                .padding(.horizontal, AppTheme.Spacing.md)

                // Recent reports placeholder
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.accent)
                        Text(recentReportsText)
                            .font(AppTheme.Typography.small())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .kerning(1.5)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)

                    VStack(spacing: 8) {
                        if isLoadingRecentReports && recentReports.isEmpty {
                            ProgressView()
                                .tint(AppTheme.Colors.accent)
                                .padding(.vertical, AppTheme.Spacing.md)
                        } else if recentReports.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 28))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                Text("No recent reports in your area")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                Text("Be the first to report!")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.lg)
                        } else {
                            ForEach(recentReports) { report in
                                RemoteReportRow(record: report, lang: lang)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                }

                Spacer(minLength: AppTheme.Spacing.xxl)
            }
        }
        .alert(lang.reportSubmittedTitle, isPresented: $showingConfirmation) {
            Button(lang.okLabel, role: .cancel) {}
        } message: {
            Text(lang.reportSubmissionAlertMessage(for: submittedType?.title(lang: lang)))
        }
        .task {
            locationManager.requestPermission()
            locationManager.startTracking()
            await loadRecentReports()
        }
        .onDisappear {
            locationManager.stopTracking()
        }
    }

    private func submit(_ type: RoadReportType) {
        submittedType = type
        showingConfirmation = true

        guard let coordinate = locationManager.currentLocation?.coordinate else { return }
        Task {
            let payload = RoadReportPayload(
                driver_id: SupabaseClient.shared.currentDriverId,
                report_type: type.rawValue,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                location_name: nil
            )
            do {
                try await SupabaseClient.shared.submitRoadReport(payload)
                await loadRecentReports()
            } catch {
                #if DEBUG
                print("RoadReportPanel: failed to submit report — \(error.localizedDescription)")
                #endif
            }
        }
    }

    @MainActor
    private func loadRecentReports() async {
        guard let coordinate = locationManager.currentLocation?.coordinate else { return }
        isLoadingRecentReports = true
        defer { isLoadingRecentReports = false }
        do {
            recentReports = try await SupabaseClient.shared.fetchRecentRoadReports(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radiusKm: 160
            )
        } catch {
            #if DEBUG
            print("RoadReportPanel: failed to fetch recent reports — \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Report Button

struct ReportButton: View {
    let type: RoadReportPanel.RoadReportType
    let lang: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(type.color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: type.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(type.color)
                }
                Text(type.title(lang: lang))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(type.subtitle(lang: lang))
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.Colors.backgroundCard)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(type.color.opacity(0.25), lineWidth: 1)
            )
        }
    }
}

// MARK: - Report Section Header

struct ReportSectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.5)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }
}

// MARK: - Mock Report Row (placeholder for real feed)

struct MockReportRow: View {
    let report: MockRoadReport
    let lang: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(report.type.color.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: report.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(report.type.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(report.type.title(lang: lang)) — \(report.location)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(lang.relativeTimeLabel(minutesAgo: report.minutesAgo))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.Colors.accent)
                Text("\(report.votes)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.accent)
            }
        }
        .padding(10)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.sm)
    }
}

struct MockRoadReport: Identifiable {
    let id = UUID()
    let type: RoadReportPanel.RoadReportType
    let location: String
    let minutesAgo: Int
    let votes: Int
}

struct RemoteReportRow: View {
    let record: RoadReportRecord
    let lang: AppLanguage

    private var reportType: RoadReportPanel.RoadReportType? {
        RoadReportPanel.RoadReportType(rawValue: record.report_type)
    }

    private var reportedDate: Date? {
        ISO8601DateFormatter().date(from: record.reported_at)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((reportType?.color ?? AppTheme.Colors.accent).opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: reportType?.icon ?? "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(reportType?.color ?? AppTheme.Colors.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(relativeTimeText)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.Colors.accent)
                Text("\(record.confirmations ?? 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.accent)
            }
        }
        .padding(10)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.sm)
    }

    private var rowTitle: String {
        let title = reportType?.title(lang: lang) ?? record.report_type
        if let locationName = record.location_name, !locationName.isEmpty {
            return "\(title) — \(locationName)"
        }
        return title
    }

    private var relativeTimeText: String {
        guard let reportedDate else { return lang.justNowLabel }
        let minutes = max(1, Int(Date().timeIntervalSince(reportedDate) / 60))
        return lang.relativeTimeLabel(minutesAgo: minutes)
    }
}

private extension AppLanguage {
    var justNowLabel: String {
        switch self {
        case .english:      return "just now"
        case .portuguese:   return "agora mesmo"
        case .spanish:      return "justo ahora"
        case .spanishLatam: return "justo ahora"
        case .french:       return "à l'instant"
        case .german:       return "gerade eben"
        case .hindi:        return "अभी अभी"
        case .arabic:       return "الآن"
        case .russian:      return "только что"
        case .polish:       return "przed chwilą"
        }
    }

    var reportInfoBannerText: String {
        switch self {
        case .english:      return "Your reports are shared in real time with all drivers nearby."
        case .portuguese:   return "Seus alertas são compartilhados em tempo real com motoristas próximos."
        case .spanish:      return "Tus reportes se comparten en tiempo real con conductores cercanos."
        case .spanishLatam: return "Tus reportes se comparten en tiempo real con conductores cercanos."
        case .french:       return "Vos signalements sont partagés en temps réel avec les conducteurs proches."
        case .german:       return "Deine Meldungen werden in Echtzeit mit Fahrern in der Nähe geteilt."
        case .hindi:        return "आपकी रिपोर्ट पास के सभी चालकों के साथ रियल टाइम में शेयर होती है।"
        case .arabic:       return "يتم مشاركة تقاريرك في الوقت الفعلي مع السائقين القريبين."
        case .russian:      return "Ваши сообщения передаются в реальном времени ближайшим водителям."
        case .polish:       return "Twoje zgłoszenia są udostępniane w czasie rzeczywistym pobliskim kierowcom."
        }
    }

    var reportSectionParkingText: String {
        switch self {
        case .english:      return "PARKING"
        case .portuguese:   return "ESTACIONAMENTO"
        case .spanish:      return "ESTACIONAMIENTO"
        case .spanishLatam: return "ESTACIONAMIENTO"
        case .french:       return "PARKING"
        case .german:       return "PARKEN"
        case .hindi:        return "पार्किंग"
        case .arabic:       return "مواقف"
        case .russian:      return "ПАРКОВКА"
        case .polish:       return "PARKING"
        }
    }

    var reportSectionWeighText: String {
        switch self {
        case .english:      return "WEIGH STATION"
        case .portuguese:   return "POSTO DE PESAGEM"
        case .spanish:      return "ESTACIÓN DE PESAJE"
        case .spanishLatam: return "ESTACIÓN DE PESAJE"
        case .french:       return "STATION DE PESÉE"
        case .german:       return "WIEGESTATION"
        case .hindi:        return "वजन स्टेशन"
        case .arabic:       return "محطة الوزن"
        case .russian:      return "ВЕСОВАЯ"
        case .polish:       return "WAGA"
        }
    }

    var reportSectionAlertsText: String {
        switch self {
        case .english:      return "ROAD ALERTS"
        case .portuguese:   return "ALERTAS DE ESTRADA"
        case .spanish:      return "ALERTAS DE RUTA"
        case .spanishLatam: return "ALERTAS DE RUTA"
        case .french:       return "ALERTES ROUTIÈRES"
        case .german:       return "STRAßENWARNUNGEN"
        case .hindi:        return "सड़क अलर्ट"
        case .arabic:       return "تنبيهات الطريق"
        case .russian:      return "ДОРОЖНЫЕ ПРЕДУПРЕЖДЕНИЯ"
        case .polish:       return "OSTRZEŻENIA DROGOWE"
        }
    }

    var recentReportsText: String {
        switch self {
        case .english:      return "RECENT NEARBY REPORTS"
        case .portuguese:   return "ALERTAS RECENTES PRÓXIMOS"
        case .spanish:      return "REPORTES RECIENTES CERCANOS"
        case .spanishLatam: return "REPORTES RECIENTES CERCANOS"
        case .french:       return "SIGNALEMENTS RÉCENTS PROCHES"
        case .german:       return "AKTUELLE MELDUNGEN IN DER NÄHE"
        case .hindi:        return "हालिया नजदीकी रिपोर्ट"
        case .arabic:       return "التقارير الأخيرة القريبة"
        case .russian:      return "НЕДАВНИЕ СООБЩЕНИЯ ПОБЛИЗОСТИ"
        case .polish:       return "OSTATNIE RAPORTY W POBLIŻU"
        }
    }

    func relativeTimeLabel(minutesAgo: Int) -> String {
        if minutesAgo < 60 {
            switch self {
            case .english:      return "\(minutesAgo) min ago"
            case .portuguese:   return "há \(minutesAgo) min"
            case .spanish:      return "hace \(minutesAgo) min"
            case .spanishLatam: return "hace \(minutesAgo) min"
            case .french:       return "il y a \(minutesAgo) min"
            case .german:       return "vor \(minutesAgo) Min."
            case .hindi:        return "\(minutesAgo) मिनट पहले"
            case .arabic:       return "قبل \(minutesAgo) دقيقة"
            case .russian:      return "\(minutesAgo) мин назад"
            case .polish:       return "\(minutesAgo) min temu"
            }
        }

        let hoursAgo = minutesAgo / 60
        switch self {
        case .english:      return "\(hoursAgo)h ago"
        case .portuguese:   return "há \(hoursAgo)h"
        case .spanish:      return "hace \(hoursAgo)h"
        case .spanishLatam: return "hace \(hoursAgo)h"
        case .french:       return "il y a \(hoursAgo)h"
        case .german:       return "vor \(hoursAgo) Std."
        case .hindi:        return "\(hoursAgo) घंटे पहले"
        case .arabic:       return "قبل \(hoursAgo) ساعة"
        case .russian:      return "\(hoursAgo) ч назад"
        case .polish:       return "\(hoursAgo) godz. temu"
        }
    }

    func reportSubmissionAlertMessage(for reportTitle: String?) -> String {
        guard let reportTitle, !reportTitle.isEmpty else {
            return reportSubmittedMessage
        }

        switch self {
        case .english:      return "\"\(reportTitle)\". \(reportSubmittedMessage)"
        case .portuguese:   return "\"\(reportTitle)\" enviado. \(reportSubmittedMessage)"
        case .spanish:      return "\"\(reportTitle)\" enviado. \(reportSubmittedMessage)"
        case .spanishLatam: return "\"\(reportTitle)\" enviado. \(reportSubmittedMessage)"
        case .french:       return "\"\(reportTitle)\" envoyé. \(reportSubmittedMessage)"
        case .german:       return "\"\(reportTitle)\" gesendet. \(reportSubmittedMessage)"
        case .hindi:        return "\"\(reportTitle)\" भेजा गया। \(reportSubmittedMessage)"
        case .arabic:       return "تم إرسال \"\(reportTitle)\". \(reportSubmittedMessage)"
        case .russian:      return "\"\(reportTitle)\" отправлено. \(reportSubmittedMessage)"
        case .polish:       return "\"\(reportTitle)\" wysłano. \(reportSubmittedMessage)"
        }
    }
}

// MARK: - Trucking News Feed
// MARK: - NewsAPI Configuration
// Get your free key at: https://newsapi.org  (free: 100 req/day dev, 500/day business)
// Replace the placeholder below with your real key.
private enum NewsAPIConfig {
    // Add key "NewsAPIKey" to Info.plist — get a free key at https://newsapi.org
    static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "NewsAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // Trucking-focused query — covers freight, logistics, DOT, fuel
    static let query  = "trucking OR freight OR logistics OR FMCSA OR diesel fuel"
    static var endpoint: String {
        "https://newsapi.org/v2/everything?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&language=en&sortBy=publishedAt&pageSize=20&apiKey=\(apiKey)"
    }
}

struct TruckingNewsView: View {
    @State private var articles: [NewsArticle] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var locationManager = LocationManager()

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(AppTheme.Colors.accent)
                        .te_uniformScale(1.5)
                    Text("Loading trucking news...")
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .padding(.top, 12)
                    Spacer()
                }
            } else if articles.isEmpty {
                VStack(spacing: AppTheme.Spacing.md) {
                    Spacer()
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.Colors.accent.opacity(0.4))
                    Text("Trucking & Logistics News")
                        .font(AppTheme.Typography.cardTitle())
                        .foregroundColor(.white)
                    if let err = errorMessage {
                        Text(err)
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("No remote logistics news available yet")
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    TEButton("Try Again", icon: "arrow.clockwise", style: .primary) {
                        Task { await fetchNews() }
                    }
                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(articles) { article in
                            NewsArticleRow(article: article)
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }
            }
        }
        .task {
            locationManager.requestPermission()
            locationManager.startTracking()
            await fetchNews()
        }
        .onDisappear {
            locationManager.stopTracking()
        }
    }

    private func fetchNews() async {
        isLoading = true
        errorMessage = nil

        if await fetchSupabaseNews() {
            await MainActor.run {
                isLoading = false
            }
            return
        }

        guard !NewsAPIConfig.apiKey.isEmpty,
              NewsAPIConfig.apiKey != "YOUR_NEWSAPI_KEY" else {
            // Sem chave NewsAPI → usa RSS REAL (FreightWaves/Transport Topics). Não fica vazio nem inventa.
            await loadNewsFromRSS()
            return
        }

        guard let url = URL(string: NewsAPIConfig.endpoint) else {
            await loadNewsFromRSS()
            return
        }

        var request = URLRequest(url: url)
        request.setValue("TruckerEasyApp/2.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                guard let data = data,
                      let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let parsed = try? JSONDecoder().decode(NewsResponse.self, from: data)
                else {
                    // API error: show mock so the tab is never empty
                    if let apiError = data.flatMap({ try? JSONDecoder().decode(NewsAPIError.self, from: $0) }) {
                        errorMessage = apiError.message
                    } else {
                        errorMessage = error?.localizedDescription ?? "Failed to load news"
                    }
                    Task { await loadNewsFromRSS() }
                    return
                }
                articles = parsed.articles.filter { $0.title != "[Removed]" && !$0.title.isEmpty }
                if articles.isEmpty { Task { await loadNewsFromRSS() } }
            }
        }.resume()
    }

    private func fetchSupabaseNews() async -> Bool {
        let countryCode = await resolveCountryCode()
        do {
            let records = try await SupabaseClient.shared.fetchLogisticsNews(countryCode: countryCode)
            let mapped = records.map { record in
                NewsArticle(
                    id: UUID(uuidString: record.id) ?? UUID(),
                    title: record.headline,
                    description: record.summary,
                    url: record.url ?? "https://truckereasy.com",
                    urlToImage: nil,
                    publishedAt: record.published_at ?? ISO8601DateFormatter().string(from: Date()),
                    source: .init(name: record.source ?? "TruckerEasy")
                )
            }
            guard !mapped.isEmpty else { return false }
            await MainActor.run {
                articles = mapped
            }
            return true
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    private func resolveCountryCode() async -> String {
        guard let location = locationManager.currentLocation else { return "US" }
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

    /// Fonte de notícias indisponível (sem chave / erro / vazio). NÃO fabricar notícias —
    /// antes isto inventava títulos/fontes/datas (ex.: "FreightWaves · 2026-03-01"), que o motorista
    /// lia como real. A aba fica VAZIA com aviso honesto; melhor vazia do que mentindo.
    private func loadMockNews() {
        articles = []
        if errorMessage == nil {
            errorMessage = "Notícias indisponíveis no momento."
        }
    }

    /// News REAL de feeds RSS free (sem chave), usada quando o NewsAPI não está configurado.
    /// Fontes testadas ao vivo (HTTP 200): FreightWaves, Transport Topics. Nada fabricado.
    private func loadNewsFromRSS() async {
        let feeds = [
            ("FreightWaves", "https://www.freightwaves.com/news/feed"),
            ("Transport Topics", "https://www.ttnews.com/rss.xml")
        ]
        var collected: [NewsArticle] = []
        for (sourceName, urlString) in feeds {
            guard let url = URL(string: urlString) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
            collected.append(contentsOf: RSSNewsParser(sourceName: sourceName).parse(data))
        }
        await MainActor.run {
            isLoading = false
            if collected.isEmpty {
                articles = []
                if errorMessage == nil { errorMessage = "Notícias indisponíveis no momento." }
            } else {
                articles = Array(collected.prefix(40))
                errorMessage = nil
            }
        }
    }
}

/// Parser RSS 2.0 mínimo → NewsArticle. Robusto a CDATA. Datas reais do feed (sem fabricar).
private final class RSSNewsParser: NSObject, XMLParserDelegate {
    private let sourceName: String
    private var items: [NewsArticle] = []
    private var element = ""
    private var inItem = false
    private var title = "", link = "", desc = "", pubDate = ""

    init(sourceName: String) { self.sourceName = sourceName }

    func parse(_ data: Data) -> [NewsArticle] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        element = elementName
        if elementName == "item" { inItem = true; title = ""; link = ""; desc = ""; pubDate = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch element {
        case "title": title += string
        case "link": link += string
        case "description": desc += string
        case "pubDate": pubDate += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard inItem, let s = String(data: CDATABlock, encoding: .utf8) else { return }
        switch element {
        case "title": title += s
        case "description": desc += s
        case "link": link += s
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard elementName == "item" else { return }
        inItem = false
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let cleanDesc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        items.append(NewsArticle(
            id: UUID(),
            title: t,
            description: String(cleanDesc.prefix(220)),
            url: link.trimmingCharacters(in: .whitespacesAndNewlines),
            urlToImage: nil,
            publishedAt: Self.isoDate(from: pubDate),
            source: .init(name: sourceName)
        ))
    }

    /// RFC822 (pubDate do RSS) → ISO8601. Se não parsear, devolve a string crua do feed (honesto, sem inventar).
    private static func isoDate(from rfc822: String) -> String {
        let raw = rfc822.trimmingCharacters(in: .whitespacesAndNewlines)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let d = fmt.date(from: raw) { return ISO8601DateFormatter().string(from: d) }
        return raw.isEmpty ? "" : raw
    }
}

struct NewsArticleRow: View {
    let article: NewsArticle

    var publishedDate: String {
        if let date = ISO8601DateFormatter().date(from: article.publishedAt) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return article.publishedAt
    }

    var body: some View {
        Button(action: {
            if let url = URL(string: article.url) {
                UIApplication.shared.open(url)
            }
        }) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(article.title)
                    .font(AppTheme.Typography.bodyBold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)

                if let desc = article.description {
                    Text(desc)
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack {
                    Text(article.source.name)
                        .font(AppTheme.Typography.small())
                        .foregroundColor(AppTheme.Colors.accent)
                    Spacer()
                    Text(publishedDate)
                        .font(AppTheme.Typography.small())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.backgroundCard)
            .cornerRadius(AppTheme.Radius.md)
        }
    }
}

// MARK: - Easy AI Chat (dispatcher)
struct EasyAIChat: View {
    var body: some View {
        if #available(iOS 26, *) {
            EasyAIChatAppleIntelligence()
        } else {
            EasyAIChatKeyword()
        }
    }
}

// MARK: - Apple Intelligence Chat (iOS 26+)
// Now uses AIService which automatically falls back to OpenRouter when Apple Intelligence is unavailable
@available(iOS 26, *)
private struct EasyAIChatAppleIntelligence: View {
    @State private var messages: [EasyMessage] = [
        EasyMessage(
            content: "Hey! I'm Easy, your AI road companion. Ask me anything about trucking regulations, routes, IFTA, or the app!",
            isUser: false
        )
    ]
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var streamingText = ""
    @State private var suggestions: [String] = []
    
    private let ai = AIService.shared

    var body: some View {
        chatLayout
    }

    private var chatLayout: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(messages) { msg in
                            ChatBubble(message: msg).id(msg.id)
                        }
                        if isTyping {
                            if streamingText.isEmpty {
                                TypingIndicator().id("typing")
                            } else {
                                ChatBubble(message: EasyMessage(content: streamingText, isUser: false))
                                    .id("streaming")
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id) }
                }
                .onChange(of: streamingText) { _, _ in
                    withAnimation { proxy.scrollTo("streaming") }
                }
                .onChange(of: isTyping) { _, _ in
                    withAnimation { proxy.scrollTo("typing") }
                }
            }
            
            // Suggestions bar
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                inputText = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(AppTheme.Typography.caption())
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(AppTheme.Colors.backgroundCard)
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, 6)
                }
                .background(AppTheme.Colors.backgroundSecond)
            }
            
            inputBar
        }
    }

    private var inputBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            TextField("Ask Easy anything...", text: $inputText, axis: .vertical)
                .font(AppTheme.Typography.body())
                .foregroundColor(.white)
                .lineLimit(1...4)
                .padding(12)
                .background(AppTheme.Colors.backgroundInput)
                .cornerRadius(AppTheme.Radius.md)
                .disabled(isTyping)
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(inputText.isEmpty || isTyping ? AppTheme.Colors.textSecondary : AppTheme.Colors.accent)
            }
            .disabled(inputText.isEmpty || isTyping)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.backgroundSecond)
    }

    private func sendMessage() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        messages.append(EasyMessage(content: query, isUser: true))
        inputText = ""
        isTyping = true
        streamingText = ""
        suggestions = []
        
        // Build context from recent messages
        let context = messages
            .suffix(10)
            .map { $0.content }
        
        Task {
            do {
                // Stream response using AIService (auto-detects Foundation Models or OpenRouter)
                for try await chunk in ai.streamResponse(to: query, context: context) {
                    await MainActor.run {
                        streamingText.append(chunk)
                    }
                }
                
                await MainActor.run {
                    if !streamingText.isEmpty {
                        messages.append(EasyMessage(content: streamingText, isUser: false))
                    }
                    streamingText = ""
                    isTyping = false
                }
                
                // Get suggested replies
                let newSuggestions = await ai.suggestedReplies(for: query, context: context)
                await MainActor.run {
                    suggestions = newSuggestions
                }
            } catch {
                await MainActor.run {
                    messages.append(EasyMessage(
                        content: "I couldn't process that right now. Please try again!",
                        isUser: false
                    ))
                    streamingText = ""
                    isTyping = false
                }
            }
        }
    }
}

// MARK: - Keyword Fallback Chat (devices without Apple Intelligence)
private struct EasyAIChatKeyword: View {
    @State private var messages: [EasyMessage] = [
        EasyMessage(content: "Hey! I'm Easy, your road companion AI. Ask me anything about regulations, routes, IFTA, or how to use the app!", isUser: false)
    ]
    @State private var inputText = ""
    @State private var isTyping = false

    private let responses: [(keywords: [String], reply: String)] = [
        (["hours", "hos", "service", "log"],
         "HOS (Hours of Service): Property-carrying drivers can drive 11 hours after 10 hours off duty, within a 14-hour window. 30-min break required after 8h driving. 60/70h weekly limit."),
        (["ifta", "fuel tax", "quarterly"],
         "IFTA is filed quarterly. You need total miles per state and total gallons purchased. Use the 'My Cabin' tab → IFTA Calculator to generate your report automatically!"),
        (["cdl", "license", "renew"],
         "Your CDL renewal depends on your state. Most require renewal every 4-8 years. Medical Card (DOT Physical) must be renewed every 2 years max. Check 'My Cabin' for your expiry dates!"),
        (["medical", "dot physical", "exam"],
         "DOT physical exams are required every 24 months for most drivers. If you have certain conditions (diabetes, sleep apnea), you may need more frequent exams. Set a reminder in 'My Cabin'!"),
        (["state", "miles", "mileage"],
         "For IFTA, you need to track miles driven per state. TruckerEasy tracks this automatically via GPS. Check 'My Cabin' → IFTA for your breakdown."),
        (["load", "freight", "pickup", "delivery"],
         "Got a load? Use the 'Got a Load?' button on the My Horizon map tab! Paste your load confirmation and I'll extract the destination address automatically."),
        (["route", "navigation", "direction", "navigate"],
         "For navigation, use the 'My Horizon' tab. You can enter your destination manually or use 'Got a Load?' to paste load details and auto-extract the address."),
        (["document", "insurance", "registration", "paper"],
         "Keep all your documents in 'My Cabin' tab. CDL, Medical Card, DOT Number, Truck Insurance, Trailer Insurance – all with expiry alerts so you're never caught off guard!"),
        (["health", "sleep", "wellness", "tired", "fatigue"],
         "Driver health matters! Use 'My Check-up' tab to log your mood (5 stars), sleep hours, water intake, and exercise. Set medication reminders so you never miss a dose on the road."),
        (["fuel", "gas", "diesel", "price"],
         "Track fuel purchases in 'My Cabin' → Fuel Log. Fuel prices are shown on the map in My Horizon. Keep receipts logged for IFTA reporting!"),
        (["inspection", "pre-trip", "post-trip", "dvir"],
         "Pre-trip inspections are required by FMCSA before each trip. Check brakes, tires, lights, fluid levels, and mirrors. Log any defects in your DVIR immediately."),
        (["weigh", "scale", "weight", "limit"],
         "Federal weight limits: 80,000 lbs gross, 20,000 on single axle, 34,000 on tandem axle. Use Road Talk → Report to share weigh station status with other drivers!"),
        (["parking", "rest", "stop", "truck stop"],
         "Use the My Horizon map to find nearby truck stops. Tap 'Find Truck Stop' for parking, fuel, and amenities. Report parking availability in Road Talk → Report!"),
        (["subscription", "price", "plan", "pay"],
         "TruckerEasy plans:\n• Monthly: \(AppDistributionConfig.MarketingPrice.monthlyUSD)/mo\n• Annual: \(AppDistributionConfig.MarketingPrice.annualUSD)/yr (save \(AppDistributionConfig.MarketingPrice.annualSavingsUSD)!)\n• Free Trial: \(AppDistributionConfig.MarketingPrice.trialDays) days\n\nGo to Settings → Manage Plan to subscribe."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(messages) { msg in
                            ChatBubble(message: msg).id(msg.id)
                        }
                        if isTyping {
                            TypingIndicator().id("typing")
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id) }
                }
                .onChange(of: isTyping) { _, _ in
                    withAnimation { proxy.scrollTo("typing") }
                }
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                TextField("Ask Easy anything...", text: $inputText, axis: .vertical)
                    .font(AppTheme.Typography.body())
                    .foregroundColor(.white)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(AppTheme.Colors.backgroundInput)
                    .cornerRadius(AppTheme.Radius.md)
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(inputText.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.accent)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.backgroundSecond)
        }
    }

    private func sendMessage() {
        let userMsg = EasyMessage(content: inputText, isUser: true)
        messages.append(userMsg)
        let query = inputText.lowercased()
        inputText = ""
        isTyping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let reply = generateReply(for: query)
            messages.append(EasyMessage(content: reply, isUser: false))
            isTyping = false
        }
    }

    private func generateReply(for query: String) -> String {
        for (keywords, reply) in responses {
            if keywords.contains(where: { query.contains($0) }) {
                return reply
            }
        }
        if query.contains("what") || query.contains("how") || query.contains("when") || query.contains("where") {
            return "Great question! For regulations check FMCSA.dot.gov. Try asking about: HOS rules, IFTA filing, CDL renewal, fuel tracking, weigh stations, or parking!"
        }
        return "I can help with HOS rules, IFTA filing, CDL/Medical Card renewals, route planning, fuel tracking, and using the TruckerEasy app. What would you like to know?"
    }
}

struct ChatBubble: View {
    let message: EasyMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser { Spacer(minLength: 60) }

            if !message.isUser {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.accent.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Text("E")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(AppTheme.Typography.body())
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isUser ? AppTheme.Colors.accent.opacity(0.25) : AppTheme.Colors.backgroundCard)
                    .cornerRadius(message.isUser ? AppTheme.Radius.lg : AppTheme.Radius.lg,
                                  corners: message.isUser ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])

                Text(message.timestamp, style: .time)
                    .font(AppTheme.Typography.small())
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
    }
}

struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.2))
                    .frame(width: 32, height: 32)
                Text("E").font(.system(size: 14, weight: .bold)).foregroundColor(AppTheme.Colors.accent)
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(AppTheme.Colors.textSecondary)
                        .frame(width: 6, height: 6)
                        .te_uniformScale(phase == i ? 1.4 : 0.8)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.Colors.backgroundCard)
            .cornerRadius(AppTheme.Radius.lg)
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) { phase = 1 }
        }
    }
}

#Preview {
    RoadTalkView()
        .modelContainer(for: [CommunityPost.self, PostComment.self], inMemory: true)
        .preferredColorScheme(.dark)
}
