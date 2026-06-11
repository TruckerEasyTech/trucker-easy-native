// HorizonSheets.swift — All sheet content views and banner overlays
// Extracted from ViewsHorizonView.swift for maintainability.

import SwiftUI
import MapKit

// MARK: - Truck Settings Sheet

struct HorizonTruckSettingsSheet: View {
    @Binding var profile: TruckProfile
    @Binding var truckSafeOnlyMode: Bool
    var lang: AppLanguage = .english
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Dimensions") {
                    HStack {
                        Text(lang.truckHeightLabel)
                        Spacer()
                        TextField("4.11", value: $profile.heightMeters, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text(lang.truckWeightLabel)
                        Spacer()
                        TextField("36.29", value: $profile.weightTonnes, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text(lang.truckLengthLabel)
                        Spacer()
                        TextField("22.0", value: $profile.lengthMeters, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Cargo") {
                    Toggle("HAZMAT", isOn: $profile.hasHazmat)
                }
                Section {
                    Toggle(lang.truckSafeOnlyToggleTitle, isOn: $truckSafeOnlyMode)
                } footer: {
                    Text(lang.truckSafeOnlyToggleFooter)
                }
            }
            .navigationTitle("Truck Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Got a Load Sheet

struct HorizonGotALoadSheet: View {
    var lang: AppLanguage = .english
    let onRouteConfirmed: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppTheme.Colors.accent)
                    .padding(.top, 24)
                Text(lang.gotALoadLabel)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text(lang.enterDestinationInstruction)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                TextField("Destination address or city…", text: $address)
                    .foregroundColor(.white)
                    .padding(14)
                    .background(AppTheme.Colors.backgroundInput)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)

                Button(action: {
                    guard !address.isEmpty else { return }
                    onRouteConfirmed(address)
                }) {
                    Text(lang.startTripLabel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.Colors.accent)
                        .cornerRadius(14)
                }
                .disabled(address.isEmpty)
                .padding(.horizontal, 20)

                Spacer()
            }
            .background(AppTheme.Colors.backgroundSecond)
            .navigationTitle("New Load")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Mood Check Sheet

struct HorizonMoodCheckSheet: View {
    var lang: AppLanguage = .english
    let onSubmit: (Int) -> Void
    let onSkip: () -> Void

    @State private var moodRating = 0

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 16)

            HStack(spacing: 10) {
                Image(systemName: "steeringwheel")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.howAreYouFeeling)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Text(lang.tapStarMoodLabel)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()
                Button(action: onSkip) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            WellnessStarRating(rating: $moodRating, onSelect: { onSubmit(moodRating) })
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .background(AppTheme.Colors.backgroundSecond)
    }
}

// MARK: - Global Search Sheet

struct HorizonGlobalSearchSheet: View {
    let locationManager: LocationManager
    let onSelectResult: (CLLocationCoordinate2D, String) -> Void
    let onSelectCategory: (NearbyCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    TextField("Search destination or place…", text: $query)
                        .foregroundColor(.white)
                        .submitLabel(.search)
                        .onSubmit { performSearch() }
                        .onChange(of: query) { _, newValue in
                            searchDebounceTask?.cancel()
                            if newValue.count < 2 { results = []; return }
                            searchDebounceTask = Task {
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                guard !Task.isCancelled else { return }
                                performSearch()
                            }
                        }
                    if isSearching {
                        ProgressView().tint(AppTheme.Colors.accent)
                    } else if !query.isEmpty {
                        Button(action: { query = ""; results = [] }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                }
                .padding(12)
                .background(AppTheme.Colors.backgroundInput)
                .cornerRadius(12)
                .padding(16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(NearbyCategory.allCases, id: \.self) { cat in
                            Button(action: { onSelectCategory(cat) }) {
                                HStack(spacing: 5) {
                                    Image(systemName: cat.icon).font(.system(size: 11))
                                    Text(cat.label).font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(cat.color)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(cat.color.opacity(0.12))
                                .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)

                Divider().background(AppTheme.Colors.textSecondary.opacity(0.2))

                List(results, id: \.self) { item in
                    Button(action: {
                        let coord = item.placemark.coordinate
                        let name = item.name ?? "Destination"
                        onSelectResult(coord, name)
                    }) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name ?? "Unknown")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                let addrParts = [item.placemark.thoroughfare, item.placemark.locality, item.placemark.administrativeArea].compactMap { $0 }
                                if let addr = addrParts.isEmpty ? nil : addrParts.joined(separator: ", ") {
                                    Text(addr)
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if let loc = locationManager.currentLocation {
                                let dist = loc.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude))
                                Text(dist < 1609
                                     ? String(format: "%.0f ft", dist * 3.28084)
                                     : String(format: "%.1f mi", dist / 1609.34))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppTheme.Colors.accent)
                            }
                        }
                    }
                    .listRowBackground(AppTheme.Colors.backgroundCard)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppTheme.Colors.backgroundSecond)
            }
            .background(AppTheme.Colors.backgroundSecond)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func performSearch() {
        guard !query.isEmpty else { return }
        isSearching = true
        Task {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = query
            if let loc = locationManager.currentLocation {
                req.region = MKCoordinateRegion(center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3))
            }
            let items = (try? await MKLocalSearch(request: req).start())?.mapItems ?? []
            await MainActor.run {
                if let loc = locationManager.currentLocation {
                    results = items.sorted { a, b in
                        return loc.distance(from: CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude)) < loc.distance(from: CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude))
                    }.prefix(10).map { $0 }
                } else {
                    results = Array(items.prefix(10))
                }
                isSearching = false
            }
        }
    }
}

// MARK: - Dispatch Load Banner

struct HorizonDispatchLoadBanner: View {
    let load: DispatchedLoad
    var lang: AppLanguage = .english
    let onAccept: () -> Void
    let onDecline: () -> Void

    private var freightFormatted: String? {
        guard let v = load.valorFrete else { return nil }
        return String(format: "$%.2f", v)
    }
    private var eiaFormatted: String? {
        guard let e = load.precoDieselEia else { return nil }
        return String(format: "$%.3f/gal", e)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppTheme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    if let company = load.companyName {
                        Text(company)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                    Text("Load #\(load.loadNumber)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                if let freight = freightFormatted {
                    VStack(spacing: 1) {
                        Text(freight)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AppTheme.Colors.accent)
                        Text("frete")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
            }

            Divider().background(AppTheme.Colors.accent.opacity(0.2))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Text(load.originAddress)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.danger)
                    Text(load.destinationAddress)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 16) {
                if let commodity = load.commodity {
                    Label(commodity, systemImage: "cube.box")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                if let weight = load.weightLbs {
                    Label(String(format: "%.0f lbs", weight), systemImage: "scalemass")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()
                if let eia = eiaFormatted {
                    Label(eia, systemImage: "fuelpump")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            HStack(spacing: 12) {
                Button(action: onDecline) {
                    Text(lang.declineLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.Colors.danger.opacity(0.12))
                        .cornerRadius(10)
                }
                Button(action: onAccept) {
                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                        Text(lang.acceptAndNavigateLabel)
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AppTheme.Colors.accent)
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(AppTheme.Colors.backgroundCard.opacity(0.97))
        .cornerRadius(AppTheme.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).stroke(AppTheme.Colors.accent.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16)
    }
}

// MARK: - Active Load Bar

struct HorizonActiveLoadBar: View {
    let load: DispatchedLoad
    var isPickedUp: Bool = false
    let onFuelReport: () -> Void
    var onMarkPickedUp: (() -> Void)? = nil
    let onMarkDelivered: () -> Void
    /// Quando `nil`, o botão de otimização quântica fica oculto (API não configurada no build).
    var onOptimizeRoute: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: isPickedUp ? "shippingbox.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(isPickedUp ? Color(hex: "#10b981") : Color(hex: "#f59e0b"))
                        Text(isPickedUp ? "Em Rota · #\(load.loadNumber)" : "Buscando · #\(load.loadNumber)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(isPickedUp ? load.destinationAddress : load.originAddress)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onFuelReport) {
                    Image(systemName: "fuelpump.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.Colors.accent)
                        .padding(8)
                        .background(AppTheme.Colors.accent.opacity(0.15))
                        .cornerRadius(8)
                }
                if isPickedUp {
                    Button(action: onMarkDelivered) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Entregue")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#10b981"))
                        .cornerRadius(8)
                    }
                } else {
                    Button(action: { onMarkPickedUp?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 12))
                            Text("Carreguei")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#f59e0b"))
                        .cornerRadius(8)
                    }
                }
            }

            if let onOptimizeRoute {
                Button(action: onOptimizeRoute) {
                    HStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Otimizar Rota")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#6366f1"), Color(hex: "#4f46e5")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .accessibilityLabel("Otimizar rota com motor de otimização")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.Colors.backgroundCard.opacity(0.97))
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(isPickedUp ? Color(hex: "#10b981").opacity(0.3) : Color(hex: "#f59e0b").opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8)
    }
}

// MARK: - Fuel Report Sheet

struct HorizonFuelReportSheet: View {
    let load: DispatchedLoad
    let onSubmit: (Double, Double, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var gallonsText = ""
    @State private var priceText = ""
    @State private var stationName = ""

    private var isValid: Bool {
        Double(gallonsText) != nil && Double(priceText) != nil
    }
    private var savingsText: String? {
        guard let eia = load.precoDieselEia,
              let price = Double(priceText),
              let gallons = Double(gallonsText) else { return nil }
        let savings = (eia - price) * gallons
        let sign = savings >= 0 ? "-" : "+"
        return "\(sign)$\(String(format: "%.2f", abs(savings))) vs EIA avg"
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("Abastecimento · Carga #\(load.loadNumber)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        if let company = load.companyName {
                            Text(company)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.top, 8)

                    if let eia = load.precoDieselEia {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(AppTheme.Colors.accent)
                            Text("EIA Ref: $\(String(format: "%.3f", eia))/gal")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppTheme.Colors.backgroundCard)
                        .cornerRadius(10)
                    }

                    VStack(spacing: 12) {
                        fuelInputField(title: "Galões abastecidos", placeholder: "ex: 120.5", text: $gallonsText, keyboard: .decimalPad)
                        fuelInputField(title: "Preço por galão ($)", placeholder: "ex: 3.799", text: $priceText, keyboard: .decimalPad)
                        fuelInputField(title: "Nome do posto (opcional)", placeholder: "ex: Pilot #422", text: $stationName, keyboard: .default)
                    }

                    if let savings = savingsText {
                        Text(savings)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(savingsText?.hasPrefix("-") == true ? Color.green : AppTheme.Colors.danger)
                    }

                    Spacer()

                    Button(action: {
                        guard let gallons = Double(gallonsText), let price = Double(priceText) else { return }
                        onSubmit(gallons, price, stationName.isEmpty ? nil : stationName)
                        dismiss()
                    }) {
                        Text("Enviar Relatório")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isValid ? AppTheme.Colors.accent : AppTheme.Colors.accent.opacity(0.4))
                            .cornerRadius(12)
                    }
                    .disabled(!isValid)
                }
                .padding(20)
            }
            .navigationTitle("Relatório de Diesel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func fuelInputField(title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(12)
                .background(AppTheme.Colors.backgroundCard)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.Colors.accent.opacity(0.25), lineWidth: 1))
        }
    }
}

// MARK: - Truck Stop Parking Banner

struct HorizonTruckStopParkingBanner: View {
    let stopName: String
    let onSelect: (ParkingAvailability) -> Void
    let onDismiss: () -> Void

    enum ParkingAvailability: String {
        case many = "MANY"
        case some = "SOME"
        case full = "FULL"

        var label: String { rawValue }
        var color: Color {
            switch self {
            case .many: return Color(hex: "#22c55e")
            case .some: return Color(hex: "#f59e0b")
            case .full: return Color(hex: "#ef4444")
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "p.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.Colors.accent)
                Text("How's parking at \(stopName)?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            HStack(spacing: 10) {
                ForEach([ParkingAvailability.many, .some, .full], id: \.rawValue) { status in
                    Button(action: { onSelect(status) }) {
                        HStack(spacing: 6) {
                            Text(status.label)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(status.color)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(status.color.opacity(0.15))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(status.color.opacity(0.4), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#0d1117").opacity(0.96))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}

// MARK: - Truck Stop Review Sheet

struct HorizonTruckStopReviewSheet: View {
    let stop: TruckStopItem
    let onDismiss: () -> Void

    @State private var easyToReach: Int = 0
    @State private var cleanliness: Int = 0
    @State private var restaurants: Int = 0
    @State private var friendlyService: Int = 0
    @State private var price: Int = 0
    @State private var comments: String = ""
    @State private var submitted = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var commentsFocused: Bool

    var canSubmit: Bool {
        easyToReach > 0 && cleanliness > 0 && friendlyService > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Image(systemName: "star.bubble.fill")
                            .font(.system(size: 36))
                            .foregroundColor(AppTheme.Colors.accent)
                        Text("How was \(stop.name)?")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text("Your review helps other truckers")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 4) {
                        HorizonReviewRatingRow(label: "Easy to reach", icon: "arrow.triangle.turn.up.right.diamond.fill", rating: $easyToReach)
                        Divider().background(Color.white.opacity(0.08))
                        HorizonReviewRatingRow(label: "Cleanliness", icon: "sparkles", rating: $cleanliness)
                        Divider().background(Color.white.opacity(0.08))
                        HorizonReviewRatingRow(label: "Restaurants", icon: "fork.knife", rating: $restaurants)
                        Divider().background(Color.white.opacity(0.08))
                        HorizonReviewRatingRow(label: "Friendly service", icon: "hand.thumbsup.fill", rating: $friendlyService)
                        Divider().background(Color.white.opacity(0.08))
                        HorizonReviewRatingRow(label: "Price / Value", icon: "dollarsign.circle.fill", rating: $price)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(14)
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Driver Comments (optional)", systemImage: "text.bubble")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .padding(.horizontal, 16)

                        TextEditor(text: $comments)
                            .focused($commentsFocused)
                            .frame(minHeight: 80)
                            .padding(10)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                            .padding(.horizontal, 16)
                    }

                    VStack(spacing: 10) {
                        Button(action: submitReview) {
                            HStack(spacing: 8) {
                                if isSubmitting { ProgressView().tint(.black) }
                                Text(submitted ? "Submitted!" : "Submit Review")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary.opacity(0.3))
                            .cornerRadius(12)
                        }
                        .disabled(!canSubmit || submitted || isSubmitting)
                        .padding(.horizontal, 16)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.Colors.warning)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }

                        Button("Skip", action: onDismiss)
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .padding(.bottom, 20)
                }
            }
            .background(Color(hex: "#0d1117").ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onDismiss)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private func submitReview() {
        guard SupabaseClient.shared.isAuthenticated,
              let driverId = SupabaseClient.shared.currentDriverId else {
            errorMessage = "Faça login para enviar sua avaliação."
            return
        }
        isSubmitting = true
        errorMessage = nil

        Task {
            let payload = TruckStopReviewPayload(
                poi_place_id: stop.dataSource == .supabase ? stop.id : nil,
                driver_id: driverId,
                location_name: stop.name,
                latitude: stop.coordinate.latitude,
                longitude: stop.coordinate.longitude,
                easy_access_rating: easyToReach > 0 ? easyToReach : nil,
                cleanliness_rating: cleanliness > 0 ? cleanliness : nil,
                restaurants_rating: restaurants > 0 ? restaurants : nil,
                friendly_service_rating: friendlyService > 0 ? friendlyService : nil,
                price_rating: price > 0 ? price : nil,
                overall_rating: max(1.0, min(5.0, overallScore)),
                restaurant_names: [],
                has_healthy_options: nil,
                comments: comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comments.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            do {
                try await SupabaseClient.shared.submitTruckStopReview(payload)
                await MainActor.run {
                    let key = "review_\(stop.name)_\(Date().timeIntervalSince1970)"
                    let data: [String: Any] = [
                        "stop": stop.name, "address": stop.address,
                        "easyToReach": easyToReach, "cleanliness": cleanliness,
                        "restaurants": restaurants, "friendlyService": friendlyService,
                        "price": price, "comments": comments,
                        "date": ISO8601DateFormatter().string(from: Date())
                    ]
                    UserDefaults.standard.set(data, forKey: key)
                    isSubmitting = false
                    submitted = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Não foi possível enviar. Faça login novamente e tente de novo."
                }
                #if DEBUG
                print("[TruckStopReview] Supabase sync failed: \(error.localizedDescription)")
                #endif
                return
            }
            #if DEBUG
            print("[TruckStopReview] Submitted: \(stop.name) — overall \(overallScore)/5")
            #endif
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onDismiss() }
            }
        }
    }

    private var overallScore: Double {
        let filled = [easyToReach, cleanliness, restaurants, friendlyService, price].filter { $0 > 0 }
        guard !filled.isEmpty else { return 0 }
        return Double(filled.reduce(0, +)) / Double(filled.count)
    }
}

// MARK: - Review Rating Row

struct HorizonReviewRatingRow: View {
    let label: String
    let icon: String
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.Colors.accent)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Button(action: { rating = star }) {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 18))
                            .foregroundColor(star <= rating ? Color(hex: "#f59e0b") : AppTheme.Colors.textSecondary.opacity(0.4))
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

// MARK: - AI Chat Panel

struct HorizonAIChatPanel: View {
    @Binding var messages: [(role: String, text: String)]
    @Binding var inputText: String
    @Binding var isStreaming: Bool
    let navigationContext: String
    let onRouteIntent: (String) -> Bool
    let onClose: () -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#c9a84c"))
                Text("Route Easy")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if !messages.isEmpty {
                    Button(action: { messages.removeAll() }) {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(Color.white.opacity(0.1))

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty {
                            VStack(spacing: 8) {
                                Text("Route Easy — compare tolls, fuel, and time. Ask anything about your haul.")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 12)
                                HStack(spacing: 6) {
                                    aiQuickButton("Fewer tolls?")
                                    aiQuickButton("Cheapest fuel?")
                                }
                                HStack(spacing: 6) {
                                    aiQuickButton("Nearest rest area?")
                                    aiQuickButton("HOS rules")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        ForEach(Array(messages.enumerated()), id: \.offset) { idx, msg in
                            HStack(alignment: .top, spacing: 8) {
                                if msg.role == "assistant" {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(hex: "#c9a84c"))
                                        .padding(.top, 4)
                                }
                                Text(msg.text)
                                    .font(.system(size: 13))
                                    .foregroundColor(msg.role == "user" ? .white : AppTheme.Colors.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(msg.role == "user"
                                        ? Color(hex: "#1d6ae5").opacity(0.3)
                                        : Color.white.opacity(0.05))
                                    .cornerRadius(10)
                                    .frame(maxWidth: .infinity, alignment: msg.role == "user" ? .trailing : .leading)
                            }
                            .id(idx)
                        }

                        if isStreaming {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .te_uniformScale(0.7)
                                    .tint(Color(hex: "#c9a84c"))
                                Text("Thinking...")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            .padding(.leading, 8)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            Divider().background(Color.white.opacity(0.1))

            HStack(spacing: 8) {
                TextField("Ask Route Easy...", text: $inputText)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(20)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AppTheme.Colors.textSecondary.opacity(0.4)
                            : Color(hex: "#c9a84c"))
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(hex: "#0d1117"))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#c9a84c").opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
    }

    private func aiQuickButton(_ text: String) -> some View {
        Button(action: {
            inputText = text
            sendMessage()
        }) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "#c9a84c"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: "#c9a84c").opacity(0.1))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "#c9a84c").opacity(0.25), lineWidth: 1)
                )
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""
        messages.append((role: "user", text: text))

        if onRouteIntent(text) {
            messages.append((role: "assistant", text: "Routing command accepted. Calculating route now."))
            return
        }

        isStreaming = true

        var contextStrings: [String] = [
            "[Navigation Context]\n\(navigationContext)"
        ]
        for msg in messages.dropLast() {
            contextStrings.append("\(msg.role == "user" ? "User" : "Assistant"): \(msg.text)")
        }

        Task {
            var fullResponse = ""
            do {
                for try await chunk in AIService.shared.streamResponse(to: text, context: contextStrings) {
                    fullResponse += chunk
                    if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" {
                        messages[lastIdx].text = fullResponse
                    } else {
                        messages.append((role: "assistant", text: fullResponse))
                    }
                }
            } catch {
                if fullResponse.isEmpty {
                    let msg: String
                    if let aiErr = error as? AIError {
                        msg = aiErr.localizedDescription
                    } else {
                        msg = "Connection issue. Try again."
                    }
                    messages.append((role: "assistant", text: msg))
                }
            }
            isStreaming = false
        }
    }
}
