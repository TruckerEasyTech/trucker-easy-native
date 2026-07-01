import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Cabin Document Types (CDL, DOT, Medical Card, etc.)
enum CabinDocType: String, CaseIterable, Codable {
    case cdl            = "CDL License"
    case medicalCard    = "Medical Card"
    case dotNumber      = "DOT Number"
    case truckInsurance = "Truck Insurance"
    case trailerInsurance = "Trailer Insurance"
    case registration   = "Registration"
    case inspection     = "Inspection"
    case hazmat         = "HAZMAT Permit"
    case oversize       = "Oversize Permit"
    case other          = "Other"

    var icon: String {
        switch self {
        case .cdl:              return "creditcard.fill"
        case .medicalCard:      return "cross.case.fill"
        case .dotNumber:        return "number.circle.fill"
        case .truckInsurance:   return "shield.fill"
        case .trailerInsurance: return "shield.lefthalf.filled"
        case .registration:     return "doc.text.fill"
        case .inspection:       return "checkmark.shield.fill"
        case .hazmat:           return "exclamationmark.triangle.fill"
        case .oversize:         return "arrow.up.left.and.arrow.down.right"
        case .other:            return "folder.fill"
        }
    }

    var color: Color {
        switch self {
        case .cdl:              return AppTheme.Colors.accent
        case .medicalCard:      return AppTheme.Colors.danger
        case .dotNumber:        return AppTheme.Colors.accentSoft
        case .truckInsurance:   return AppTheme.Colors.success
        case .trailerInsurance: return Color(hex: "#0d9488")
        case .registration:     return AppTheme.Colors.ctaGlow
        case .inspection:       return AppTheme.Colors.cta
        case .hazmat:           return AppTheme.Colors.warning
        case .oversize:         return Color(hex: "#7c3aed")
        case .other:            return AppTheme.Colors.textSecondary
        }
    }
}

// MARK: - Cabin View (Tab 3 - Digital Document Vault)
struct CabinView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @Query(sort: \TruckDocument.expirationDate) private var documents: [TruckDocument]

    @State private var showingAddDocument = false
    @State private var selectedFilter: DocFilter = .all
    @State private var selectedDoc: TruckDocument? = nil

    // Quick-scan preset — opens scanner directly for a specific doc type
    @State private var quickScanPresetName: String = ""
    @State private var quickScanPresetType: DocumentType = .other

    enum DocFilter: String, CaseIterable {
        case all = "All"
        case expiring = "Expiring"
        case expired = "Expired"
        case ok = "OK"

        func label(lang: AppLanguage) -> String {
            switch self {
            case .all:      return lang.filterAll
            case .expiring: return lang.filterExpiring
            case .expired:  return lang.filterExpired
            case .ok:       return lang.filterOk
            }
        }
    }

    var lang: AppLanguage { regionalSettings.currentLanguage }

    var filteredDocs: [TruckDocument] {
        switch selectedFilter {
        case .all:      return documents
        case .expiring: return documents.filter { ($0.daysUntilExpiration ?? 999) <= 30 && !$0.isExpired }
        case .expired:  return documents.filter { $0.isExpired }
        case .ok:       return documents.filter { !$0.isExpired && ($0.daysUntilExpiration ?? 999) > 30 }
        }
    }

    // Summary counts
    var expiredCount: Int { documents.filter { $0.isExpired }.count }
    var expiringCount: Int { documents.filter { ($0.daysUntilExpiration ?? 999) <= 30 && !$0.isExpired }.count }
    var okCount: Int { documents.filter { !$0.isExpired && ($0.daysUntilExpiration ?? 999) > 30 }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.Spacing.lg) {

                        // MARK: Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lang.cabinTitle)
                                    .font(AppTheme.Typography.heroTitle())
                                    .foregroundColor(.white)
                                Text(lang.cabinSubtitle)
                                    .font(AppTheme.Typography.caption())
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                            Button(action: { showingAddDocument = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(AppTheme.Colors.accent)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, AppTheme.Spacing.md)

                        // MARK: Status Summary (Traffic Light)
                        HStack(spacing: AppTheme.Spacing.sm) {
                            TrafficLightCard(count: okCount, label: lang.filterOk, color: AppTheme.Colors.success,
                                            icon: "checkmark.circle.fill")
                            TrafficLightCard(count: expiringCount, label: lang.filterExpiring, color: AppTheme.Colors.warning,
                                            icon: "exclamationmark.circle.fill")
                            TrafficLightCard(count: expiredCount, label: lang.filterExpired, color: AppTheme.Colors.danger,
                                            icon: "xmark.circle.fill")
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // MARK: Filter Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                ForEach(DocFilter.allCases, id: \.rawValue) { filter in
                                    DocFilterChip(title: filter.label(lang: lang), isSelected: selectedFilter == filter) {
                                        selectedFilter = filter
                                    }
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.md)
                        }

                        // MARK: Priority Alerts
                        if expiredCount > 0 || expiringCount > 0 {
                            PriorityAlertsCard(
                                expired: documents.filter { $0.isExpired },
                                expiring: documents.filter { ($0.daysUntilExpiration ?? 999) <= 30 && !$0.isExpired }
                            )
                            .padding(.horizontal, AppTheme.Spacing.md)
                        }

                        // MARK: Document List
                        if filteredDocs.isEmpty {
                            EmptyVaultView(onAdd: { showingAddDocument = true })
                                .padding(.horizontal, AppTheme.Spacing.md)
                        } else {
                            VStack(spacing: AppTheme.Spacing.sm) {
                                ForEach(filteredDocs) { doc in
                                    DocumentVaultRow(document: doc)
                                        .onTapGesture { selectedDoc = doc }
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.md)
                        }

                        // MARK: Quick Scan Buttons — always visible, not just when vault is empty
                        QuickScanGrid(onScan: { name, type in
                            quickScanPresetName = name
                            quickScanPresetType = type
                            showingAddDocument = true
                        })
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // MARK: IFTA Fuel Tax
                        NavigationLink {
                            IFTAView()
                                .preferredColorScheme(.dark)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "fuelpump.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(AppTheme.Colors.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("IFTA Fuel Tax")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("Quarterly reports & state mileage")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            .padding(AppTheme.Spacing.md)
                            .background(AppTheme.Colors.backgroundCard)
                            .cornerRadius(AppTheme.Radius.md)
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // MARK: Tools Section — Truck Signs
                        TruckSignsShortcutCard()
                            .padding(.horizontal, AppTheme.Spacing.md)

                        // MARK: Reefer temperature monitor — só para perfil frigorífico
                        if TruckProfile.loadSaved().truckType == .refrigerated {
                            ReeferShortcutCard()
                                .padding(.horizontal, AppTheme.Spacing.md)
                        }

                        Spacer(minLength: AppTheme.Spacing.xxl)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAddDocument) {
                AddDocumentView(
                    presetName: quickScanPresetName,
                    presetType: quickScanPresetType
                )
                .preferredColorScheme(.dark)
                .onDisappear {
                    // Reset preset after sheet closes
                    quickScanPresetName = ""
                    quickScanPresetType = .other
                }
            }
            .sheet(item: $selectedDoc) { doc in
                DocumentDetailView(document: doc)
                    .preferredColorScheme(.dark)
            }
        }
    }

    private func addPresetDocument(_ type: CabinDocType) {
        let doc = TruckDocument(
            name: type.rawValue,
            documentType: mapCabinToDocType(type)
        )
        modelContext.insert(doc)
    }

    private func mapCabinToDocType(_ t: CabinDocType) -> DocumentType {
        switch t {
        case .cdl:              return .license
        case .medicalCard:      return .medical
        case .truckInsurance:   return .insurance
        case .trailerInsurance: return .insurance
        case .registration:     return .registration
        case .inspection:       return .inspection
        default:                return .other
        }
    }
}

// MARK: - Traffic Light Card
struct TrafficLightCard: View {
    let count: Int
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            Text("\(count)")
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(color)
            Text(label)
                .font(AppTheme.Typography.captionBold())
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(color.opacity(0.1))
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Filter Chip
struct DocFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Typography.captionBold())
                .foregroundColor(isSelected ? AppTheme.Colors.background : AppTheme.Colors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.backgroundCard)
                .cornerRadius(AppTheme.Radius.pill)
        }
    }
}

// MARK: - Priority Alerts Card
struct PriorityAlertsCard: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    let expired: [TruckDocument]
    let expiring: [TruckDocument]

    var lang: AppLanguage { regionalSettings.currentLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(AppTheme.Colors.danger)
                Text(lang.actionRequiredLabel)
                    .font(AppTheme.Typography.small())
                    .foregroundColor(AppTheme.Colors.danger)
                    .kerning(1.5)
            }

            ForEach(expired.prefix(3)) { doc in
                HStack(spacing: 10) {
                    Circle().fill(AppTheme.Colors.danger).frame(width: 8, height: 8)
                    Text(doc.name)
                        .font(AppTheme.Typography.captionBold())
                        .foregroundColor(.white)
                    Spacer()
                    Text(lang.expiredLabel)
                        .font(AppTheme.Typography.small())
                        .foregroundColor(AppTheme.Colors.danger)
                        .kerning(1)
                }
            }

            ForEach(expiring.prefix(3)) { doc in
                HStack(spacing: 10) {
                    Circle().fill(AppTheme.Colors.warning).frame(width: 8, height: 8)
                    Text(doc.name)
                        .font(AppTheme.Typography.captionBold())
                        .foregroundColor(.white)
                    Spacer()
                    if let days = doc.daysUntilExpiration {
                        Text("in \(days)d")
                            .font(AppTheme.Typography.small())
                            .foregroundColor(AppTheme.Colors.warning)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.danger.opacity(0.08))
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(AppTheme.Colors.danger.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Document Vault Row (with traffic light indicator)
struct DocumentVaultRow: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    let document: TruckDocument

    var lang: AppLanguage { regionalSettings.currentLanguage }

    var statusColor: Color {
        if document.isExpired { return AppTheme.Colors.danger }
        if let days = document.daysUntilExpiration, days <= 30 { return AppTheme.Colors.warning }
        return AppTheme.Colors.success
    }

    var statusText: String {
        if document.isExpired { return lang.expiredLabel }
        if let days = document.daysUntilExpiration {
            return "in \(days)d"
        }
        return lang.noExpiryLabel
    }

    var docIcon: String {
        switch document.documentType {
        case .license:      return CabinDocType.cdl.icon
        case .medical:      return CabinDocType.medicalCard.icon
        case .insurance:    return CabinDocType.truckInsurance.icon
        case .registration: return CabinDocType.registration.icon
        case .inspection:   return CabinDocType.inspection.icon
        default:            return "doc.fill"
        }
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Traffic light dot + icon
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: docIcon)
                    .font(.system(size: 22))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(AppTheme.Typography.bodyBold())
                    .foregroundColor(.white)
                if let expDate = document.expirationDate {
                    Text("Expires \(expDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                } else {
                    Text(lang.noExpirationSetLabel)
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            Spacer()

            // Traffic light badge
            VStack(spacing: 4) {
                // Traffic light circles
                TrafficLight(color: AppTheme.Colors.danger, active: document.isExpired)
                TrafficLight(color: AppTheme.Colors.warning,
                             active: !document.isExpired && (document.daysUntilExpiration ?? 999) <= 30)
                TrafficLight(color: AppTheme.Colors.success,
                             active: !document.isExpired && (document.daysUntilExpiration ?? 999) > 30)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }
}

struct TrafficLight: View {
    let color: Color
    let active: Bool

    var body: some View {
        Circle()
            .fill(active ? color : color.opacity(0.15))
            .frame(width: 10, height: 10)
    }
}

// MARK: - Empty Vault View
struct EmptyVaultView: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    let onAdd: () -> Void

    var lang: AppLanguage { regionalSettings.currentLanguage }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundColor(AppTheme.Colors.accent.opacity(0.4))
            Text(lang.vaultEmptyTitle)
                .font(AppTheme.Typography.sectionTitle())
                .foregroundColor(.white)
            Text(lang.vaultEmptySubtitle)
                .font(AppTheme.Typography.body())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            TEButton(lang.addFirstDocumentLabel, icon: "plus", style: .cta, action: onAdd)
        }
        .padding(AppTheme.Spacing.xl)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.lg)
    }
}

// MARK: - Quick Scan Grid (one-tap camera per doc type)

struct QuickScanGrid: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    /// Called with (presetName, DocumentType) when the driver taps a scan button
    let onScan: (String, DocumentType) -> Void

    var lang: AppLanguage { regionalSettings.currentLanguage }

    private struct QuickScanItem {
        let label: String
        let icon: String
        let color: Color
        let docType: DocumentType
    }

    private let items: [QuickScanItem] = [
        QuickScanItem(label: "CDL",          icon: "creditcard.fill",             color: AppTheme.Colors.accent,        docType: .license),
        QuickScanItem(label: "Medical Card", icon: "cross.case.fill",             color: AppTheme.Colors.danger,        docType: .medical),
        QuickScanItem(label: "Insurance",    icon: "shield.fill",                 color: AppTheme.Colors.success,       docType: .insurance),
        QuickScanItem(label: "Registration", icon: "doc.text.fill",               color: Color(hex: "#f59e0b"),         docType: .registration),
        QuickScanItem(label: "Inspection",   icon: "checkmark.shield.fill",       color: AppTheme.Colors.cta,           docType: .inspection),
        QuickScanItem(label: "Permit",       icon: "star.circle.fill",            color: Color(hex: "#7c3aed"),         docType: .permit),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.accent)
                Text(lang.quickScanLabel)
                    .font(AppTheme.Typography.small())
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .kerning(1.5)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                      spacing: 12) {
                ForEach(items, id: \.label) { item in
                    Button(action: { onScan(item.label, item.docType) }) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(item.color.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: item.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(item.color)
                            }
                            Text(item.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            // Camera badge
                            HStack(spacing: 3) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 9))
                                Text("Scan")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(AppTheme.Colors.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.Colors.backgroundCard)
                        .cornerRadius(AppTheme.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .stroke(item.color.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}


// MARK: - Truck Signs Shortcut Card

struct TruckSignsShortcutCard: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @State private var showingSigns = false

    var lang: AppLanguage { regionalSettings.currentLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Section label
            HStack(spacing: 6) {
                Image(systemName: "signpost.right.and.left.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.accent)
                Text(lang.driverToolsLabel)
                    .font(AppTheme.Typography.small())
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .kerning(1.5)
            }

            Button(action: { showingSigns = true }) {
                HStack(spacing: AppTheme.Spacing.md) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .fill(Color(hex: "#f59e0b").opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "signpost.right.and.left.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Color(hex: "#f59e0b"))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(lang.truckSignsGuideLabel)
                            .font(AppTheme.Typography.bodyBold())
                            .foregroundColor(.white)
                        Text(lang.truckSignsGuideSubtitle)
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(AppTheme.Spacing.md)
                .background(AppTheme.Colors.backgroundCard)
                .cornerRadius(AppTheme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .stroke(Color(hex: "#f59e0b").opacity(0.2), lineWidth: 1)
                )
            }
        }
        .sheet(isPresented: $showingSigns) {
            NavigationStack {
                TruckSignsView()
                    .preferredColorScheme(.dark)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(lang.doneLabel) { showingSigns = false }
                                .foregroundColor(AppTheme.Colors.accent)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }
}


// MARK: - Reefer Monitor Shortcut Card (só aparece para perfil frigorífico)

struct ReeferShortcutCard: View {
    @State private var showingReefer = false
    private var monitor: ReeferMonitorService { ReeferMonitorService.shared }

    var body: some View {
        Button(action: { showingReefer = true }) {
            HStack(spacing: AppTheme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(Color(hex: "#5aa9e6").opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "thermometer.snowflake")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color(hex: "#5aa9e6"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Reefer Monitor")
                        .font(AppTheme.Typography.bodyBold())
                        .foregroundColor(.white)
                    // Estado honesto: temperatura real ao vivo, ou convite pra conectar/registrar
                    if let c = monitor.currentTempCelsius {
                        Text(String(format: "%.1f°F ao vivo · %@", c * 9 / 5 + 32,
                                    monitor.isOutOfRange ? "FORA DA FAIXA" : "na faixa"))
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(monitor.isOutOfRange ? Color(hex: "#ef4444") : Color(hex: "#22d474"))
                    } else {
                        Text("Temperatura da carga · sensor BLE + registro FSMA")
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.backgroundCard)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(Color(hex: "#5aa9e6").opacity(0.2), lineWidth: 1)
            )
        }
        .sheet(isPresented: $showingReefer) {
            NavigationStack {
                ReeferMonitorView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingReefer = false }
                                .foregroundColor(AppTheme.Colors.accent)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    CabinView()
        .modelContainer(for: [TruckDocument.self], inMemory: true)
        .preferredColorScheme(.dark)
}
