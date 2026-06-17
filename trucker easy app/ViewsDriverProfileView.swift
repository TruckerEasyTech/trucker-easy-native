// ViewsDriverProfileView.swift
// TruckerEasy — Driver Profile Tab
// © 2024–2026 TruckerEasy. All rights reserved. Unauthorized copying or redistribution prohibited.

import SwiftUI
import PhotosUI
import MapKit

// MARK: - Driver Profile View

struct DriverProfileView: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @Environment(\.colorScheme) private var colorScheme

    // Persisted driver info
    @AppStorage("driverName")        private var driverName      = "Driver"
    @AppStorage("driverSinceYear")   private var driverSinceYear = 2025
    @AppStorage("driverReports")     private var driverReports   = 0
    @AppStorage("driverReviews")     private var driverReviews   = 0
    @AppStorage("driverMessages")    private var driverMessages  = 0
    @AppStorage("appearanceMode")    private var appearanceMode  = 0   // 0=Auto, 1=Light, 2=Dark
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    // Truck profile
    @State private var truckProfile = TruckProfile.loadSaved()
    @State private var showingTruckEditor    = false

    // Sheet / navigation state
    @State private var showingEditName       = false
    @State private var showingFoodPrefs      = false
    @State private var showingLanguage       = false
    @State private var showingVoicePicker    = false
    @State private var showingPrivacy        = false
    @State private var showingHelp           = false
    @State private var showingBypassHistory  = false
    @State private var showingMyRatings      = false
    @State private var showingStopAdvisor    = false
    @State private var showingLogOutAlert    = false
    @State private var showingPhotoPicker    = false
    @State private var showingSubscription   = false
    @State private var showingFindDMV        = false
    @State private var showingDrugTest       = false
    @State private var showingFleetAccount   = false
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var avatarImageData: Data? = nil
    @State private var fleetAuth = DriverAuthManager.shared

    var lang: AppLanguage { regionalSettings.currentLanguage }

    // Computed year "Since"
    private var sinceText: String { "Since \(driverSinceYear)" }

    // Initials fallback
    private var initials: String {
        let parts = driverName.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(driverName.prefix(2)).uppercased()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // MARK: Header — Avatar + Name + Stats
                        profileHeader

                        // MARK: Section cards
                        VStack(spacing: 14) {
                            wellbeingSection
                            foodSection
                            bypassRatingsSection
                            documentsSection
                            if AppAccessPolicy.driverDispatchEnabled {
                                fleetAccountSection
                            }
                            myTruckSection
                            settingsSection
                            logoutButton
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(lang.myProfileTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Colors.backgroundInput, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        // Sheet presentations
        .sheet(isPresented: $showingTruckEditor) {
            TruckProfileEditorSheet(truckProfile: $truckProfile)
        }
        .sheet(isPresented: $showingFoodPrefs)      { FoodPreferencesSheet() }
        .sheet(isPresented: $showingLanguage)        { LanguageSelectionSheet(regionalSettings: regionalSettings) }
        .sheet(isPresented: $showingVoicePicker)     { VoiceSelectionSheet(regionalSettings: regionalSettings) }
        .sheet(isPresented: $showingPrivacy)         { PrivacyPolicySheet() }
        .sheet(isPresented: $showingHelp)            { HelpSupportSheet() }
        .sheet(isPresented: $showingBypassHistory)   { BypassHistorySheet() }
        .sheet(isPresented: $showingMyRatings)       { MyRatingsSheet() }
        .sheet(isPresented: $showingStopAdvisor)     { StopAdvisorSheet() }
        .sheet(isPresented: $showingSubscription)    { SubscriptionView() }
        .sheet(isPresented: $showingFindDMV)         { FindDMVSheet() }
        .sheet(isPresented: $showingDrugTest)        { DrugTestSheet() }
        .sheet(isPresented: $showingFleetAccount) {
            DriverFleetAccountSheet(auth: fleetAuth)
        }
        .sheet(isPresented: $showingEditName) {
            EditDriverNameSheet(driverName: $driverName)
        }
        .alert(lang.logOutConfirmTitle, isPresented: $showingLogOutAlert) {
            Button(lang.logOutConfirmTitle, role: .destructive) { performLogout() }
            Button(lang.cancelLabel, role: .cancel) {}
        } message: {
            Text(lang.logOutConfirmMessage)
        }
        .onChange(of: avatarItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    avatarImageData = data
                }
            }
        }
        .task {
            guard AppAccessPolicy.driverDispatchEnabled else { return }
            fleetAuth.syncFromClient()
            if fleetAuth.isSignedIn {
                await fleetAuth.refreshPendingLoads(pushFirstToHorizon: false)
            }
        }
        .preferredColorScheme(colorSchemeFromSetting)
    }

    // MARK: - Logout

    private func performLogout() {
        Task { await fleetAuth.signOut() }
        let keysToReset = [
            "driverName", "driverSinceYear", "driverReports",
            "driverReviews", "driverMessages", "avatarImageData",
            "healthProfile", "driverRatings", "favoriteMeals",
            "hasSeenWelcome"
        ]
        for key in keysToReset {
            UserDefaults.standard.removeObject(forKey: key)
        }
        driverName = "Driver"
        driverSinceYear = 2025
        driverReports = 0
        driverReviews = 0
        driverMessages = 0
        notificationsEnabled = true
        appearanceMode = 0
    }

    // MARK: - Header

    private var profileHeader: some View {
        ZStack {
            // Background gradient strip
            LinearGradient(
                colors: [AppTheme.Colors.backgroundInput, AppTheme.Colors.background],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 220)

            VStack(spacing: 12) {
                // Avatar
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    ZStack {
                        if let data = avatarImageData, let uiImg = UIImage(data: data) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 86, height: 86)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.Colors.accent.opacity(0.35), AppTheme.Colors.cta.opacity(0.25)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 86, height: 86)
                                .overlay(
                                    Text(initials)
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                )
                        }
                        // Camera badge
                        Circle()
                            .fill(AppTheme.Colors.accent)
                            .frame(width: 26, height: 26)
                            .overlay(Image(systemName: "camera.fill").font(.system(size: 12)).foregroundColor(.white))
                            .offset(x: 29, y: 29)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(AppTheme.Colors.accent.opacity(0.5), lineWidth: 2)
                        .frame(width: 90, height: 90)
                )

                // Name + edit
                Button(action: { showingEditName = true }) {
                    HStack(spacing: 6) {
                        Text(driverName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                }

                Text(sinceText)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)

                // Stats row
                HStack(spacing: 0) {
                    ProfileStatCell(value: driverReports, label: lang.reportsStatLabel)
                    Divider().frame(height: 32).background(AppTheme.Colors.backgroundCard)
                    ProfileStatCell(value: driverReviews, label: lang.reviewsStatLabel)
                    Divider().frame(height: 32).background(AppTheme.Colors.backgroundCard)
                    ProfileStatCell(value: driverMessages, label: lang.messagesStatLabel)
                }
                .background(AppTheme.Colors.backgroundCard.opacity(0.7))
                .cornerRadius(12)
                .padding(.horizontal, 32)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Wellbeing Section

    private var wellbeingSection: some View {
        ProfileSectionCard(title: lang.wellnessSectionLabel) {
            NavigationLink {
                CheckupView()
                    .environment(regionalSettings)
            } label: {
                ProfileRow(icon: "heart.fill", iconColor: AppTheme.Colors.danger,
                           title: lang.myWellbeingLabel, subtitle: lang.wellnessSubtitle)
            }
        }
    }

    // MARK: - Food Section

    private var foodSection: some View {
        ProfileSectionCard(title: lang.foodSectionLabel) {
            VStack(spacing: 0) {
                Button(action: { showingFoodPrefs = true }) {
                    ProfileRow(icon: "fork.knife.circle.fill", iconColor: AppTheme.Colors.cta,
                               title: lang.foodPreferencesLabel, subtitle: lang.foodSectionSubtitle)
                }
                Divider().background(AppTheme.Colors.backgroundCard)
                Button(action: { showingFoodPrefs = true }) {
                    ProfileRow(icon: "star.fill", iconColor: AppTheme.Colors.warning,
                               title: lang.favoriteMealsLabel, subtitle: lang.favoriteMealsSubtitle)
                }
                Divider().background(AppTheme.Colors.backgroundCard)
                Button(action: {}) {
                    ProfileRow(icon: "leaf.fill", iconColor: AppTheme.Colors.success,
                               title: lang.stopAdvisorFoodLabel, subtitle: lang.stopAdvisorSubtitle,
                               badge: "AI")
                }
            }
        }
    }

    // MARK: - Bypass / Ratings Section

    private var bypassRatingsSection: some View {
        ProfileSectionCard(title: lang.historySectionLabel) {
            VStack(spacing: 0) {
                Button(action: { showingBypassHistory = true }) {
                    ProfileRow(icon: "checkmark.shield.fill", iconColor: AppTheme.Colors.accent,
                               title: lang.bypassHistoryLabel, subtitle: lang.bypassHistorySubtitle)
                }
                Divider().background(AppTheme.Colors.backgroundCard)
                Button(action: { showingMyRatings = true }) {
                    ProfileRow(icon: "star.leadinghalf.filled", iconColor: AppTheme.Colors.warning,
                               title: lang.myRatingsLabel, subtitle: lang.myRatingsSubtitle)
                }
                Divider().background(AppTheme.Colors.backgroundCard)
                Button(action: { showingStopAdvisor = true }) {
                    ProfileRow(icon: "mappin.and.ellipse", iconColor: AppTheme.Colors.cta,
                               title: lang.stopAdvisorLabel, subtitle: lang.smartStopSubtitle)
                }
                Divider().background(AppTheme.Colors.backgroundCard)
                Button(action: {}) {
                    ProfileRow(icon: "building.2.fill", iconColor: AppTheme.Colors.accentSoft,
                               title: lang.facilityRatingLabel, subtitle: lang.facilityRatingSubtitle)
                }
            }
        }
    }

    // MARK: - Compliance & Documents

    private var documentsSection: some View {
        ProfileSectionCard(title: lang.complianceSectionLabel) {
            VStack(spacing: 0) {
                NavigationLink {
                    CabinView()
                } label: {
                    ProfileRow(icon: "doc.fill", iconColor: AppTheme.Colors.accent,
                               title: lang.myDocumentsLabel, subtitle: lang.myDocumentsSubtitle)
                }
                Divider().background(AppTheme.Colors.backgroundCard)
                Button(action: { showingFindDMV = true }) {
                    ProfileRow(icon: "mappin.circle.fill", iconColor: AppTheme.Colors.textSecondary,
                               title: lang.findDMVLabel, subtitle: lang.findDMVSubtitle)
                }
                Divider().background(AppTheme.Colors.backgroundCard)
                Button(action: { showingDrugTest = true }) {
                    ProfileRow(icon: "cross.case.fill", iconColor: AppTheme.Colors.success,
                               title: lang.drugTestLabel, subtitle: lang.drugTestSubtitle)
                }
            }
        }
    }

    // MARK: - My Truck Section

    private var myTruckSection: some View {
        ProfileSectionCard(title: "MY TRUCK") {
            VStack(spacing: 0) {
                Button(action: { showingTruckEditor = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: truckTypeIcon(truckProfile.truckType))
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.Colors.cta)
                            .frame(width: 32, height: 32)
                            .background(AppTheme.Colors.cta.opacity(0.12))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(truckProfile.truckType.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                            Text(truckSummaryText)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }

                Divider().background(AppTheme.Colors.backgroundCard)

                // Hazmat indicator row
                HStack(spacing: 12) {
                    Image(systemName: truckProfile.hasHazmat ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                        .font(.system(size: 18))
                        .foregroundColor(truckProfile.hasHazmat ? AppTheme.Colors.warning : AppTheme.Colors.success)
                        .frame(width: 32, height: 32)
                        .background((truckProfile.hasHazmat ? AppTheme.Colors.warning : AppTheme.Colors.success).opacity(0.12))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(truckProfile.hasHazmat ? "Hazmat Load" : "No Hazmat")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                        Text(truckProfile.hasHazmat ? "Routes avoid restricted tunnels & zones" : "Standard routing applies")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private var truckSummaryText: String {
        let h = String(format: "%.1fm", truckProfile.heightMeters)
        let w = String(format: "%.1ft", truckProfile.weightTonnes)
        let l = String(format: "%.1fm", truckProfile.lengthMeters)
        return "\(h) tall · \(w) · \(l) long"
    }

    private func truckTypeIcon(_ type: TruckType) -> String {
        switch type {
        case .semi:         return "truck.box.fill"
        case .straight:     return "box.truck.fill"
        case .tanker:       return "fuelpump.fill"
        case .flatbed:      return "shippingbox.fill"
        case .refrigerated: return "snowflake"
        }
    }

    // MARK: - Fleet / Dispatch

    private var fleetAccountSection: some View {
        ProfileSectionCard(title: "Fleet & Dispatch") {
            VStack(spacing: 0) {
                Button(action: { showingFleetAccount = true }) {
                    ProfileRow(
                        icon: "shippingbox.fill",
                        iconColor: AppTheme.Colors.cta,
                        title: fleetAuth.isSignedIn ? "Fleet account connected" : "Connect fleet account",
                        subtitle: fleetAuth.isSignedIn
                            ? (fleetAuth.email ?? "Signed in") + (fleetAuth.pendingLoadCount.map { " · \($0) pending" } ?? "")
                            : "Receive loads from truckereasy.com dispatch"
                    )
                }
                if fleetAuth.isSignedIn {
                    Divider().background(AppTheme.Colors.backgroundCard)
                    Button {
                        Task { await fleetAuth.refreshPendingLoads(pushFirstToHorizon: true) }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(AppTheme.Colors.accent)
                                .frame(width: 32)
                            Text("Refresh pending loads")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        ProfileSectionCard(title: lang.settingsSectionLabel) {
            VStack(spacing: 0) {
                // Appearance
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.Colors.accent)
                        .frame(width: 32)
                    Text(lang.appearanceLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $appearanceMode) {
                        Text(lang.autoLabel).tag(0)
                        Text(lang.lightLabel).tag(1)
                        Text(lang.darkLabel).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .tint(AppTheme.Colors.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().background(AppTheme.Colors.backgroundCard)

                // Notifications toggle
                HStack {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.Colors.warning)
                        .frame(width: 32)
                    Text(lang.notificationsLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $notificationsEnabled)
                        .tint(AppTheme.Colors.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().background(AppTheme.Colors.backgroundCard)

                // Language
                Button(action: { showingLanguage = true }) {
                    ProfileRow(icon: "globe", iconColor: AppTheme.Colors.accent,
                               title: lang.languageLabel,
                               subtitle: regionalSettings.currentLanguage.rawValue + "  " + regionalSettings.currentLanguage.flagEmoji)
                }

                Divider().background(AppTheme.Colors.backgroundCard)

                // Navigation voice
                Button(action: { showingVoicePicker = true }) {
                    ProfileRow(icon: "speaker.wave.2.fill", iconColor: AppTheme.Colors.accent,
                               title: "Voz da navegação",
                               subtitle: VoiceNavigationManager.shared.isEnabled ? "Escolher voz e ouvir amostra" : "Desativada")
                }

                Divider().background(AppTheme.Colors.backgroundCard)

                // Subscription
                Button(action: { showingSubscription = true }) {
                    ProfileRow(icon: "star.fill", iconColor: Color(hex: "#f59e0b"),
                               title: lang.manageSubscriptionLabel, subtitle: lang.manageSubscriptionSubtitle,
                               badge: "PRO")
                }

                Divider().background(AppTheme.Colors.backgroundCard)

                // Privacy
                Button(action: { showingPrivacy = true }) {
                    ProfileRow(icon: "lock.shield.fill", iconColor: AppTheme.Colors.success,
                               title: lang.privacyPolicyLabel, subtitle: lang.privacyPolicySubtitle)
                }

                Divider().background(AppTheme.Colors.backgroundCard)

                // Help
                Button(action: { showingHelp = true }) {
                    ProfileRow(icon: "questionmark.circle.fill", iconColor: AppTheme.Colors.accentSoft,
                               title: lang.helpSupportLabel, subtitle: lang.helpSupportSubtitle)
                }
            }
        }
    }

    // MARK: - Log Out

    private var logoutButton: some View {
        Button(action: { showingLogOutAlert = true }) {
            HStack {
                Spacer()
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                Text(lang.logOutLabel)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .foregroundColor(AppTheme.Colors.danger)
            .padding(.vertical, 14)
            .background(AppTheme.Colors.danger.opacity(0.1))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.Colors.danger.opacity(0.3), lineWidth: 1))
        }
        .padding(.bottom, 8)
    }

    // MARK: - Color scheme helper

    private var colorSchemeFromSetting: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}

// MARK: - Reusable Sub-components

struct ProfileStatCell: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

struct ProfileSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .tracking(1.2)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            content
                .padding(.bottom, 4)
        }
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.Colors.accent.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ProfileRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppTheme.Colors.cta)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.Colors.cta.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Edit Driver Name Sheet

struct EditDriverNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var driverName: String
    @State private var tempName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(AppTheme.Colors.accent)
                        .padding(.top, 32)

                    Text("Your Driver Name")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    TextField("Enter your name", text: $tempName)
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .padding(14)
                        .background(AppTheme.Colors.backgroundCard)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(AppTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !tempName.trimmingCharacters(in: .whitespaces).isEmpty {
                            driverName = tempName.trimmingCharacters(in: .whitespaces)
                        }
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.accent)
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear { tempName = driverName }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Truck Profile Editor Sheet

struct TruckProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var truckProfile: TruckProfile

    // Local editing copy
    @State private var editType: TruckType = .semi
    @State private var editHeight: Double = 4.11
    @State private var editWeight: Double = 36.287
    @State private var editLength: Double = 16.76
    @State private var editAxleWeight: Double = 9.072
    @State private var editHazmat: Bool = false

    private let presets: [(String, TruckProfile)] = [
        ("Semi 53'", .semiFiftyThree),
        ("Semi 48'", .semiFortyEight),
        ("Straight", .straightTruck),
        ("Tanker", .tanker),
        ("Flatbed", .flatbed),
        ("Reefer", .refrigerated),
        ("Oversized", .oversized),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Truck type picker
                        ProfileSectionCard(title: "TRUCK TYPE") {
                            VStack(spacing: 0) {
                                ForEach(TruckType.allCases, id: \.self) { type in
                                    Button(action: { editType = type }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: iconFor(type))
                                                .font(.system(size: 18))
                                                .foregroundColor(editType == type ? AppTheme.Colors.cta : AppTheme.Colors.textSecondary)
                                                .frame(width: 32)
                                            Text(type.rawValue)
                                                .font(.system(size: 15, weight: editType == type ? .bold : .medium))
                                                .foregroundColor(editType == type ? .white : AppTheme.Colors.textSecondary)
                                            Spacer()
                                            if editType == type {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(AppTheme.Colors.cta)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .contentShape(Rectangle())
                                    }
                                    if type != TruckType.allCases.last {
                                        Divider().background(AppTheme.Colors.backgroundCard)
                                    }
                                }
                            }
                        }

                        // Quick presets
                        ProfileSectionCard(title: "QUICK PRESETS") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(presets, id: \.0) { name, preset in
                                        Button(action: { applyPreset(preset) }) {
                                            Text(name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(AppTheme.Colors.accent.opacity(0.25))
                                                .cornerRadius(20)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .stroke(AppTheme.Colors.accent.opacity(0.4), lineWidth: 1)
                                                )
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }

                        // Dimensions
                        ProfileSectionCard(title: "DIMENSIONS") {
                            VStack(spacing: 0) {
                                dimensionRow(label: "Height", value: $editHeight, unit: "m", icon: "arrow.up.and.down", range: 2.0...5.5, step: 0.01, imperial: metersToFeetInches(editHeight))
                                Divider().background(AppTheme.Colors.backgroundCard)
                                dimensionRow(label: "Length", value: $editLength, unit: "m", icon: "arrow.left.and.right", range: 4.0...25.0, step: 0.1, imperial: metersToFeetInches(editLength))
                                Divider().background(AppTheme.Colors.backgroundCard)
                                dimensionRow(label: "Weight (GVW)", value: $editWeight, unit: "t", icon: "scalemass.fill", range: 3.0...60.0, step: 0.1, imperial: tonnesToLbs(editWeight))
                                Divider().background(AppTheme.Colors.backgroundCard)
                                dimensionRow(label: "Axle Weight", value: $editAxleWeight, unit: "t", icon: "circle.grid.2x1.fill", range: 1.0...15.0, step: 0.1, imperial: tonnesToLbs(editAxleWeight))
                            }
                        }

                        // Hazmat toggle
                        ProfileSectionCard(title: "HAZMAT") {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(editHazmat ? AppTheme.Colors.warning : AppTheme.Colors.textSecondary)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Hazardous Materials")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("Routes will avoid restricted tunnels & zones")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: $editHazmat)
                                    .tint(AppTheme.Colors.warning)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("My Truck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Colors.backgroundInput, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        truckProfile = TruckProfile(
                            heightMeters: editHeight,
                            weightTonnes: editWeight,
                            lengthMeters: editLength,
                            axleWeightTonnes: editAxleWeight,
                            hasHazmat: editHazmat,
                            truckType: editType
                        )
                        truckProfile.save()
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.accent)
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            editType = truckProfile.truckType
            editHeight = truckProfile.heightMeters
            editWeight = truckProfile.weightTonnes
            editLength = truckProfile.lengthMeters
            editAxleWeight = truckProfile.axleWeightTonnes
            editHazmat = truckProfile.hasHazmat
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Dimension Row

    private func dimensionRow(label: String, value: Binding<Double>, unit: String, icon: String, range: ClosedRange<Double>, step: Double, imperial: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.Colors.accent)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f %@", value.wrappedValue, unit))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.Colors.cta)
                Text("(\(imperial))")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(AppTheme.Colors.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func applyPreset(_ preset: TruckProfile) {
        editType = preset.truckType
        editHeight = preset.heightMeters
        editWeight = preset.weightTonnes
        editLength = preset.lengthMeters
        editAxleWeight = preset.axleWeightTonnes
        editHazmat = preset.hasHazmat
    }

    private func iconFor(_ type: TruckType) -> String {
        switch type {
        case .semi:         return "truck.box.fill"
        case .straight:     return "box.truck.fill"
        case .tanker:       return "fuelpump.fill"
        case .flatbed:      return "shippingbox.fill"
        case .refrigerated: return "snowflake"
        }
    }

    private func metersToFeetInches(_ m: Double) -> String {
        let totalInches = m * 39.3701
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
        return "\(feet)'\(inches)\""
    }

    private func tonnesToLbs(_ t: Double) -> String {
        let lbs = Int(t * 2204.62)
        if lbs >= 1000 {
            return String(format: "%dk lbs", lbs / 1000)
        }
        return "\(lbs) lbs"
    }
}

// MARK: - Food Preferences Sheet

struct FoodPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss

    // Mirrors HealthProfileView data, stored via AppStorage JSON
    @State private var dietType   = "Standard"
    @State private var allergies: [String] = []
    @State private var conditions: [String] = []
    @State private var favoriteMeals: [String] = []
    @State private var newAllergy  = ""
    @State private var newMeal     = ""

    let dietTypes  = ["Standard", "Diabetic", "Low-Sodium", "Vegetarian", "Vegan", "Halal", "Kosher", "Gluten-Free", "Keto", "Paleo"]
    let commonAllergies = ["Gluten", "Dairy", "Nuts", "Shellfish", "Eggs", "Soy", "Fish"]
    let popularMeals    = ["Truck Stop Breakfast", "Burritos", "BBQ Plate", "Soup & Salad", "Burger", "Grilled Chicken"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {

                        // Diet Type
                        ProfileSectionCard(title: "DIET TYPE") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(dietTypes, id: \.self) { dt in
                                        Button(action: { dietType = dt }) {
                                            Text(dt)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(dietType == dt ? .white : AppTheme.Colors.textSecondary)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(dietType == dt ? AppTheme.Colors.cta : AppTheme.Colors.backgroundCard)
                                                .cornerRadius(20)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }

                        // Allergies & Restrictions
                        ProfileSectionCard(title: "ALLERGIES & RESTRICTIONS") {
                            VStack(alignment: .leading, spacing: 0) {
                                // Common allergy chips
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(commonAllergies, id: \.self) { a in
                                            let isSelected = allergies.contains(a)
                                            Button(action: {
                                                if isSelected { allergies.removeAll { $0 == a } }
                                                else { allergies.append(a) }
                                            }) {
                                                HStack(spacing: 4) {
                                                    if isSelected {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.system(size: 11))
                                                    }
                                                    Text(a)
                                                        .font(.system(size: 13, weight: .semibold))
                                                }
                                                .foregroundColor(isSelected ? .white : AppTheme.Colors.textSecondary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(isSelected ? AppTheme.Colors.danger : AppTheme.Colors.backgroundInput)
                                                .cornerRadius(20)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                }
                                Divider().background(AppTheme.Colors.backgroundInput)
                                // Custom entry
                                HStack {
                                    TextField("Add custom restriction…", text: $newAllergy)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .padding(10)
                                    Button(action: {
                                        let v = newAllergy.trimmingCharacters(in: .whitespaces)
                                        if !v.isEmpty { allergies.append(v); newAllergy = "" }
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(AppTheme.Colors.accent)
                                    }
                                    .padding(.trailing, 10)
                                }
                                // Saved list
                                ForEach(allergies.filter { !commonAllergies.contains($0) }, id: \.self) { a in
                                    HStack {
                                        Text("• \(a)")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                            .padding(.leading, 14)
                                        Spacer()
                                        Button(action: { allergies.removeAll { $0 == a } }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(AppTheme.Colors.textSecondary)
                                        }
                                        .padding(.trailing, 14)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                        // Favorite Meals
                        ProfileSectionCard(title: "FAVORITE MEALS") {
                            VStack(alignment: .leading, spacing: 0) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(popularMeals, id: \.self) { m in
                                            let isSaved = favoriteMeals.contains(m)
                                            Button(action: {
                                                if isSaved { favoriteMeals.removeAll { $0 == m } }
                                                else { favoriteMeals.append(m) }
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: isSaved ? "heart.fill" : "heart")
                                                        .font(.system(size: 11))
                                                    Text(m)
                                                        .font(.system(size: 13, weight: .semibold))
                                                }
                                                .foregroundColor(isSaved ? .white : AppTheme.Colors.textSecondary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(isSaved ? AppTheme.Colors.cta.opacity(0.7) : AppTheme.Colors.backgroundInput)
                                                .cornerRadius(20)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                }
                                Divider().background(AppTheme.Colors.backgroundInput)
                                HStack {
                                    TextField("Add a favorite meal…", text: $newMeal)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .padding(10)
                                    Button(action: {
                                        let v = newMeal.trimmingCharacters(in: .whitespaces)
                                        if !v.isEmpty { favoriteMeals.append(v); newMeal = "" }
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(AppTheme.Colors.accent)
                                    }
                                    .padding(.trailing, 10)
                                }
                                ForEach(favoriteMeals.filter { !popularMeals.contains($0) }, id: \.self) { m in
                                    HStack {
                                        Text("• \(m)")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                            .padding(.leading, 14)
                                        Spacer()
                                        Button(action: { favoriteMeals.removeAll { $0 == m } }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(AppTheme.Colors.textSecondary)
                                        }
                                        .padding(.trailing, 14)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }

                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Food Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveProfile(); dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                        .fontWeight(.bold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadProfile() }
    }

    private func loadProfile() {
        guard let data = UserDefaults.standard.data(forKey: "healthProfile"),
              let p = try? JSONDecoder().decode(HealthProfile.self, from: data) else { return }
        conditions = p.conditions
        allergies  = p.allergies
        dietType   = p.dietType

        if let mealsData = UserDefaults.standard.data(forKey: "favoriteMeals"),
           let meals = try? JSONDecoder().decode([String].self, from: mealsData) {
            favoriteMeals = meals
        }
    }

    private func saveProfile() {
        let profile = HealthProfile(conditions: conditions, allergies: allergies, dietType: dietType)
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "healthProfile")
        }
        if let data = try? JSONEncoder().encode(favoriteMeals) {
            UserDefaults.standard.set(data, forKey: "favoriteMeals")
        }
    }
}

// MARK: - Language Selection Sheet (wraps existing RegionalSettingsView)

struct LanguageSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let regionalSettings: RegionalSettingsManager

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                List {
                    ForEach(AppLanguage.allCases) { language in
                        Button(action: {
                            regionalSettings.currentLanguage = language
                            dismiss()
                        }) {
                            HStack {
                                Text(language.flagEmoji).font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(language.rawValue)
                                        .font(.headline).foregroundColor(.white)
                                    Text(language.nativeName)
                                        .font(.caption).foregroundColor(AppTheme.Colors.textSecondary)
                                }
                                Spacer()
                                if regionalSettings.currentLanguage == language {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.Colors.accent)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Privacy Policy Sheet

struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("TruckerEasy Privacy Policy")
                            .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                        Text("Last updated: January 2025")
                            .font(.caption).foregroundColor(AppTheme.Colors.textSecondary)
                        Group {
                            PolicySection(title: "Data We Collect", text: "TruckerEasy collects location data, trip logs, health check-ins, and document information solely to provide app features. No data is sold to third parties.")
                            PolicySection(title: "How We Use Your Data", text: "Your data is used to power navigation, wellness tracking, document reminders, and personalized food suggestions. All processing happens on-device where possible.")
                            PolicySection(title: "Data Storage", text: "Data is stored locally on your device using Apple's SwiftData framework. Any cloud sync is encrypted end-to-end.")
                            PolicySection(title: "Your Rights", text: "You may export or delete all your data at any time from Settings → Data. You may opt out of analytics at any time.")
                            PolicySection(title: "Contact", text: "Privacy concerns: privacy@truckereasy.app\n© 2024–2026 TruckerEasy. All rights reserved.")
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.foregroundColor(AppTheme.Colors.accent) } }
        }
        .preferredColorScheme(.dark)
    }
}

struct PolicySection: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(AppTheme.Colors.accent)
            Text(text).font(.system(size: 14)).foregroundColor(AppTheme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Help & Support Sheet

struct HelpSupportSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                List {
                    Section("Getting Started") {
                        Label("Quick Start Guide", systemImage: "book.fill").foregroundColor(.white)
                        Label("Video Tutorials", systemImage: "play.rectangle.fill").foregroundColor(.white)
                    }
                    Section("Support") {
                        Label("Contact Support", systemImage: "envelope.fill").foregroundColor(.white)
                        Label("Report a Bug", systemImage: "ant.fill").foregroundColor(.white)
                        Label("Request a Feature", systemImage: "lightbulb.fill").foregroundColor(.white)
                    }
                    Section("About") {
                        HStack {
                            Label("Version", systemImage: "info.circle.fill").foregroundColor(AppTheme.Colors.textSecondary)
                            Spacer()
                            Text("2.0.0").foregroundColor(AppTheme.Colors.textSecondary).font(.caption)
                        }
                        Label("Built by a driver. For drivers.", systemImage: "truck.box.fill")
                            .foregroundColor(AppTheme.Colors.accent).italic()
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.foregroundColor(AppTheme.Colors.accent) } }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Bypass History Sheet

struct BypassHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [WeighStationReportRecord] = []
    @State private var isLoading = true

    private var bypassRecords: [WeighStationReportRecord] {
        records.filter { $0.outcome == "bypass" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(AppTheme.Colors.accent)
                } else if bypassRecords.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 52)).foregroundColor(AppTheme.Colors.accent)
                            .padding(.top, 40)
                        Text("Bypass History")
                            .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                        Text("No bypass records yet. Your weigh station bypass records will appear here automatically.")
                            .font(.system(size: 15)).foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            HStack {
                                Text("\(bypassRecords.count) bypass\(bypassRecords.count == 1 ? "" : "es")")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppTheme.Colors.accent)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.top, 12)

                            ForEach(bypassRecords, id: \.id) { record in
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(AppTheme.Colors.success)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(record.station_name)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                        Text(Self.formatDate(record.reported_at))
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.Colors.textSecondary)
                                    }
                                    Spacer()
                                    Text("BYPASS")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundColor(AppTheme.Colors.success)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.Colors.success.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                                .padding(12)
                                .background(AppTheme.Colors.backgroundCard)
                                .cornerRadius(AppTheme.Radius.md)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("Bypass History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.foregroundColor(AppTheme.Colors.accent) } }
        }
        .preferredColorScheme(.dark)
        .task {
            do {
                records = try await SupabaseClient.shared.fetchWeighStationReports()
            } catch {
                #if DEBUG
                print("[BypassHistory] fetch failed: \(error.localizedDescription)")
                #endif
            }
            isLoading = false
        }
    }

    private static func formatDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return iso
    }
}

// MARK: - Saved Rating Model

struct SavedRating: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var locationName: String
    var category: String  // "Truck Stop" or "Facility"
    var serviceRating: Int
    var cleanlinessRating: Int
    var foodRating: Int
    var overallRating: Int
    var notes: String
}

// MARK: - My Ratings Sheet

struct MyRatingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0   // 0=Rate Now, 1=History
    @State private var locationName = ""
    @State private var category = "Truck Stop"
    @State private var serviceRating = 0
    @State private var cleanlinessRating = 0
    @State private var foodRating = 0
    @State private var overallRating = 0
    @State private var notes = ""
    @State private var savedRatings: [SavedRating] = []
    @State private var showSavedConfirmation = false

    private let categories = ["Truck Stop", "Facility/Shipper", "Fuel Station", "Rest Area"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab selector
                    HStack(spacing: 0) {
                        ForEach(["Avaliar", "Meu Historico"], id: \.self) { tab in
                            let idx = tab == "Avaliar" ? 0 : 1
                            Button(action: { selectedTab = idx }) {
                                Text(tab)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(selectedTab == idx ? .white : AppTheme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(selectedTab == idx ? AppTheme.Colors.accent.opacity(0.2) : Color.clear)
                            }
                        }
                    }
                    .background(AppTheme.Colors.backgroundCard)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.Colors.accent.opacity(0.2), lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    if selectedTab == 0 {
                        rateNowTab
                    } else {
                        historyTab
                    }
                }
            }
            .navigationTitle("My Ratings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundColor(AppTheme.Colors.accent)
                }
            }
            .overlay {
                if showSavedConfirmation {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(AppTheme.Colors.success)
                            Text("Avaliacao salva!")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(AppTheme.Colors.backgroundCard)
                        .cornerRadius(25)
                        .shadow(color: .black.opacity(0.4), radius: 8)
                        .padding(.bottom, 32)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadRatings() }
    }

    // MARK: Rate Now Tab
    private var rateNowTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {

                // Location & Category
                ProfileSectionCard(title: "LOCAL") {
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(AppTheme.Colors.accent)
                                .frame(width: 32)
                            TextField("Nome do local (ex: Pilot #234)", text: $locationName)
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        Divider().background(AppTheme.Colors.backgroundInput)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.self) { cat in
                                    Button(action: { category = cat }) {
                                        Text(cat)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(category == cat ? .white : AppTheme.Colors.textSecondary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(category == cat ? AppTheme.Colors.accent : AppTheme.Colors.backgroundInput)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                }

                // Star Ratings
                ProfileSectionCard(title: "AVALIACAO") {
                    VStack(spacing: 0) {
                        RatingQuestionRow(question: "Atendimento / Service", rating: $serviceRating, color: AppTheme.Colors.accent)
                        Divider().background(AppTheme.Colors.backgroundInput)
                        RatingQuestionRow(question: "Limpeza / Cleanliness", rating: $cleanlinessRating, color: AppTheme.Colors.cta)
                        Divider().background(AppTheme.Colors.backgroundInput)
                        RatingQuestionRow(question: "Comida / Food", rating: $foodRating, color: AppTheme.Colors.success)
                        Divider().background(AppTheme.Colors.backgroundInput)
                        RatingQuestionRow(question: "Geral / Overall", rating: $overallRating, color: AppTheme.Colors.warning)
                    }
                }

                // Notes
                ProfileSectionCard(title: "OBSERVACOES") {
                    TextField("Adicionar comentario (opcional)...", text: $notes, axis: .vertical)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .lineLimit(3...5)
                        .padding(14)
                }

                // Submit
                Button(action: saveRating) {
                    HStack {
                        Spacer()
                        Image(systemName: "star.fill")
                        Text("Salvar Avaliacao")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .background(overallRating > 0 ? AppTheme.Colors.warning : AppTheme.Colors.backgroundCard)
                    .cornerRadius(12)
                }
                .disabled(overallRating == 0 || locationName.isEmpty)

            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .padding(.top, 4)
        }
    }

    // MARK: History Tab
    private var historyTab: some View {
        Group {
            if savedRatings.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "star.slash.fill")
                        .font(.system(size: 44))
                        .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.4))
                    Text("Nenhuma avaliacao ainda")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Text("Avalie truck stops e empresas para ver o historico aqui.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(savedRatings) { rating in
                            SavedRatingCard(rating: rating)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: Actions
    private func saveRating() {
        let rating = SavedRating(
            date: Date(),
            locationName: locationName,
            category: category,
            serviceRating: serviceRating,
            cleanlinessRating: cleanlinessRating,
            foodRating: foodRating,
            overallRating: overallRating,
            notes: notes
        )
        savedRatings.insert(rating, at: 0)
        persistRatings()

        // reset form
        locationName = ""
        serviceRating = 0; cleanlinessRating = 0; foodRating = 0; overallRating = 0
        notes = ""

        withAnimation { showSavedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedConfirmation = false }
        }
        selectedTab = 1
    }

    private func persistRatings() {
        if let data = try? JSONEncoder().encode(savedRatings) {
            UserDefaults.standard.set(data, forKey: "driverRatings")
        }
    }

    private func loadRatings() {
        guard let data = UserDefaults.standard.data(forKey: "driverRatings"),
              let decoded = try? JSONDecoder().decode([SavedRating].self, from: data) else { return }
        savedRatings = decoded
    }
}

// MARK: - Rating Question Row (1-5 stars)

struct RatingQuestionRow: View {
    let question: String
    @Binding var rating: Int
    let color: Color

    var body: some View {
        HStack {
            Text(question)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Button(action: { rating = star }) {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 20))
                            .foregroundColor(star <= rating ? color : AppTheme.Colors.textSecondary.opacity(0.4))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Saved Rating Card

struct SavedRatingCard: View {
    let rating: SavedRating

    private var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: rating.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rating.locationName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(rating.category + " • " + dateText)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { s in
                        Image(systemName: s <= rating.overallRating ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(s <= rating.overallRating ? AppTheme.Colors.warning : AppTheme.Colors.textSecondary.opacity(0.3))
                    }
                }
            }

            HStack(spacing: 16) {
                ratingBadge(label: "Serv", value: rating.serviceRating, color: AppTheme.Colors.accent)
                ratingBadge(label: "Limp", value: rating.cleanlinessRating, color: AppTheme.Colors.cta)
                ratingBadge(label: "Comida", value: rating.foodRating, color: AppTheme.Colors.success)
            }

            if !rating.notes.isEmpty {
                Text(rating.notes)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.Colors.accent.opacity(0.08), lineWidth: 1))
    }

    private func ratingBadge(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(color)
            Text("\(value)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
    }
}

// MARK: - Find DMV Sheet

struct FindDMVSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var results: [MKMapItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView().tint(AppTheme.Colors.accent).te_uniformScale(1.3)
                        Text("Buscando DMV proximos...")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(AppTheme.Colors.warning)
                        Text(error)
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Tentar novamente") { Task { await search() } }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                } else if results.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "mappin.slash.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
                        Text("Nenhum DMV encontrado na sua regiao.")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(results, id: \.self) { item in
                                PlaceResultRow(item: item, accentColor: AppTheme.Colors.textSecondary)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Encontrar DMV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }.foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await search() }
    }

    private func search() async {
        isLoading = true
        errorMessage = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "DMV Department of Motor Vehicles driver license"
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems
        } catch {
            errorMessage = "Nao foi possivel buscar DMV proximos.\nVerifique sua conexao e tente novamente."
        }
        isLoading = false
    }
}

// MARK: - Drug Test Sheet

struct DrugTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var results: [MKMapItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView().tint(AppTheme.Colors.success).te_uniformScale(1.3)
                        Text("Buscando centros de drug test...")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(AppTheme.Colors.warning)
                        Text(error)
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("Tentar novamente") { Task { await search() } }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.success)
                    }
                } else if results.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 44))
                            .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
                        Text("Nenhum centro encontrado na sua regiao.")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(AppTheme.Colors.success)
                                Text("Centros DOT-certificados proximos")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppTheme.Colors.success)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            LazyVStack(spacing: 10) {
                                ForEach(results, id: \.self) { item in
                                    PlaceResultRow(item: item, accentColor: AppTheme.Colors.success)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Drug Test / DOT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }.foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await search() }
    }

    private func search() async {
        isLoading = true
        errorMessage = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "DOT drug testing clinic occupational health"
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems
        } catch {
            errorMessage = "Nao foi possivel buscar centros de drug test.\nVerifique sua conexao e tente novamente."
        }
        isLoading = false
    }
}

// MARK: - Place Result Row (shared by FindDMVSheet and DrugTestSheet)

struct PlaceResultRow: View {
    let item: MKMapItem
    let accentColor: Color

    private var address: String {
        let parts = [item.placemark.thoroughfare, item.placemark.locality, item.placemark.administrativeArea].compactMap { $0 }
        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }
        return item.placemark.title ?? item.name ?? ""
    }

    private var phone: String { item.phoneNumber ?? "" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name ?? "Location")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                if !address.isEmpty {
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                if !phone.isEmpty {
                    Text(phone)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            }) {
                Text("GPS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(accentColor)
                    .cornerRadius(20)
            }
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Stop Advisor Sheet

struct StopAdvisorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 52)).foregroundColor(AppTheme.Colors.cta)
                        .padding(.top, 40)
                    Text("Stop Advisor")
                        .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                    Text("Based on your route, HOS remaining, and food preferences, TruckerEasy will suggest the best stops along your way.")
                        .font(.system(size: 15)).foregroundColor(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            }
            .navigationTitle("Stop Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.foregroundColor(AppTheme.Colors.accent) } }
        }
        .preferredColorScheme(.dark)
    }
}
