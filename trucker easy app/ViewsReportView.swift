import SwiftUI
import CoreLocation

// MARK: - Report Category

enum ReportCategory: String, CaseIterable, Identifiable {
    case parking      = "Parking Status"
    case weighStation = "Weigh Station"
    case safetyHazard = "Safety Hazard"
    case roadConditions = "Road Conditions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .parking:        return "p.circle.fill"
        case .weighStation:   return "scalemass.fill"
        case .safetyHazard:   return "exclamationmark.triangle.fill"
        case .roadConditions: return "cloud.rain.fill"
        }
    }

    var color: Color {
        switch self {
        case .parking:        return Color(hex: "#6366f1")
        case .weighStation:   return Color(hex: "#ef4444")
        case .safetyHazard:   return Color(hex: "#f59e0b")
        case .roadConditions: return Color(hex: "#0ea5e9")
        }
    }

    var description: String {
        switch self {
        case .parking:        return "Report parking availability at truck stops and rest areas"
        case .weighStation:   return "Report weigh station status: open, closed, or monitoring"
        case .safetyHazard:   return "Report road hazards, debris, accidents, or dangerous conditions"
        case .roadConditions: return "Report weather, road surface conditions, or construction"
        }
    }
}

// MARK: - Parking Status Options

enum ParkingStatus: String, CaseIterable, Identifiable {
    case plenty  = "Plenty of Space"
    case limited = "Limited Spots"
    case full    = "Completely Full"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .plenty:  return "checkmark.circle.fill"
        case .limited: return "exclamationmark.circle.fill"
        case .full:    return "xmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .plenty:  return Color(hex: "#10b981")
        case .limited: return Color(hex: "#f59e0b")
        case .full:    return Color(hex: "#ef4444")
        }
    }
}

// MARK: - Safety Hazard Types

enum HazardType: String, CaseIterable, Identifiable {
    case debris     = "Road Debris"
    case accident   = "Accident"
    case ice        = "Ice / Black Ice"
    case pothole    = "Pothole"
    case construction = "Construction"
    case police     = "Police Activity"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .debris:       return "trash.fill"
        case .accident:     return "car.side.rear.and.car.side.front.and.arrow.right"
        case .ice:          return "snowflake"
        case .pothole:      return "road.lanes"
        case .construction: return "hammer.fill"
        case .police:       return "car.side.fill"
        }
    }
}

// MARK: - Road Condition Types

enum RoadCondition: String, CaseIterable, Identifiable {
    case clear     = "Clear"
    case wet       = "Wet / Rain"
    case snow      = "Snow / Ice"
    case fog       = "Heavy Fog"
    case wind      = "High Winds"
    case flooded   = "Flooding"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .clear:   return "sun.max.fill"
        case .wet:     return "cloud.rain.fill"
        case .snow:    return "snowflake"
        case .fog:     return "cloud.fog.fill"
        case .wind:    return "wind"
        case .flooded: return "water.waves"
        }
    }
    var color: Color {
        switch self {
        case .clear:   return Color(hex: "#f59e0b")
        case .wet:     return Color(hex: "#0ea5e9")
        case .snow:    return Color(hex: "#e2e8f0")
        case .fog:     return Color(hex: "#94a3b8")
        case .wind:    return Color(hex: "#6366f1")
        case .flooded: return Color(hex: "#3b82f6")
        }
    }
}

// MARK: - Report View

struct ReportView: View {
    @State private var locationManager = LocationManager()
    @State private var selectedCategory: ReportCategory? = nil
    @State private var submittedCategory: ReportCategory? = nil
    @State private var showingConfirmation = false

    var body: some View {
        ZStack {
            Color(hex: "#000d1a").ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text("Report")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(.white)
                    Text("Help other drivers by reporting conditions")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 16)

                // ── Location pill ──────────────────────────────────────────
                locationPill
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                // ── Category Grid ─────────────────────────────────────────
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(ReportCategory.allCases) { cat in
                        ReportCategoryCard(category: cat) {
                            withAnimation(.spring(response: 0.35)) {
                                selectedCategory = cat
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startTracking()
        }
        .sheet(item: $selectedCategory) { cat in
            ReportDetailSheet(
                category: cat,
                locationManager: locationManager,
                onSubmit: {
                    submittedCategory = cat
                    selectedCategory = nil
                    withAnimation { showingConfirmation = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { showingConfirmation = false }
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .overlay(alignment: .bottom) {
            if showingConfirmation, let cat = submittedCategory {
                SubmittedBanner(category: cat)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var locationPill: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#00d4c8").opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "location.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#00d4c8"))
            }
            if let loc = locationManager.currentLocation {
                Text(String(format: "Current Location  %.4f, %.4f",
                            loc.coordinate.latitude,
                            loc.coordinate.longitude))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
            } else {
                Text("Acquiring location…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Report Category Card

private struct ReportCategoryCard: View {
    let category: ReportCategory
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(category.color.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: category.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(category.color)
                }
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(category.color.opacity(0.25), lineWidth: 1)
            )
            .te_uniformScale(pressed ? 0.95 : 1)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity,
                            pressing: { pressed = $0 }, perform: {})
    }
}

// MARK: - Report Detail Sheet

struct ReportDetailSheet: View {
    let category: ReportCategory
    let locationManager: LocationManager
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    // Parking
    @State private var selectedParkingStatus: ParkingStatus? = nil
    // Weigh station reuses WeighStationStatus from ViewsWeighStationWeatherShare
    @State private var weighOpen: Bool? = nil
    // Hazard
    @State private var selectedHazard: HazardType? = nil
    // Road
    @State private var selectedRoadCondition: RoadCondition? = nil
    @State private var additionalNote = ""

    var canSubmit: Bool {
        switch category {
        case .parking:        return selectedParkingStatus != nil
        case .weighStation:   return weighOpen != nil
        case .safetyHazard:   return selectedHazard != nil
        case .roadConditions: return selectedRoadCondition != nil
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0d1117").ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Category header
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(category.color.opacity(0.15))
                                    .frame(width: 52, height: 52)
                                Image(systemName: category.icon)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(category.color)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.rawValue)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Text(category.description)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(14)

                        // Options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SELECT STATUS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .kerning(1.2)

                            switch category {
                            case .parking:
                                ForEach(ParkingStatus.allCases) { status in
                                    optionRow(
                                        icon: status.icon,
                                        title: status.rawValue,
                                        subtitle: nil,
                                        color: status.color,
                                        isSelected: selectedParkingStatus == status
                                    ) { selectedParkingStatus = status }
                                }
                            case .weighStation:
                                optionRow(icon: "checkmark.circle.fill", title: "Open", subtitle: "Scale is active — trucks must stop", color: Color(hex: "#ef4444"), isSelected: weighOpen == true) { weighOpen = true }
                                optionRow(icon: "xmark.circle.fill", title: "Closed", subtitle: "Scale is closed — bypass freely", color: Color(hex: "#10b981"), isSelected: weighOpen == false) { weighOpen = false }
                            case .safetyHazard:
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                    ForEach(HazardType.allCases) { hazard in
                                        Button(action: { selectedHazard = hazard }) {
                                            VStack(spacing: 8) {
                                                Image(systemName: hazard.icon)
                                                    .font(.system(size: 22))
                                                    .foregroundColor(selectedHazard == hazard ? .white : Color(hex: "#f59e0b"))
                                                Text(hazard.rawValue)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .multilineTextAlignment(.center)
                                                    .lineLimit(2)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(selectedHazard == hazard ? Color(hex: "#f59e0b") : Color(hex: "#f59e0b").opacity(0.1))
                                            .cornerRadius(12)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#f59e0b").opacity(selectedHazard == hazard ? 0 : 0.25), lineWidth: 1))
                                        }
                                    }
                                }
                            case .roadConditions:
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                    ForEach(RoadCondition.allCases) { cond in
                                        Button(action: { selectedRoadCondition = cond }) {
                                            VStack(spacing: 8) {
                                                Image(systemName: cond.icon)
                                                    .font(.system(size: 22))
                                                    .foregroundColor(selectedRoadCondition == cond ? .white : cond.color)
                                                Text(cond.rawValue)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(selectedRoadCondition == cond ? cond.color : cond.color.opacity(0.1))
                                            .cornerRadius(12)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(cond.color.opacity(selectedRoadCondition == cond ? 0 : 0.25), lineWidth: 1))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(14)

                        // Optional note
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ADD A NOTE (OPTIONAL)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .kerning(1.2)
                            TextField("Any extra details for fellow drivers…", text: $additionalNote)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.white.opacity(0.07))
                                .cornerRadius(10)
                        }

                        // Submit
                        Button(action: {
                            onSubmit()
                            dismiss()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 15))
                                Text("Submit Report")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canSubmit ? Color(hex: "#00d4c8") : Color.white.opacity(0.1))
                            .cornerRadius(14)
                        }
                        .disabled(!canSubmit)
                        .padding(.bottom, 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func optionRow(icon: String, title: String, subtitle: String?, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundColor(isSelected ? .white : color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(color)
                }
            }
            .padding(14)
            .background(isSelected ? color.opacity(0.1) : Color.clear)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? color.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1.5))
        }
    }
}

// MARK: - Submitted Confirmation Banner

private struct SubmittedBanner: View {
    let category: ReportCategory
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundColor(Color(hex: "#10b981"))
            VStack(alignment: .leading, spacing: 2) {
                Text("Report Submitted!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("\(category.rawValue) — visible to nearby drivers")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(14)
        .background(Color(hex: "#0d2a1e"))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#10b981").opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 10)
    }
}
