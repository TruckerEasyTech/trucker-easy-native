import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Medication.reminderTime) private var medications: [Medication]

    @State private var regionalSettings = RegionalSettingsManager()
    @State private var selectedTab = 0
    @State private var ptt = PushToTalkService.shared
    @State private var showingPTTSheet = false

    init() {
        // Matte Gold + Black tab bar
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(red: 0.039, green: 0.035, blue: 0.024, alpha: 1) // #0a0906

        // Matte gold inactive: #6b5a3a  active: #c9a84c
        let goldInactive = UIColor(red: 0.420, green: 0.353, blue: 0.227, alpha: 1)
        let goldActive   = UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: 1)

        let normalAttr: [NSAttributedString.Key: Any]   = [.foregroundColor: goldInactive]
        let selectedAttr: [NSAttributedString.Key: Any] = [.foregroundColor: goldActive]

        tabBarAppearance.stackedLayoutAppearance.normal.iconColor    = goldInactive
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor  = goldActive
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes   = normalAttr
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttr

        UITabBar.appearance().standardAppearance    = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance  = tabBarAppearance

        // Navigation bar — warm black + gold tint
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(red: 0.082, green: 0.071, blue: 0.047, alpha: 1) // #151210
        navAppearance.titleTextAttributes      = [.foregroundColor: UIColor(red: 0.961, green: 0.941, blue: 0.910, alpha: 1)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(red: 0.961, green: 0.941, blue: 0.910, alpha: 1)]
        UINavigationBar.appearance().standardAppearance    = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance  = navAppearance
        UINavigationBar.appearance().tintColor             = goldActive
    }

    var body: some View {
        let lang = regionalSettings.lang
        TabView(selection: $selectedTab) {
            // Tab 1: My Horizon (Map & Navigation)
            HorizonView()
                .tabItem {
                    Label(lang.tabHorizon, systemImage: selectedTab == 0 ? "map.fill" : "map")
                }
                .tag(0)

            // Tab 2: My Check-up (Health & Wellness)
            CheckupView()
                .tabItem {
                    Label(lang.tabCheckup, systemImage: selectedTab == 1 ? "heart.fill" : "heart")
                }
                .tag(1)

            // Tab 3: My Cabin (Documents & Compliance)
            CabinView()
                .tabItem {
                    Label(lang.tabCabin, systemImage: selectedTab == 2 ? "folder.fill" : "folder")
                }
                .tag(2)

            // Tab 4: Road Talk (Community & News)
            RoadTalkView()
                .tabItem {
                    Label(lang.tabRoadTalk, systemImage: selectedTab == 3 ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                }
                .tag(3)

            // Tab 5: My Profile (Driver data, food prefs, settings)
            DriverProfileView()
                .tabItem {
                    Label(lang.tabProfile, systemImage: selectedTab == 4 ? "person.fill" : "person")
                }
                .tag(4)
        }
        .preferredColorScheme(.dark)
        .task {
            MedicationNotificationScheduler.syncAll(medications: medications, modelContext: modelContext)
        }
        .onChange(of: medications.count) { _, _ in
            MedicationNotificationScheduler.syncAll(medications: medications, modelContext: modelContext)
        }
        .environment(regionalSettings)
        .environment(\.layoutDirection, regionalSettings.currentLanguage.isRTL ? .rightToLeft : .leftToRight)
        // Compact flag language picker — keep off map tab to prevent overlap with navigation HUD
        .overlay(alignment: .topTrailing) {
            if selectedTab != 0 {
                FlagLanguagePicker(regionalSettings: regionalSettings)
                    .padding(.top, 56)
                    .padding(.trailing, 12)
            }
        }
        // Floating Ch.19 PTT button — keep off map tab and Road Talk to avoid stacked controls
        .overlay(alignment: .bottomLeading) {
            if selectedTab != 0 && selectedTab != 3 {
                FloatingPTTButton(ptt: ptt, onTap: { selectedTab = 3 })
                    .padding(.leading, 16)
                    .padding(.bottom, 88) // above tab bar
                    .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
            }
        }
    }
}

// MARK: - Regional Settings View
struct RegionalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RegionalSettingsManager.self) private var regionalSettings

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                List {
                    // MARK: Language Section
                    Section("Language / Idioma / Langue / Sprache") {
                        ForEach(AppLanguage.allCases) { language in
                            Button(action: {
                                regionalSettings.currentLanguage = language
                            }) {
                                HStack {
                                    Text(language.flagEmoji).font(.title2)
                                    Text(language.rawValue)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    if regionalSettings.currentLanguage == language {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppTheme.Colors.accent)
                                    }
                                }
                            }
                        }
                    }

                    // MARK: Region Section
                    Section("Region & HOS Rules") {
                        ForEach(SupportedRegion.allCases) { region in
                            Button(action: {
                                regionalSettings.currentRegion = region
                            }) {
                                HStack(spacing: 12) {
                                    Text(region.flagEmoji).font(.title2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(region.rawValue)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        HStack(spacing: 8) {
                                            Label(region.currencySymbol, systemImage: "banknote")
                                                .font(.caption)
                                                .foregroundColor(AppTheme.Colors.textSecondary)
                                            Label(region.distanceUnit, systemImage: "road.lanes")
                                                .font(.caption)
                                                .foregroundColor(AppTheme.Colors.textSecondary)
                                            Label(region.fuelUnit, systemImage: "fuelpump")
                                                .font(.caption)
                                                .foregroundColor(AppTheme.Colors.textSecondary)
                                        }
                                        // HOS preview
                                        let hos = region.hosRules
                                        Text("Max \(String(format: "%.0f", hos.maxDrivingHours))h drive · \(hos.weeklyHoursLimit)h/week · \(String(format: "%.0f", hos.restBetweenShiftsHours))h rest")
                                            .font(.caption2)
                                            .foregroundColor(AppTheme.Colors.warning)
                                    }
                                    Spacer()
                                    if regionalSettings.currentRegion == region {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppTheme.Colors.accent)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    // MARK: Current HOS Rules summary
                    Section("Active HOS Rules — \(regionalSettings.currentRegion.hosRules.authority)") {
                        let hos = regionalSettings.currentRegion.hosRules
                        HOSRuleRow(icon: "clock.fill", color: AppTheme.Colors.accent,
                                   label: "Max driving/day", value: "\(String(format: "%.0f", hos.maxDrivingHours))h")
                        HOSRuleRow(icon: "timer", color: AppTheme.Colors.warning,
                                   label: "Service window", value: "\(String(format: "%.0f", hos.serviceWindowHours))h")
                        HOSRuleRow(icon: "cup.and.saucer.fill", color: AppTheme.Colors.success,
                                   label: "Break after \(String(format: "%.1f", hos.mandatoryBreakAfterHours))h", value: "\(hos.mandatoryBreakMinutes) min")
                        HOSRuleRow(icon: "bed.double.fill", color: AppTheme.Colors.accentSoft,
                                   label: "Rest between shifts", value: "\(String(format: "%.0f", hos.restBetweenShiftsHours))h")
                        HOSRuleRow(icon: "calendar.badge.clock", color: AppTheme.Colors.danger,
                                   label: "Weekly limit", value: "\(hos.weeklyHoursLimit)h")
                        HOSRuleRow(icon: "scalemass.fill", color: AppTheme.Colors.ctaGlow,
                                   label: "Max weight", value: regionalSettings.currentRegion.weightUnit == "lbs"
                                   ? "\(String(format: "%.0f", hos.weightLimitLbs)) lbs"
                                   : "\(String(format: "%.1f", hos.weightLimitTonnes)) t")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct HOSRuleRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .font(AppTheme.Typography.caption())
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .font(AppTheme.Typography.captionBold())
        }
    }
}

// MARK: - Safety Tips View
struct SafetyTipsView: View {
    let tips = [
        SafetyTip(icon: "bed.double.fill", title: "Rest Regularly",
                  description: "Take breaks every 2 hours. Get 7-8 hours of sleep before long trips.",
                  color: AppTheme.Colors.accent),
        SafetyTip(icon: "speedometer", title: "Follow Speed Limits",
                  description: "Maintain safe speeds and adjust for weather conditions.",
                  color: AppTheme.Colors.warning),
        SafetyTip(icon: "eye", title: "Stay Alert",
                  description: "Avoid driving when drowsy. Use rest areas when needed.",
                  color: AppTheme.Colors.success),
        SafetyTip(icon: "checkmark.shield", title: "Vehicle Inspection",
                  description: "Perform daily pre-trip inspections. Check tires, brakes, lights.",
                  color: AppTheme.Colors.accentSoft),
        SafetyTip(icon: "exclamationmark.triangle", title: "Weather Awareness",
                  description: "Monitor weather conditions. Slow down in rain, snow, or fog.",
                  color: AppTheme.Colors.danger),
        SafetyTip(icon: "phone.down", title: "No Distractions",
                  description: "Avoid phone use while driving. Pull over if you need to make calls.",
                  color: AppTheme.Colors.cta)
    ]

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(tips) { tip in
                        SafetyTipCard(tip: tip)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Safety Tips")
    }
}

struct SafetyTip: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct SafetyTipCard: View {
    let tip: SafetyTip
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: tip.icon)
                .font(.title)
                .foregroundColor(tip.color)
                .frame(width: 56, height: 56)
                .background(tip.color.opacity(0.15))
                .cornerRadius(AppTheme.Radius.md)
            VStack(alignment: .leading, spacing: 6) {
                Text(tip.title)
                    .font(AppTheme.Typography.cardTitle())
                    .foregroundColor(.white)
                Text(tip.description)
                    .font(AppTheme.Typography.caption())
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding()
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }
}

// MARK: - App Settings
struct AppSettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("autoBackup") private var autoBackup = true

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()
            Form {
                Section("Notifications") {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    Toggle("Document Expiry Alerts", isOn: $notificationsEnabled)
                    Toggle("Medication Reminders", isOn: $notificationsEnabled)
                    Toggle("Trip Reminders", isOn: $notificationsEnabled)
                }
                Section("Data") {
                    Toggle("Auto Backup", isOn: $autoBackup)
                    Button("Export Data") {}
                    Button("Clear Cache") {}
                        .foregroundColor(AppTheme.Colors.warning)
                }
                Section("Subscription") {
                    NavigationLink(destination: SubscriptionView()) {
                        Label("Manage Plan", systemImage: "star.fill")
                            .foregroundColor(AppTheme.Colors.cta)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()
            List {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "truck.box.fill")
                            .font(.system(size: 64))
                            .foregroundColor(AppTheme.Colors.accent)
                        Text("TruckerEasy")
                            .font(AppTheme.Typography.heroTitle())
                            .foregroundColor(.white)
                        Text("Version 2.0.0")
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        Text("\"Built by a driver. For drivers.\"")
                            .font(AppTheme.Typography.body())
                            .foregroundColor(AppTheme.Colors.accent)
                            .italic()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                Section("Features") {
                    Label("My Horizon – Map & Navigation", systemImage: "map.fill")
                    Label("My Check-up – Health & Wellness", systemImage: "heart.fill")
                    Label("My Cabin – Documents & Compliance", systemImage: "folder.fill")
                    Label("Road Talk – News & Community", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("About")
    }
}

// MARK: - Help View
struct HelpView: View {
    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()
            List {
                Section("Getting Started") {
                    NavigationLink("Quick Start Guide") { Text("Quick Start Guide").padding() }
                    NavigationLink("Tutorial Videos") { Text("Tutorial Videos").padding() }
                }
                Section("Support") {
                    Button("Contact Support") {}
                    Button("Report a Bug") {}
                    Button("Request a Feature") {}
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Help & Support")
    }
}

// MARK: - Floating PTT Mini Button (persistent overlay from map/any tab)

struct FloatingPTTButton: View {
    let ptt: PushToTalkService
    let onTap: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    private var isOnAir: Bool { ptt.connectionState.isOnAir }
    private var isTalking: Bool { ptt.isTalking }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                ZStack {
                    if isOnAir {
                        Circle()
                            .fill(Color(hex: "#22d474").opacity(0.25))
                            .frame(width: 28, height: 28)
                            .te_uniformScale(pulseScale)
                    }
                    Image(systemName: isOnAir ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isOnAir ? Color(hex: "#22d474") : Color(hex: "#9ca3af"))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("CH 19")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.white)
                        .kerning(0.8)
                    Text(isOnAir ? (isTalking ? "LIVE" : "ON AIR") : "TAP TO JOIN")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isOnAir ? Color(hex: "#22d474") : Color(hex: "#6b7280"))
                        .kerning(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .background(
                isOnAir
                    ? Color(hex: "#22d474").opacity(0.08)
                    : Color(hex: "#0d1b2a").opacity(0.6)
            )
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        isOnAir ? Color(hex: "#22d474").opacity(isTalking ? 0.9 : 0.4) : Color.white.opacity(0.1),
                        lineWidth: isTalking ? 2 : 1
                    )
            )
            .shadow(
                color: isOnAir ? Color(hex: "#22d474").opacity(0.3) : .black.opacity(0.4),
                radius: isOnAir ? 8 : 4, y: 2
            )
        }
        .onAppear {
            guard isOnAir else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.4
            }
        }
        .onChange(of: isOnAir) { _, onAir in
            if onAir {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.4
                }
            } else {
                withAnimation { pulseScale = 1.0 }
            }
        }
    }
}

// MARK: - Compact Flag Language Picker

struct FlagLanguagePicker: View {
    let regionalSettings: RegionalSettingsManager
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Current language button (always visible)
            Button(action: { withAnimation(.spring(response: 0.3)) { expanded.toggle() } }) {
                HStack(spacing: 5) {
                    Text(regionalSettings.currentLanguage.flagEmoji)
                        .font(.system(size: 16))
                    if !expanded {
                        Text(regionalSettings.currentLanguage.code.prefix(2).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .cornerRadius(AppTheme.Radius.pill)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.pill)
                        .stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 1)
                )
            }

            // Expanded language grid
            if expanded {
                VStack(spacing: 0) {
                    ForEach(AppLanguage.allCases) { language in
                        Button(action: {
                            regionalSettings.currentLanguage = language
                            withAnimation { expanded = false }
                        }) {
                            HStack(spacing: 8) {
                                Text(language.flagEmoji)
                                    .font(.system(size: 14))
                                Text(language.nativeName)
                                    .font(.system(size: 12, weight: regionalSettings.currentLanguage == language ? .bold : .regular))
                                    .foregroundColor(regionalSettings.currentLanguage == language ? AppTheme.Colors.accent : .white)
                                    .lineLimit(1)
                                Spacer()
                                if regionalSettings.currentLanguage == language {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppTheme.Colors.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(regionalSettings.currentLanguage == language ? AppTheme.Colors.accent.opacity(0.08) : Color.clear)
                        }
                        if language != AppLanguage.allCases.last {
                            Divider()
                                .background(AppTheme.Colors.backgroundCard.opacity(0.5))
                        }
                    }
                }
                .frame(width: 190)
                .background(.ultraThinMaterial)
                .cornerRadius(AppTheme.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Launch Wellness Check-In (Daily, automatic)

struct LaunchWellnessCheckIn: View {
    let lang: AppLanguage
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var selectedMood: Int = 0
    @State private var sleepHours: Double = 7
    @State private var hadBreakfast = false
    @State private var feltRested = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.Colors.backgroundInput, AppTheme.Colors.background],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(lang.goodMorningDriver)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(lang.dailyCheckInTitle)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(.top, 52)
                .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: AppTheme.Spacing.md) {
                        MoodCheckCard(
                            moodRating: $selectedMood,
                            saved: false,
                            onSave: { },
                            howAreYouText: lang.howAreYouFeeling,
                            tapStarText: lang.tapStarMoodLabel
                        )

                        sleepCard
                        preCheckCard
                    }
                    .padding(AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.lg)
                }

                VStack(spacing: 10) {
                    Button(action: saveAndComplete) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text(lang.readyToDriveLabel)
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: selectedMood > 0
                                    ? [AppTheme.Colors.cta, Color(hex: "#E65100")]
                                    : [Color.gray.opacity(0.35), Color.gray.opacity(0.25)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .cornerRadius(AppTheme.Radius.md)
                    }
                    .disabled(selectedMood == 0)

                    Button(action: onComplete) {
                        Text(lang.skipForNowLabel)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.lg + 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveAndComplete() {
        let now = Date()
        if selectedMood > 0 {
            let moodLog = WellnessLog(category: .mental, date: now)
            moodLog.stressLevel = 6 - selectedMood
            moodLog.notes = "Mood \(selectedMood)/5"
            modelContext.insert(moodLog)
        }
        if sleepHours > 0 {
            let sleepLog = WellnessLog(category: .rest, date: now)
            sleepLog.hoursSlept = sleepHours
            sleepLog.notes = feltRested ? "Felt rested" : "Didn't feel fully rested"
            modelContext.insert(sleepLog)
        }
        if hadBreakfast {
            let mealLog = WellnessLog(category: .nutrition, date: now)
            mealLog.notes = "Had breakfast before driving"
            modelContext.insert(mealLog)
        }
        try? modelContext.save()

        if selectedMood > 0 {
            WellnessCloudSync.pushDailyCheckin(
                moodStars: selectedMood,
                sleepHours: sleepHours > 0 ? sleepHours : nil,
                hadMeal: hadBreakfast,
                feltRested: feltRested,
                source: .launch
            )
        }
        onComplete()
    }

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Hours slept last night", systemImage: "bed.double.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.1fh", sleepHours))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(sleepHours >= 7 ? AppTheme.Colors.success : AppTheme.Colors.warning)
            }
            Slider(value: $sleepHours, in: 1...12, step: 0.5)
                .accentColor(sleepHours >= 7 ? AppTheme.Colors.success : AppTheme.Colors.warning)
            HStack {
                Text("1h").font(.system(size: 10)).foregroundColor(AppTheme.Colors.textSecondary)
                Spacer()
                Text("7h (min recommended)").font(.system(size: 10)).foregroundColor(AppTheme.Colors.textSecondary)
                Spacer()
                Text("12h").font(.system(size: 10)).foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundSecond)
        .cornerRadius(AppTheme.Radius.md)
    }

    // MARK: Pre-check toggles
    private var preCheckCard: some View {
        VStack(spacing: 10) {
            checkToggle(label: "Had breakfast / meal", isOn: $hadBreakfast)
            Divider().background(AppTheme.Colors.backgroundCard)
            checkToggle(label: "Felt rested after sleep", isOn: $feltRested)
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundSecond)
        .cornerRadius(AppTheme.Radius.md)
    }

    private func checkToggle(label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white)
        }
        .toggleStyle(SwitchToggleStyle(tint: AppTheme.Colors.success))
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [
            Trip.self, FuelPurchase.self, Expense.self, IFTAReport.self,
            TruckDocument.self, GeofenceRegion.self, CommunityPost.self,
            ChatMessage.self, WellnessLog.self
        ], inMemory: true)
}
