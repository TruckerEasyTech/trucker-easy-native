import SwiftUI
import SwiftData
import Combine
import UserNotifications
#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - Medication Model
@Model
class Medication {
    var id: UUID
    var name: String
    var dosage: String
    var reminderTime: Date        // primary time (kept for backward compatibility)
    var extraReminderTimes: [Date] // additional times per day
    var isActive: Bool
    var takenToday: Bool
    var lastTakenDate: Date?

    /// All reminder times (primary + extras), sorted ascending
    var allReminderTimes: [Date] {
        ([reminderTime] + extraReminderTimes).sorted()
    }

    init(name: String, dosage: String, reminderTimes: [Date]) {
        self.id = UUID()
        self.name = name
        self.dosage = dosage
        self.reminderTime = reminderTimes.first ?? Date()
        self.extraReminderTimes = reminderTimes.count > 1 ? Array(reminderTimes.dropFirst()) : []
        self.isActive = true
        self.takenToday = false
    }
}

// MARK: - Health Profile
struct HealthProfile: Codable {
    var conditions: [String]
    var allergies: [String]
    var dietType: String

    static let `default` = HealthProfile(conditions: [], allergies: [], dietType: "Standard")

    /// Loads health profile from UserDefaults (saved in CheckupView)
    static func loadSaved() -> HealthProfile {
        if let data = UserDefaults.standard.data(forKey: "healthProfile"),
           let profile = try? JSONDecoder().decode(HealthProfile.self, from: data) {
            return profile
        }
        return .default
    }

    /// MKLocalSearch query based on driver's diet and health conditions
    var foodSearchQuery: String {
        switch dietType.lowercased() {
        case "vegetarian":  return "vegetarian restaurant"
        case "vegan":       return "vegan restaurant"
        case "diabetic", "diabetes":
                            return "healthy restaurant low sugar"
        case "heart healthy", "cardiac":
                            return "healthy heart-friendly restaurant"
        case "gluten free": return "gluten free restaurant"
        case "halal":       return "halal restaurant"
        default:            return "diner restaurant truck stop food"
        }
    }

    /// Short reason text shown in food suggestion banner
    var suggestionReason: String {
        switch dietType.lowercased() {
        case "vegetarian":  return "Vegetarian options"
        case "vegan":       return "Vegan options"
        case "diabetic", "diabetes":
                            return "Low sugar options"
        case "heart healthy", "cardiac":
                            return "Heart-healthy options"
        case "gluten free": return "Gluten-free options"
        case "halal":       return "Halal certified"
        default:            return "Trucker-friendly food"
        }
    }
}

// MARK: - Checkup View (Tab 2) — Driver Wellness Hub
struct CheckupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @Query(sort: \WellnessLog.date, order: .reverse) private var logs: [WellnessLog]
    @Query private var medications: [Medication]

    @State private var moodRating: Int = 0
    @State private var hkSteps: Int = 0
    @State private var hkSleepHours: Double = 0
    @State private var showingAddMedication = false
    @State private var medicationAlert: Medication? = nil
    @State private var showingMedicationAlert = false
    @State private var showingHealthProfile = false
    @State private var showingSleepLog = false
    @State private var showingHOSInfo = false
    @State private var showingTelemedicine = false
    @State private var showingLotusCortex = false

    var todaysLogs: [WellnessLog] { logs.filter { $0.date.isToday } }
    var todayMood: WellnessLog? { todaysLogs.first { $0.category == .mental } }
    // Sleep: use the most recent log for today (not a sum — prevents double-counting)
    var totalSleepToday: Double { todaysLogs.filter { $0.category == .rest }.compactMap { $0.hoursSlept }.max() ?? 0 }
    var totalExerciseToday: Int { todaysLogs.filter { $0.category == .exercise }.compactMap { $0.exerciseMinutes }.reduce(0, +) }
    var totalWaterToday: Int { todaysLogs.filter { $0.category == .nutrition }.compactMap { $0.waterIntake }.reduce(0, +) }

    var lang: AppLanguage { regionalSettings.currentLanguage }

    var driverStatusMessage: (String, Color) {
        guard !todaysLogs.isEmpty else {
            return ("Log your wellness to see your status", AppTheme.Colors.textSecondary)
        }
        let score = calculateWellnessScore()
        switch score {
        case 80...100: return (lang.statusGreat, AppTheme.Colors.success)
        case 60..<80:  return (lang.statusGood, AppTheme.Colors.accent)
        case 40..<60:  return (lang.statusFatigue, AppTheme.Colors.warning)
        default:       return (lang.fatigueWarning, AppTheme.Colors.danger)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {

                    // MARK: Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lang.checkupTitle)
                                .font(AppTheme.Typography.heroTitle())
                                .foregroundColor(.white)
                            Text(lang.wellnessPriority)
                                .font(AppTheme.Typography.caption())
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Button(action: { showingHealthProfile = true }) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.Colors.accent.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(AppTheme.Colors.accent)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.top, AppTheme.Spacing.md)

                    // MARK: Driver Status Banner
                    DriverStatusBanner(
                        message: driverStatusMessage.0,
                        color: driverStatusMessage.1,
                        wellnessScore: calculateWellnessScore(),
                        dayStatusText: lang.dayStatusLabel
                    )
                    .padding(.horizontal, AppTheme.Spacing.md)

                    // MARK: Mood Check — 5 estrelas
                    MoodCheckCard(
                        moodRating: $moodRating,
                        saved: todayMood != nil,
                        onSave: { saveMood(rating: moodRating) },
                        howAreYouText: lang.howAreYouFeeling,
                        savedText: lang.savedLabel,
                        tapStarText: lang.tapStarMoodLabel
                    )
                    .padding(.horizontal, AppTheme.Spacing.md)

                    // MARK: Today's Vitals
                    TodayVitalsCard(
                        sleepHours: totalSleepToday,
                        exerciseMins: totalExerciseToday,
                        waterGlasses: totalWaterToday,
                        moodRating: todayMood != nil ? moodRating : 0,
                        hkSteps: hkSteps,
                        hkSleepHours: hkSleepHours,
                        todayText: lang.todayLabel,
                        sleepText: lang.sleepLabel,
                        exerciseText: lang.exerciseLabel,
                        waterText: lang.waterLabel,
                        moodText: lang.moodLabel
                    )
                    .padding(.horizontal, AppTheme.Spacing.md)

                    // MARK: Quick Log
                    WellnessQuickAdd { category, value in
                        saveWellnessLog(category: category, value: value)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)

                    // MARK: HOS / Fatigue Awareness
                    HOSFatigueBanner(hos: regionalSettings.hosRules, onLearnMore: { showingHOSInfo = true })
                        .padding(.horizontal, AppTheme.Spacing.md)

                    // MARK: Medications
                    MedicationsCard(
                        medications: medications,
                        onAddMedication: { showingAddMedication = true },
                        onMedicationTap: { med in
                            medicationAlert = med
                            showingMedicationAlert = true
                        },
                        medicationsText: lang.medicationsLabel,
                        pendingText: lang.pendingLabel,
                        addMedicationText: lang.addMedicationLabel
                    )
                    .padding(.horizontal, AppTheme.Spacing.md)

                    // MARK: Today's Activity Log
                    if !todaysLogs.isEmpty {
                        TodayActivityLog(logs: todaysLogs)
                            .padding(.horizontal, AppTheme.Spacing.md)
                    }

                    // MARK: Driver Wellness Tips
                    DriverWellnessTips()
                        .padding(.horizontal, AppTheme.Spacing.md)

                    // MARK: Mental Health CTA
                    MentalHealthSupportCard()
                        .padding(.horizontal, AppTheme.Spacing.md)

                    // MARK: Lotus Cortex (AI wellness + telehealth screening)
                    LotusCortexCard(onTap: { showingLotusCortex = true })
                        .padding(.horizontal, AppTheme.Spacing.md)

                    // MARK: Telemedicine (DoctorsHero)
                    TelemedicineCard(onTap: { showingTelemedicine = true })
                        .padding(.horizontal, AppTheme.Spacing.md)

                    Spacer(minLength: AppTheme.Spacing.xxl)
                }
            }
        }
        .sheet(isPresented: $showingAddMedication) {
            AddMedicationView()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingHealthProfile) {
            HealthProfileView()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingHOSInfo) {
            HOSInfoSheet(hos: regionalSettings.hosRules)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingTelemedicine) {
            TelemedicineView()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingLotusCortex) {
            CortexWellnessView()
                .preferredColorScheme(.dark)
        }
        .overlay(
            Group {
                if showingMedicationAlert, let med = medicationAlert {
                    MedicationAlertOverlay(
                        medication: med,
                        onTaken: {
                            markMedicationTaken(med)
                            showingMedicationAlert = false
                        },
                        onSnooze: { showingMedicationAlert = false }
                    )
                }
            }
        )
        .onAppear {
            checkMedicationReminders()
            #if canImport(HealthKit)
            if let hk = HealthKitManager.shared {
                hk.fetchTodaySteps { steps in hkSteps = steps }
                hk.fetchLastNightSleep { hours in hkSleepHours = hours }
            }
            #endif
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            checkMedicationReminders()
        }
    }

    private func calculateWellnessScore() -> Double {
        // Return 0 if nothing has been logged today yet
        guard !todaysLogs.isEmpty else { return 0 }
        var score = 0.0
        // Sleep: max 40 pts
        let sleep = totalSleepToday
        if sleep >= 7      { score += 40 }
        else if sleep >= 5 { score += 22 }
        else if sleep > 0  { score += 10 }
        // Mood: max 30 pts — stressLevel = 6 - moodRating, so invert back
        if let mood = todayMood {
            let moodRating = 6 - (mood.stressLevel ?? 3)   // 1–5
            score += Double(max(0, moodRating)) * 6.0       // max 30
        }
        // Exercise: max 15 pts
        if totalExerciseToday >= 20      { score += 15 }
        else if totalExerciseToday > 0   { score += 8 }
        // Water: max 15 pts
        if totalWaterToday >= 8          { score += 15 }
        else if totalWaterToday >= 4     { score += 8 }
        else if totalWaterToday > 0      { score += 4 }
        return min(score, 100)
    }

    private func saveMood(rating: Int) {
        // Update existing today's mood entry instead of creating a duplicate
        if let existing = todayMood {
            existing.stressLevel = 6 - rating
            existing.notes = moodRatingText(rating)
            existing.date = Date()
        } else {
            let log = WellnessLog(category: .mental, date: Date(), notes: moodRatingText(rating))
            log.stressLevel = 6 - rating
            modelContext.insert(log)
        }
        try? modelContext.save()
        WellnessCloudSync.pushDailyCheckin(moodStars: rating, source: .checkup)
    }

    private func moodRatingText(_ r: Int) -> String {
        r > 0 ? "Mood \(r)/5" : ""
    }

    private func saveWellnessLog(category: WellnessCategory, value: Double) {
        let log = WellnessLog(category: category, date: Date())
        switch category {
        case .rest:      log.hoursSlept = value
        case .exercise:  log.exerciseMinutes = Int(value)
        case .nutrition: log.waterIntake = Int(value)
        case .mental:    log.stressLevel = Int(value)
        case .safety:    log.notes = "Safety check completed"
        }
        modelContext.insert(log)
    }

    private func markMedicationTaken(_ med: Medication) {
        med.takenToday = true
        med.lastTakenDate = Date()
    }

    private func checkMedicationReminders() {
        let now = Date()
        let cal = Calendar.current
        for med in medications where med.isActive && !med.takenToday {
            for time in med.allReminderTimes {
                guard
                    let todayReminder = cal.date(
                        bySettingHour: cal.component(.hour, from: time),
                        minute: cal.component(.minute, from: time),
                        second: 0,
                        of: now
                    )
                else { continue }
                // Janela: até 2 min antes e até 45 min depois do horário programado
                let delta = now.timeIntervalSince(todayReminder)
                if delta >= -120 && delta <= 2700 {
                    medicationAlert = med
                    showingMedicationAlert = true
                    return
                }
            }
        }
    }
}

// MARK: - Driver Status Banner
struct DriverStatusBanner: View {
    let message: String
    let color: Color
    let wellnessScore: Double
    var dayStatusText: String = "DAY STATUS"

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: statusIcon)
                        .font(.system(size: 22))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayStatusText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(color.opacity(0.8))
                        .kerning(1.2)
                    Text(message)
                        .font(AppTheme.Typography.captionBold())
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(Int(wellnessScore))")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(color)
                    Text("pts")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.Colors.backgroundInput)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * (wellnessScore / 100), height: 6)
                        .animation(.easeOut(duration: 0.8), value: wellnessScore)
                }
            }
            .frame(height: 6)
        }
        .padding(AppTheme.Spacing.md)
        .background(color.opacity(0.08))
        .cornerRadius(AppTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    private var statusIcon: String {
        switch Int(wellnessScore) {
        case 80...100: return "checkmark.shield.fill"
        case 60..<80:  return "face.smiling.fill"
        case 40..<60:  return "exclamationmark.circle.fill"
        default:       return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Wellness Star Rating (1–5, sem emoji)
struct WellnessStarRating: View {
    @Binding var rating: Int
    var starSize: CGFloat = 38
    var spacing: CGFloat = 16
    var onSelect: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...5, id: \.self) { star in
                Button(action: {
                    rating = star
                    onSelect?()
                }) {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: starSize))
                        .foregroundColor(star <= rating ? starColor(star) : Color.white.opacity(0.25))
                        .te_uniformScale(star == rating ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: rating)
                }
            }
        }
    }

    private func starColor(_ star: Int) -> Color {
        switch star {
        case 1: return AppTheme.Colors.danger
        case 2: return AppTheme.Colors.warning
        case 3: return AppTheme.Colors.ctaGlow
        case 4: return AppTheme.Colors.success
        case 5: return AppTheme.Colors.accent
        default: return AppTheme.Colors.textSecondary
        }
    }
}

// MARK: - Mood Check Card
struct MoodCheckCard: View {
    @Binding var moodRating: Int
    let saved: Bool
    let onSave: () -> Void
    var howAreYouText: String = "How are you feeling?"
    var savedText: String = "Saved"
    var tapStarText: String = "Tap a star to log your mood"
    var showsFeedback: Bool = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack {
                Text(howAreYouText)
                    .font(AppTheme.Typography.cardTitle())
                    .foregroundColor(.white)
                Spacer()
                if saved && moodRating > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppTheme.Colors.success)
                            .font(.system(size: 14))
                        Text(savedText)
                            .font(AppTheme.Typography.small())
                            .foregroundColor(AppTheme.Colors.success)
                    }
                }
            }

            WellnessStarRating(rating: $moodRating, onSelect: onSave)

            if moodRating == 0 {
                Text(tapStarText)
                    .font(AppTheme.Typography.caption())
                    .foregroundColor(AppTheme.Colors.textSecondary)
            } else if showsFeedback {
                Text(moodLabel)
                    .font(AppTheme.Typography.captionBold())
                    .foregroundColor(moodColor(moodRating))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(moodColor(moodRating).opacity(0.1))
                    .cornerRadius(AppTheme.Radius.pill)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(moodRating)/5")
                    .font(AppTheme.Typography.caption())
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.lg)
    }

    private func moodColor(_ rating: Int) -> Color {
        switch rating {
        case 1: return AppTheme.Colors.danger
        case 2: return AppTheme.Colors.warning
        case 3: return AppTheme.Colors.ctaGlow
        case 4: return AppTheme.Colors.success
        case 5: return AppTheme.Colors.accent
        default: return AppTheme.Colors.textSecondary
        }
    }

    private var moodLabel: String {
        switch moodRating {
        case 1: return "Feeling bad — take it easy"
        case 2: return "Below normal — rest when you can"
        case 3: return "Getting by — stay hydrated"
        case 4: return "Feeling good — keep it up!"
        case 5: return "Great! Drive safely!"
        default: return ""
        }
    }
}

// MARK: - Today Vitals Card
struct TodayVitalsCard: View {
    let sleepHours: Double
    let exerciseMins: Int
    let waterGlasses: Int
    let moodRating: Int
    var hkSteps: Int = 0
    var hkSleepHours: Double = 0
    var todayText: String = "TODAY"
    var sleepText: String = "Sleep"
    var exerciseText: String = "Exercise"
    var waterText: String = "Water"
    var moodText: String = "Mood"

    private var stepsFormatted: String {
        hkSteps > 0 ? (hkSteps >= 1000 ? "\(hkSteps / 1000)k" : "\(hkSteps)") : "--"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(todayText)
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.5)

            HStack(spacing: AppTheme.Spacing.sm) {
                VitalCard(
                    icon: "moon.zzz.fill",
                    value: sleepHours > 0 ? String(format: "%.0fh", sleepHours) : "--",
                    label: sleepText,
                    color: AppTheme.Colors.accentSoft,
                    isGood: sleepHours >= 7
                )
                VitalCard(
                    icon: "figure.walk",
                    value: exerciseMins > 0 ? "\(exerciseMins)m" : "--",
                    label: exerciseText,
                    color: AppTheme.Colors.success,
                    isGood: exerciseMins >= 20
                )
                VitalCard(
                    icon: "drop.fill",
                    value: waterGlasses > 0 ? "\(waterGlasses)" : "--",
                    label: waterText,
                    color: AppTheme.Colors.accent,
                    isGood: waterGlasses >= 8
                )
                VitalCard(
                    icon: "star.fill",
                    value: moodRating > 0 ? "\(moodRating)/5" : "--",
                    label: moodText,
                    color: AppTheme.Colors.ctaGlow,
                    isGood: moodRating >= 3
                )
            }

            // HealthKit steps row
            if hkSteps > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.success)
                    Text("\(hkSteps) steps today")
                        .font(AppTheme.Typography.small())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    if hkSteps >= 8000 {
                        Text("• Goal reached!")
                            .font(AppTheme.Typography.small())
                            .foregroundColor(AppTheme.Colors.success)
                    } else {
                        Text("• Goal: 8,000")
                            .font(AppTheme.Typography.small())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                .padding(.top, 4)
            }

            // HealthKit sleep row
            if hkSleepHours > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 13))
                        .foregroundColor(hkSleepHours >= 7 ? AppTheme.Colors.accent : AppTheme.Colors.warning)
                    Text(String(format: "%.1fh sleep (Apple Health)", hkSleepHours))
                        .font(AppTheme.Typography.small())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    if hkSleepHours < 6 {
                        Text("• Rest needed!")
                            .font(AppTheme.Typography.small())
                            .foregroundColor(AppTheme.Colors.danger)
                    } else if hkSleepHours >= 7 {
                        Text("• Well rested")
                            .font(AppTheme.Typography.small())
                            .foregroundColor(AppTheme.Colors.success)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

struct VitalCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    let isGood: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
            }
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(value == "--" ? AppTheme.Colors.textSecondary : .white)
            Text(label)
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
            if value != "--" && isGood {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.success)
            } else if value != "--" && !isGood {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.warning)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }
}

// MARK: - HOS / Fatigue Banner
struct HOSFatigueBanner: View {
    let hos: HOSRules
    let onLearnMore: () -> Void
    @State private var currentTipIndex = 0

    private var tips: [(String, String, Color)] {
        let driveH = Int(hos.maxDrivingHours)
        let breakH = Int(hos.mandatoryBreakAfterHours)
        let breakM = hos.mandatoryBreakMinutes
        return [
            ("exclamationmark.triangle.fill",
             "\(hos.regionName): Max \(driveH)h driving per day",
             AppTheme.Colors.warning),
            ("bed.double.fill",
             "\(breakM)-min break required after \(breakH)h behind the wheel",
             AppTheme.Colors.accent),
            ("eye.slash.fill",
             "FATIGUE SIGNS: slow blinking, mental wandering",
             AppTheme.Colors.danger),
            ("moon.fill",
             "20-30min nap restores alertness for up to 2h",
             AppTheme.Colors.accentSoft),
            ("cross.circle.fill",
             "Caffeine doesn't replace sleep. Max 2-3 coffees/day",
             AppTheme.Colors.ctaGlow),
        ]
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(tips[currentTipIndex].2.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: tips[currentTipIndex].0)
                    .font(.system(size: 20))
                    .foregroundColor(tips[currentTipIndex].2)
            }
            Text(tips[currentTipIndex].1)
                .font(AppTheme.Typography.captionBold())
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("HOS", action: onLearnMore)
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppTheme.Colors.accent.opacity(0.1))
                .cornerRadius(AppTheme.Radius.pill)
        }
        .padding(AppTheme.Spacing.md)
        .background(
            LinearGradient(
                colors: [AppTheme.Colors.backgroundCard, AppTheme.Colors.backgroundInput],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .cornerRadius(AppTheme.Radius.md)
        .onTapGesture {
            withAnimation {
                currentTipIndex = (currentTipIndex + 1) % tips.count
            }
        }
    }
}

// MARK: - Wellness Quick Add
struct WellnessQuickAdd: View {
    let onSave: (WellnessCategory, Double) -> Void
    @State private var sleepHours: Double = 7
    @State private var showingSleepPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("QUICK LOG")
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.5)

            HStack(spacing: AppTheme.Spacing.sm) {
                QuickLogButton(icon: "moon.zzz.fill", label: "Sleep 8h", color: AppTheme.Colors.accentSoft) {
                    onSave(.rest, 8)
                }
                QuickLogButton(icon: "figure.walk", label: "Walked", color: AppTheme.Colors.success) {
                    onSave(.exercise, 20)
                }
                QuickLogButton(icon: "drop.fill", label: "+ Water", color: AppTheme.Colors.accent) {
                    onSave(.nutrition, 1)
                }
                QuickLogButton(icon: "checkmark.shield.fill", label: "Check", color: AppTheme.Colors.warning) {
                    onSave(.safety, 1)
                }
            }
        }
    }
}

struct QuickLogButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    @State private var tapped = false

    var body: some View {
        Button(action: {
            action()
            withAnimation(.spring(response: 0.3)) { tapped = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { tapped = false }
            }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(tapped ? AppTheme.Colors.success.opacity(0.2) : color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: tapped ? "checkmark.circle.fill" : icon)
                        .font(.system(size: 20))
                        .foregroundColor(tapped ? AppTheme.Colors.success : color)
                }
                Text(label)
                    .font(AppTheme.Typography.small())
                    .foregroundColor(tapped ? AppTheme.Colors.success : AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tapped ? AppTheme.Colors.success.opacity(0.05) : AppTheme.Colors.backgroundCard)
            .cornerRadius(AppTheme.Radius.md)
        }
    }
}

// MARK: - Medications Card
struct MedicationsCard: View {
    let medications: [Medication]
    let onAddMedication: () -> Void
    let onMedicationTap: (Medication) -> Void
    var medicationsText: String = "Medications"
    var pendingText: String = "pending"
    var addMedicationText: String = "Add medication reminder"

    var pendingCount: Int { medications.filter { !$0.takenToday && $0.isActive }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.cta.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "pill.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.Colors.cta)
                    }
                    Text(medicationsText)
                        .font(AppTheme.Typography.cardTitle())
                        .foregroundColor(.white)
                }
                Spacer()
                if pendingCount > 0 {
                    Text("\(pendingCount) \(pendingText)")
                        .font(AppTheme.Typography.small())
                        .foregroundColor(AppTheme.Colors.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.Colors.warning.opacity(0.1))
                        .cornerRadius(AppTheme.Radius.pill)
                }
                Button(action: onAddMedication) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(AppTheme.Colors.accent)
                        .font(.system(size: 24))
                }
            }

            if medications.isEmpty {
                Button(action: onAddMedication) {
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundColor(AppTheme.Colors.accent)
                        Text(addMedicationText)
                            .font(AppTheme.Typography.body())
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.Colors.accent.opacity(0.06))
                    .cornerRadius(AppTheme.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                            .foregroundColor(AppTheme.Colors.accent.opacity(0.3))
                    )
                }
            } else {
                ForEach(medications) { med in
                    MedicationRow(medication: med, onTap: { onMedicationTap(med) })
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.lg)
    }
}

struct MedicationRow: View {
    let medication: Medication
    let onTap: () -> Void

    private var timeFormatter: DateFormatter {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(medication.takenToday ? AppTheme.Colors.success : AppTheme.Colors.warning)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(medication.name)
                        .font(AppTheme.Typography.bodyBold())
                        .foregroundColor(.white)
                    Text(medication.dosage)
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()
                // Show all reminder times
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(medication.allReminderTimes, id: \.self) { t in
                        Text(timeFormatter.string(from: t))
                            .font(AppTheme.Typography.captionBold())
                            .foregroundColor(medication.takenToday ? AppTheme.Colors.success : AppTheme.Colors.warning)
                    }
                }

                if medication.takenToday {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.Colors.success)
                }
            }
            .padding(10)
            .background(AppTheme.Colors.backgroundInput)
            .cornerRadius(AppTheme.Radius.md)
        }
    }
}

// MARK: - Medication Alert Overlay
struct MedicationAlertOverlay: View {
    let medication: Medication
    let onTaken: () -> Void
    let onSnooze: () -> Void
    @Environment(RegionalSettingsManager.self) private var regionalSettings

    var body: some View {
        let lang = regionalSettings.currentLanguage
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { onSnooze() }

            VStack(spacing: AppTheme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.cta.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: "pill.fill")
                        .font(.system(size: 36))
                        .foregroundColor(AppTheme.Colors.cta)
                }

                VStack(spacing: 8) {
                    Text(lang.medicationTimeLabel)
                        .font(AppTheme.Typography.sectionTitle())
                        .foregroundColor(.white)
                    Text(medication.name)
                        .font(AppTheme.Typography.bodyBold())
                        .foregroundColor(AppTheme.Colors.accent)
                    Text(medication.dosage)
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }

                VStack(spacing: AppTheme.Spacing.sm) {
                    Button(action: onTaken) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(lang.savedLabel)
                        }
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.Colors.success)
                        .cornerRadius(AppTheme.Radius.md)
                    }

                    Button(action: onSnooze) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(lang.remindLaterLabel)
                        }
                        .font(AppTheme.Typography.bodyBold())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.Colors.backgroundInput)
                        .cornerRadius(AppTheme.Radius.md)
                    }
                }
            }
            .padding(AppTheme.Spacing.xl)
            .background(AppTheme.Colors.backgroundSecond)
            .cornerRadius(AppTheme.Radius.xl)
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
    }
}

// MARK: - Today Activity Log
struct TodayActivityLog: View {
    let logs: [WellnessLog]
    @Environment(RegionalSettingsManager.self) private var regionalSettings

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(regionalSettings.currentLanguage.todayActivityLabel)
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.5)

            ForEach(logs.prefix(6)) { log in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(log.category.color.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: log.category.icon)
                            .font(.system(size: 12))
                            .foregroundColor(log.category.color)
                    }
                    Text(log.category.displayName)
                        .font(AppTheme.Typography.captionBold())
                        .foregroundColor(.white)
                    if !log.notes.isEmpty {
                        Text(log.notes)
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(log.date, style: .time)
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }
}

// MARK: - Driver Wellness Tips
struct DriverWellnessTips: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    let tips: [(String, String, Color)] = [
        ("bed.double.fill", "Sleep 7-8h before a long trip", AppTheme.Colors.accentSoft),
        ("drop.fill", "Drink water every 2 hours while driving", AppTheme.Colors.accent),
        ("fork.knife", "Avoid heavy meals before driving", AppTheme.Colors.success),
        ("eye.slash.fill", "Blinking a lot? Stop. Eye fatigue is dangerous.", AppTheme.Colors.warning),
        ("figure.walk", "5min walk at every stop restores focus", AppTheme.Colors.cta),
        ("lungs.fill", "Take 3 deep breaths when feeling road stress", AppTheme.Colors.accentSoft),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text(regionalSettings.currentLanguage.driverTipsLabel)
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.5)

            ForEach(tips, id: \.1) { icon, tip, color in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)
                        .frame(width: 32)
                    Text(tip)
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }
}

// MARK: - Mental Health CTA (diferencial - ninguém faz isso)
struct MentalHealthSupportCard: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#6366f1").opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 22))
                        .foregroundColor(Color(hex: "#6366f1"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Driver Mental Health")
                        .font(AppTheme.Typography.bodyBold())
                        .foregroundColor(.white)
                    Text("Loneliness on the road is real. You are not alone.")
                        .font(AppTheme.Typography.caption())
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            Text("Truck drivers have high rates of stress and depression. Talking about it is strength, not weakness.")
                .font(AppTheme.Typography.caption())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.leading)

            HStack(spacing: AppTheme.Spacing.sm) {
                if let telURL = URL(string: "tel://988") {
                    Link(destination: telURL) {
                        HStack {
                            Image(systemName: "phone.fill")
                            Text("Call 988")
                        }
                        .font(AppTheme.Typography.captionBold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#6366f1"))
                        .cornerRadius(AppTheme.Radius.md)
                    }
                }

                if let smsURL = URL(string: "sms://988") {
                    Link(destination: smsURL) {
                        HStack {
                            Image(systemName: "message.fill")
                            Text("SMS 988")
                        }
                        .font(AppTheme.Typography.captionBold())
                        .foregroundColor(Color(hex: "#6366f1"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#6366f1").opacity(0.1))
                        .cornerRadius(AppTheme.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .stroke(Color(hex: "#6366f1").opacity(0.4), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            LinearGradient(
                colors: [Color(hex: "#6366f1").opacity(0.08), AppTheme.Colors.backgroundCard],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .cornerRadius(AppTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .stroke(Color(hex: "#6366f1").opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - HOS Info Sheet
struct HOSInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let hos: HOSRules

    private var rules: [(String, String, Color)] {
        let driveH   = String(format: "%.0fh", hos.maxDrivingHours)
        let windowH  = String(format: "%.0fh", hos.serviceWindowHours)
        let breakStr = "\(hos.mandatoryBreakMinutes)m after \(Int(hos.mandatoryBreakAfterHours))h"
        let restH    = String(format: "%.0fh", hos.restBetweenShiftsHours)
        let weekly   = hos.extendedWeeklyHours > 0
            ? "\(hos.weeklyHoursLimit)/\(hos.extendedWeeklyHours)h"
            : "\(hos.weeklyHoursLimit)h"
        let reset    = String(format: "%.0fh", hos.weeklyResetHours)
        return [
            (driveH,   "Max driving per day",             AppTheme.Colors.accent),
            (windowH,  "Daily on-duty window",            AppTheme.Colors.warning),
            (breakStr, "Mandatory break",                  AppTheme.Colors.success),
            (restH,    "Rest between shifts",             AppTheme.Colors.accentSoft),
            (weekly,   "Weekly hour limit",               AppTheme.Colors.danger),
            (reset,    "Weekly reset (continuous rest)",  AppTheme.Colors.ctaGlow),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        // Header
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.Colors.warning.opacity(0.15))
                                    .frame(width: 70, height: 70)
                                Image(systemName: "clock.badge.exclamationmark.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppTheme.Colors.warning)
                            }
                            Text("HOS Rules — \(hos.regionName)")
                                .font(AppTheme.Typography.sectionTitle())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            Text(hos.authority)
                                .font(AppTheme.Typography.caption())
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top)
                        .padding(.horizontal)

                        // Rules grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.sm) {
                            ForEach(rules, id: \.0) { value, desc, color in
                                VStack(spacing: 8) {
                                    Text(value)
                                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                                        .foregroundColor(color)
                                        .minimumScaleFactor(0.7)
                                        .lineLimit(1)
                                    Text(desc)
                                        .font(AppTheme.Typography.small())
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(AppTheme.Spacing.md)
                                .background(color.opacity(0.08))
                                .cornerRadius(AppTheme.Radius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                        .stroke(color.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal)

                        // Region-specific notes
                        if !hos.notes.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                                Label("REGIONAL NOTES", systemImage: "info.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppTheme.Colors.accent)
                                    .kerning(0.5)

                                ForEach(hos.notes, id: \.self) { note in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle().fill(AppTheme.Colors.accent).frame(width: 6, height: 6)
                                            .padding(.top, 5)
                                        Text(note)
                                            .font(AppTheme.Typography.caption())
                                            .foregroundColor(AppTheme.Colors.textSecondary)
                                    }
                                }
                            }
                            .padding(AppTheme.Spacing.md)
                            .background(AppTheme.Colors.accent.opacity(0.06))
                            .cornerRadius(AppTheme.Radius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                    .stroke(AppTheme.Colors.accent.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal)
                        }

                        // Fatigue warning
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Label("FATIGUE SIGNS — STOP IMMEDIATELY", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AppTheme.Colors.danger)
                                .kerning(0.5)

                            ForEach([
                                "Frequent blinking or heavy eyelids",
                                "Not remembering the last few miles",
                                "Drifting into another lane",
                                "Difficulty maintaining speed",
                                "Unusual irritability or impatience",
                            ], id: \.self) { sign in
                                HStack(spacing: 8) {
                                    Circle().fill(AppTheme.Colors.danger).frame(width: 6, height: 6)
                                    Text(sign)
                                        .font(AppTheme.Typography.caption())
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                }
                            }
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(AppTheme.Colors.danger.opacity(0.06))
                        .cornerRadius(AppTheme.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .stroke(AppTheme.Colors.danger.opacity(0.25), lineWidth: 1)
                        )
                        .padding(.horizontal)

                        Spacer(minLength: AppTheme.Spacing.xxl)
                    }
                }
            }
            .navigationTitle("HOS Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
    }
}

// MARK: - Add Medication View
struct AddMedicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dosage = ""
    @State private var reminderTimes: [Date] = [Date()]

    private var timeFormatter: DateFormatter {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                Form {
                    Section("Detalhes do Medicamento") {
                        TextField("Nome do medicamento", text: $name)
                            .foregroundColor(.white)
                        TextField("Dosagem (ex: 10mg)", text: $dosage)
                            .foregroundColor(.white)
                    }

                    Section {
                        ForEach(reminderTimes.indices, id: \.self) { idx in
                            HStack {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(AppTheme.Colors.cta)
                                    .frame(width: 24)
                                DatePicker(
                                    "Horario \(idx + 1)",
                                    selection: $reminderTimes[idx],
                                    displayedComponents: .hourAndMinute
                                )
                                .foregroundColor(.white)
                                if reminderTimes.count > 1 {
                                    Button(action: { reminderTimes.remove(at: idx) }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(AppTheme.Colors.danger)
                                    }
                                }
                            }
                        }

                        if reminderTimes.count < 4 {
                            Button(action: { reminderTimes.append(Date()) }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(AppTheme.Colors.accent)
                                    Text("Adicionar horario")
                                        .foregroundColor(AppTheme.Colors.accent)
                                }
                            }
                        }
                    } header: {
                        Text("Horarios de Lembrete (\(reminderTimes.count))")
                    } footer: {
                        Text("Voce pode adicionar ate 4 horarios por medicamento.")
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Adicionar Medicamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.foregroundColor(AppTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        guard !name.isEmpty else { return }
                        let med = Medication(
                            name: name,
                            dosage: dosage.isEmpty ? "Conforme prescrito" : dosage,
                            reminderTimes: reminderTimes
                        )
                        modelContext.insert(med)
                        MedicationNotificationScheduler.reschedule(med)
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.accent)
                    .disabled(name.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

}

// MARK: - Health Profile View
struct HealthProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("healthProfile") private var profileData: Data = Data()

    @State private var conditions: [String] = []
    @State private var allergies: [String] = []
    @State private var dietType = "Standard"
    @State private var newCondition = ""
    @State private var newAllergy = ""

    let dietTypes = ["Standard", "Diabetic", "Low-Sodium", "Vegetarian", "Vegan", "Halal", "Kosher"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                Form {
                    Section("Health Conditions") {
                        ForEach(conditions, id: \.self) { c in
                            Text(c).foregroundColor(.white)
                        }
                        .onDelete { conditions.remove(atOffsets: $0) }
                        HStack {
                            TextField("Add condition", text: $newCondition)
                                .foregroundColor(.white)
                            Button("Add") {
                                if !newCondition.isEmpty {
                                    conditions.append(newCondition)
                                    newCondition = ""
                                }
                            }
                            .foregroundColor(AppTheme.Colors.accent)
                        }
                    }
                    Section("Allergies") {
                        ForEach(allergies, id: \.self) { a in
                            Text(a).foregroundColor(.white)
                        }
                        .onDelete { allergies.remove(atOffsets: $0) }
                        HStack {
                            TextField("Add allergy", text: $newAllergy)
                                .foregroundColor(.white)
                            Button("Add") {
                                if !newAllergy.isEmpty {
                                    allergies.append(newAllergy)
                                    newAllergy = ""
                                }
                            }
                            .foregroundColor(AppTheme.Colors.accent)
                        }
                    }
                    Section("Diet Type") {
                        Picker("Diet", selection: $dietType) {
                            ForEach(dietTypes, id: \.self) { Text($0) }
                        }
                        .foregroundColor(.white)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Health Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(AppTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveProfile(); dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
            .onAppear { loadProfile() }
        }
    }

    private func saveProfile() {
        let profile = HealthProfile(conditions: conditions, allergies: allergies, dietType: dietType)
        if let data = try? JSONEncoder().encode(profile) {
            profileData = data
        }
    }

    private func loadProfile() {
        if let profile = try? JSONDecoder().decode(HealthProfile.self, from: profileData) {
            conditions = profile.conditions
            allergies = profile.allergies
            dietType = profile.dietType
        }
    }
}

// MARK: - WellnessCategory extension
extension WellnessCategory {
    var displayName: String {
        switch self {
        case .rest:      return "Sleep"
        case .exercise:  return "Exercise"
        case .nutrition: return "Nutrition"
        case .mental:    return "Mood"
        case .safety:    return "Safety"
        }
    }

    var icon: String {
        switch self {
        case .rest:      return "moon.zzz.fill"
        case .exercise:  return "figure.walk"
        case .nutrition: return "drop.fill"
        case .mental:    return "star.fill"
        case .safety:    return "checkmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .rest:      return AppTheme.Colors.accentSoft
        case .exercise:  return AppTheme.Colors.success
        case .nutrition: return AppTheme.Colors.accent
        case .mental:    return AppTheme.Colors.ctaGlow
        case .safety:    return AppTheme.Colors.warning
        }
    }
}

#Preview {
    CheckupView()
        .modelContainer(for: [WellnessLog.self, Medication.self], inMemory: true)
        .preferredColorScheme(.dark)
}
