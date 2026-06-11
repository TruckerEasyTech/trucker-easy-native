import SwiftUI

// MARK: - Telemedicine Entry Card (shown in CheckupView)

struct TelemedicineCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#00d4c8").opacity(0.2), Color(hex: "#0077b6").opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 48, height: 48)
                    Image(systemName: "stethoscope")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color(hex: "#00d4c8"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Telemedicine")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Talk to a doctor from your truck")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }

                Spacer()

                if TelemedicineService.shared.isConfigured {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                } else {
                    Text("Setup")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#f59e0b"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#f59e0b").opacity(0.12))
                        .cornerRadius(8)
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.backgroundCard)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(Color(hex: "#00d4c8").opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Telemedicine Full View

struct TelemedicineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var symptoms = ""
    @State private var symptomResult: TelemedicineSymptomCheck?
    @State private var isChecking = false
    @State private var doctors: [TelemedicineDoctor] = []
    @State private var appointments: [TelemedicineAppointment] = []
    @State private var isLoadingDoctors = false
    @State private var errorMessage: String?

    private let service = TelemedicineService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                if !service.isConfigured {
                    notConfiguredState
                } else {
                    VStack(spacing: 0) {
                        tabSelector
                        TabView(selection: $selectedTab) {
                            symptomCheckerTab.tag(0)
                            doctorsTab.tag(1)
                            appointmentsTab.tag(2)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
            }
            .navigationTitle("Telemedicine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Not Configured

    private var notConfiguredState: some View {
        VStack(spacing: 20) {
            Image(systemName: "stethoscope")
                .font(.system(size: 56))
                .foregroundColor(Color(hex: "#00d4c8").opacity(0.5))
            Text("Telemedicine Coming Soon")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text("Connect with licensed doctors directly from your truck. Video consultations, prescriptions, and AI symptom checker.")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "video.fill", text: "Video consultations (no clinic needed)")
                featureRow(icon: "pill.fill", text: "Digital prescriptions sent to nearest pharmacy")
                featureRow(icon: "brain.head.profile", text: "AI symptom checker for quick assessment")
                featureRow(icon: "clock.fill", text: "24/7 availability for truckers on the road")
            }
            .padding(.top, 12)
        }
        .padding(AppTheme.Spacing.lg)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#00d4c8"))
                .frame(width: 24)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton("Symptoms", icon: "brain.head.profile", tag: 0)
            tabButton("Doctors", icon: "person.2.fill", tag: 1)
            tabButton("My Visits", icon: "calendar", tag: 2)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, 8)
    }

    private func tabButton(_ title: String, icon: String, tag: Int) -> some View {
        Button(action: { withAnimation(.spring()) { selectedTab = tag } }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(selectedTab == tag ? Color(hex: "#00d4c8") : AppTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedTab == tag ? Color(hex: "#00d4c8").opacity(0.1) : Color.clear)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Symptom Checker Tab

    private var symptomCheckerTab: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How are you feeling?")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Text("Describe your symptoms and our AI will assess urgency and recommend next steps.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $symptoms)
                    .frame(minHeight: 100)
                    .padding(10)
                    .background(AppTheme.Colors.backgroundInput)
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .overlay(
                        Group {
                            if symptoms.isEmpty {
                                Text("e.g. headache for 2 days, neck pain, blurry vision...")
                                    .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }
                        }, alignment: .topLeading
                    )

                Button(action: checkSymptoms) {
                    HStack {
                        if isChecking {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                            Text("Check Symptoms")
                        }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Group {
                            if symptoms.count < 10 {
                                Color.gray.opacity(0.3)
                            } else {
                                LinearGradient(colors: [Color(hex: "#00d4c8"), Color(hex: "#0077b6")],
                                               startPoint: .leading, endPoint: .trailing)
                            }
                        }
                    )
                    .cornerRadius(12)
                }
                .disabled(symptoms.count < 10 || isChecking)

                if let result = symptomResult {
                    symptomResultCard(result)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.danger)
                        .padding(10)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }

    private func symptomResultCard(_ result: TelemedicineSymptomCheck) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                urgencyBadge(result.urgency)
                Spacer()
                if let spec = result.suggestedSpecialty {
                    Text(spec)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#00d4c8"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#00d4c8").opacity(0.1))
                        .cornerRadius(6)
                }
            }

            Text(result.assessment)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Text(result.recommendation)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.Colors.textSecondary)

            if result.urgency == "high" || result.urgency == "emergency" {
                Button(action: { selectedTab = 1 }) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("Find a Doctor Now")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.Colors.danger)
                    .cornerRadius(8)
                }
            }
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(urgencyColor(result.urgency).opacity(0.3), lineWidth: 1)
        )
    }

    private func urgencyBadge(_ urgency: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(urgencyColor(urgency)).frame(width: 8, height: 8)
            Text(urgency.capitalized)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(urgencyColor(urgency))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(urgencyColor(urgency).opacity(0.1))
        .cornerRadius(6)
    }

    private func urgencyColor(_ urgency: String) -> Color {
        switch urgency {
        case "emergency": return Color(hex: "#ef4444")
        case "high":      return Color(hex: "#f59e0b")
        case "medium":    return Color(hex: "#00d4c8")
        default:          return AppTheme.Colors.success
        }
    }

    // MARK: - Doctors Tab

    private var doctorsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                if isLoadingDoctors {
                    ProgressView().tint(Color(hex: "#00d4c8")).padding(.top, 40)
                } else if doctors.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
                        Text("Loading doctors...")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(doctors) { doc in
                        doctorRow(doc)
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
        }
        .onAppear { loadDoctors() }
    }

    private func doctorRow(_ doctor: TelemedicineDoctor) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#00d4c8").opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(String(doctor.name.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "#00d4c8"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(doctor.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(doctor.specialty)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }

            Spacer()

            if let rating = doctor.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#f59e0b"))
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(10)
    }

    // MARK: - Appointments Tab

    private var appointmentsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                if appointments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
                        Text("No appointments yet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Use the symptom checker or browse doctors to book your first teleconsultation.")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(appointments) { apt in
                        appointmentRow(apt)
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
        }
        .onAppear { loadAppointments() }
    }

    private func appointmentRow(_ apt: TelemedicineAppointment) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(apt.doctorName ?? "Doctor")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(apt.date)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
            Text(apt.status.capitalized)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(apt.status == "confirmed" ? AppTheme.Colors.success : Color(hex: "#f59e0b"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((apt.status == "confirmed" ? AppTheme.Colors.success : Color(hex: "#f59e0b")).opacity(0.12))
                .cornerRadius(6)
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(10)
    }

    // MARK: - Actions

    private func checkSymptoms() {
        isChecking = true
        errorMessage = nil
        Task {
            do {
                let result = try await service.checkSymptoms(symptoms)
                await MainActor.run {
                    symptomResult = result
                    isChecking = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isChecking = false
                }
            }
        }
    }

    private func loadDoctors() {
        guard doctors.isEmpty else { return }
        isLoadingDoctors = true
        Task {
            do {
                let docs = try await service.fetchDoctors()
                await MainActor.run {
                    doctors = docs
                    isLoadingDoctors = false
                }
            } catch {
                await MainActor.run { isLoadingDoctors = false }
            }
        }
    }

    private func loadAppointments() {
        Task {
            do {
                let apts = try await service.fetchAppointments()
                await MainActor.run { appointments = apts }
            } catch { }
        }
    }
}

#Preview {
    TelemedicineView()
        .preferredColorScheme(.dark)
}
