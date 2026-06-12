// HorizonBottomSheet.swift — Search bar + idle content
// **OPAQUE SOLID background — NO .ultraThinMaterial, NO .opacity() on dark color**
// This is the definitive fix for the "black screen overlay" bug.

import SwiftUI
import MapKit
import Speech
import AVFoundation

struct HorizonBottomSheet: View {
    let locationManager: LocationManager
    let activeTrip: Trip?
    @Binding var isCalculatingRoute: Bool
    var isNavigating: Bool
    var distanceMeters: Double
    var durationSeconds: Double
    @Binding var isExpanded: Bool
    var region: SupportedRegion = .usa
    var lang: AppLanguage = .english
    let onCenterLocation: () -> Void
    let onCalculateRoute: (String) -> Void
    var onCalculateRouteToCoordinate: ((CLLocationCoordinate2D, String) -> Void)? = nil
    let onSelectCategory: (NearbyCategory) -> Void
    var onClearRoute: (() -> Void)? = nil
    @Binding var showingShareTrip: Bool

    @Binding var loadPickupAddress: String
    @Binding var loadDropoffAddress: String
    @Binding var loadCargoOnBoard: Bool
    var isAnalyzingLoadRoute: Bool
    let onAnalyzeLoadRoute: () -> Void
    /// Dentro do painel unificado (toolbar + sheet) — sem cantos/clip duplicados.
    var unifiedChrome: Bool = false
    /// Parser de comando falado: recebe a transcrição final e devolve true se era
    /// "rota para X" / "route to X" e a rota foi iniciada (hands-free).
    var onRouteIntent: ((String) -> Bool)? = nil

    @State private var destination = ""
    @State private var weatherService = WeatherService.shared
    @FocusState private var searchFocused: Bool

    // Live search suggestions
    @State private var searchSuggestions: [MKMapItem] = []
    @State private var isLoadingSuggestions = false
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var showSuggestions = false
    // Últimos destinos roteados — aparecem ao focar a busca com o campo vazio.
    @State private var recentSearches: [HorizonRecentSearch] = []

    // Speech recognition
    @State private var speechRecognizer: SFSpeechRecognizer? = nil
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest? = nil
    @State private var recognitionTask: SFSpeechRecognitionTask? = nil
    @State private var audioEngine: AVAudioEngine? = nil
    @State private var isListening = false
    @State private var isAudioTapInstalled = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Drag handle ──
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isNavigating else { return }
                    isExpanded.toggle()
                }
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            guard !isNavigating else { return }
                            if value.translation.height < -30 {
                                isExpanded = true
                            } else if value.translation.height > 30 {
                                isExpanded = false
                            }
                        }
                )

            // ── Search bar (fixed at top, outside ScrollView) ──
            searchBar
                .padding(.horizontal, 14)
                .padding(.top, 4)

            // ── Live suggestions dropdown ──
            if showSuggestions && (!searchSuggestions.isEmpty || isLoadingSuggestions) {
                suggestionsDropdown
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }

            if isExpanded {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if !isNavigating && isExpanded && false {
                        loadPlanningSection
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                    }

                    if isNavigating || activeTrip != nil {
                        destinationRow
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                    }

                    if isNavigating {
                        actionButtons
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                    }

                    if let weather = weatherService.currentWeather {
                        weatherCard(weather)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }

                    if isNavigating {
                        shareTripRow
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }

                    Spacer(minLength: 20)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            }
        }
        // ━━━ FIX: OPAQUE SOLID background ━━━
        // BEFORE (caused black screen overlay):
        //   .background(Color(hex: "#0d1117").opacity(0.18))
        //   .background(.ultraThinMaterial)
        // NOW: Solid opaque dark — no transparency, no material blur
        .background(unifiedChrome ? Color.clear : GPSDesignSystem.Colors.chromeBackground)
        .clipShape(RoundedRectangle(cornerRadius: unifiedChrome ? 0 : 20, style: .continuous))
        .onChange(of: showSuggestions) { _, showing in
            if showing && !isNavigating { isExpanded = true }
        }
        .onChange(of: searchFocused) { _, focused in
            guard !isNavigating else { return }
            if focused {
                isExpanded = true
                recentSearches = HorizonRecentSearchStore.load()
                if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !recentSearches.isEmpty {
                    showSuggestions = true
                }
            } else {
                isExpanded = false
            }
            // #region agent log
            #if DEBUG
            print("[DBG][SEARCH][H-s1] searchFocused=\(focused) isExpanded=\(isExpanded)")
            #endif
            // #endregion
        }
        .onChange(of: destination) { _, newValue in
            searchDebounceTask?.cancel()
            // #region agent log
            #if DEBUG
            print("[DBG][SEARCH][H-s1] destinationChanged len=\(newValue.count) showSuggestions=\(showSuggestions)")
            #endif
            // #endregion
            if newValue.count < 2 {
                searchSuggestions = []
                // Campo vazio + histórico → mantém o dropdown com os destinos recentes.
                showSuggestions = newValue.isEmpty && searchFocused && !recentSearches.isEmpty
                return
            }
            showSuggestions = true
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await fetchSuggestions(for: newValue)
            }
        }
        .onAppear {
            if speechRecognizer == nil {
                speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
            }
            if audioEngine == nil {
                audioEngine = AVAudioEngine()
            }
            // #region agent log
            #if DEBUG
            print("[DBG][BS][H-ui-5] HorizonBottomSheet onAppear ready speech/audio")
            #endif
            // #endregion
        }
    }

    // MARK: - Load pickup / dropoff (logistics)

    private var loadPlanningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "truck.box.fill")
                    .foregroundColor(Color(hex: "#00d4c8"))
                Text("Coleta e entrega")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("Já coletou")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                Toggle("", isOn: $loadCargoOnBoard)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#00d4c8")))
            }

            TextField("Endereço da coleta (shipper)", text: $loadPickupAddress)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)

            TextField("Endereço da entrega (receiver)", text: $loadDropoffAddress)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)

            Button(action: onAnalyzeLoadRoute) {
                HStack {
                    if isAnalyzingLoadRoute { ProgressView().tint(.white) }
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    Text("Analisar rota da carga")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "#00d4c8"))
                .cornerRadius(12)
            }
            .disabled(isAnalyzingLoadRoute || loadPickupAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || loadDropoffAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(isAnalyzingLoadRoute ? 0.85 : 1)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
            TextField("Set destination for truck routes", text: $destination)
                .foregroundColor(GPSDesignSystem.Colors.textPrimary)
                .font(GPSDesignSystem.Typography.searchPlaceholder())
                .submitLabel(.go)
                .focused($searchFocused)
                .onSubmit {
                    if !destination.isEmpty {
                        // #region agent log
                        #if DEBUG
                        print("[DBG][SEARCH][H-s2] onSubmit destination='\(destination)'")
                        #endif
                        // #endregion
                        submitDestination()
                    }
                }
            if isCalculatingRoute {
                ProgressView().tint(GPSDesignSystem.Colors.primaryAction)
            } else if !destination.isEmpty {
                Button(action: {
                    submitDestination()
                }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(GPSDesignSystem.Colors.primaryAction)
                }
            }
            Button(action: toggleSpeechRecognition) {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isListening ? GPSDesignSystem.Colors.alert : GPSDesignSystem.Colors.textSecondary)
                    .te_uniformScale(isListening ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isListening)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: GPSDesignSystem.Metrics.searchBarHeight)
        .background(GPSDesignSystem.Colors.panelElevated)
        .clipShape(RoundedRectangle(cornerRadius: GPSDesignSystem.Metrics.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GPSDesignSystem.Metrics.cornerMedium, style: .continuous)
                .stroke(isListening ? GPSDesignSystem.Colors.alert.opacity(0.6) : GPSDesignSystem.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Live Suggestions Dropdown

    private var suggestionsDropdown: some View {
        VStack(spacing: 0) {
            if isLoadingSuggestions {
                HStack {
                    ProgressView().tint(AppTheme.Colors.accent)
                    Text(lang.searchingLabel)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            } else {
                // Histórico de destinos — exibido quando ainda não há sugestões digitadas.
                if searchSuggestions.isEmpty {
                    ForEach(recentSearches) { recent in
                        Button(action: { routeToRecent(recent) }) {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                    .frame(width: 20)
                                Text(recent.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                if let loc = locationManager.currentLocation {
                                    let dist = loc.distance(from: CLLocation(latitude: recent.latitude, longitude: recent.longitude))
                                    Text(formatSuggestionDistance(dist))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppTheme.Colors.accent)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        if recent != recentSearches.last {
                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 44)
                        }
                    }
                }
                ForEach(searchSuggestions, id: \.self) { item in
                    Button(action: {
                        let name = item.name ?? destination
                        destination = name
                        showSuggestions = false
                        searchSuggestions = []
                        searchFocused = false
                        // ━━━ FIX: Use coordinate directly (avoids redundant geocoding) ━━━
                        let coord = item.placemark.coordinate
                        HorizonRecentSearchStore.record(name: name, coordinate: coord)
                        if let directRoute = onCalculateRouteToCoordinate {
                            directRoute(coord, name)
                        } else {
                            onCalculateRoute(name)
                        }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.Colors.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                let addrParts = [item.placemark.thoroughfare, item.placemark.locality, item.placemark.administrativeArea].compactMap { $0 }
                                if let addr = addrParts.isEmpty ? nil : addrParts.joined(separator: ", ") {
                                    Text(addr)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if let loc = locationManager.currentLocation {
                                let dist = loc.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude))
                                Text(formatSuggestionDistance(dist))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppTheme.Colors.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    if item != searchSuggestions.last {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .background(Color(hex: "#161b22"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Speech Recognition

    private func toggleSpeechRecognition() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func startListening() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            DispatchQueue.main.async { self.beginRecognition() }
        }
    }

    private func beginRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        }
        if audioEngine == nil {
            audioEngine = AVAudioEngine()
        }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        guard let audioEngine else { return }
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            // #region agent log
            #if DEBUG
            print("[DBG][AUD][H-audio-3] invalid input format channels=\(inputFormat.channelCount) rate=\(Int(inputFormat.sampleRate))")
            #endif
            // #endregion
            return
        }
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let transcript = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.destination = transcript
                    self.showSuggestions = false
                }
                if result.isFinal {
                    self.stopListening()
                    let spoken = transcript
                    DispatchQueue.main.async {
                        // Hands-free: se o motorista disse "rota para X" / "route to X",
                        // inicia a rota automaticamente e limpa o campo de busca.
                        if self.onRouteIntent?(spoken) == true {
                            self.destination = ""
                            self.showSuggestions = false
                            self.searchFocused = false
                        }
                    }
                }
            }
            if error != nil {
                self.stopListening()
            }
        }

        if isAudioTapInstalled {
            inputNode.removeTap(onBus: 0)
            isAudioTapInstalled = false
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            guard self.isListening else { return }
            guard buffer.frameLength > 0 else { return }
            let byteSize = buffer.audioBufferList.pointee.mBuffers.mDataByteSize
            guard byteSize > 0 else {
                // #region agent log
                #if DEBUG
                print("[DBG][AUD][H-audio-1] skip empty AVAudioBuffer byteSize=0")
                #endif
                // #endregion
                return
            }
            self.recognitionRequest?.append(buffer)
        }
        isAudioTapInstalled = true
        // #region agent log
        #if DEBUG
        print("[DBG][AUD][H-audio-3] tap installed sampleRate=\(Int(recordingFormat.sampleRate))")
        #endif
        // #endregion

        audioEngine.prepare()
        try? audioEngine.start()
        isListening = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if self.isListening { self.stopListening() }
        }
    }

    private func stopListening() {
        if let audioEngine {
            audioEngine.stop()
            if isAudioTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                isAudioTapInstalled = false
            }
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isListening = false
    }

    // MARK: - Fetch Live Suggestions

    @MainActor
    private func fetchSuggestions(for text: String) async {
        isLoadingSuggestions = true
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.resultTypes = [.pointOfInterest, .address]
        if let loc = locationManager.currentLocation {
            req.region = MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.40, longitudeDelta: 0.40)
            )
        }
        let items = (try? await MKLocalSearch(request: req).start())?.mapItems ?? []
        let sorted: [MKMapItem]
        if let loc = locationManager.currentLocation {
            sorted = items.sorted { a, b in
                return loc.distance(from: CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude)) < loc.distance(from: CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude))
            }
        } else {
            sorted = items
        }
        searchSuggestions = Array(sorted.prefix(8))
        isLoadingSuggestions = false
    }

    private func formatSuggestionDistance(_ meters: Double) -> String {
        if meters < 1609 {
            return String(format: "%.0f ft", meters * 3.28084)
        }
        return String(format: "%.1f mi", meters / 1609.34)
    }

    private func submitDestination() {
        showSuggestions = false
        searchFocused = false
        destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return }
        // #region agent log
        #if DEBUG
        print("[DBG][SEARCH][H-s2] submitDestination trimmed='\(destination)' suggestions=\(searchSuggestions.count)")
        #endif
        // #endregion

        // Prefer coordinate-based routing from ranked suggestions
        // to avoid global geocoding picking a wrong far-away place.
        if let best = searchSuggestions.first {
            let name = best.name ?? destination
            destination = name
            if let directRoute = onCalculateRouteToCoordinate {
                HorizonRecentSearchStore.record(name: name, coordinate: best.placemark.coordinate)
                directRoute(best.placemark.coordinate, name)
                return
            }
        }
        onCalculateRoute(destination)
    }

    /// Re-roteia para um destino do histórico com um toque.
    private func routeToRecent(_ recent: HorizonRecentSearch) {
        destination = recent.name
        showSuggestions = false
        searchSuggestions = []
        searchFocused = false
        // Re-registra para promover ao topo do histórico.
        HorizonRecentSearchStore.record(name: recent.name, coordinate: recent.coordinate)
        if let directRoute = onCalculateRouteToCoordinate {
            directRoute(recent.coordinate, recent.name)
        } else {
            onCalculateRoute(recent.name)
        }
    }

    // MARK: - Destination / ETA Row

    private var destinationRow: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(activeTrip?.endLocation ?? "Selected Destination")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button(action: {}) {
                    HStack(spacing: 3) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11))
                        Text(lang.itineraryLabel)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#00d4c8"))
                }
            }

            if isNavigating {
                HStack(spacing: 4) {
                    Text(adjustedTruckETA(seconds: durationSeconds, distanceMeters: distanceMeters))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("·")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Text(formatDistance(distanceMeters))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Clear + Go Buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: { onClearRoute?(); destination = "" }) {
                Text(lang.clearTripLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(GPSDesignSystem.Colors.alert)
                    .frame(width: GPSDesignSystem.Metrics.clearTripWidth)
                    .frame(height: GPSDesignSystem.Metrics.actionButtonHeight)
                    .background(GPSDesignSystem.Colors.alertDark)
                    .clipShape(RoundedRectangle(cornerRadius: GPSDesignSystem.Metrics.cornerMedium, style: .continuous))
            }
            Button(action: onCenterLocation) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(lang.goLabel)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(GPSDesignSystem.Colors.chromeBackground)
                .frame(maxWidth: .infinity)
                .frame(height: GPSDesignSystem.Metrics.actionButtonHeight)
                .background(GPSDesignSystem.Colors.primaryAction)
                .clipShape(RoundedRectangle(cornerRadius: GPSDesignSystem.Metrics.cornerMedium, style: .continuous))
            }
        }
    }

    // MARK: - Weather Card

    private func weatherCard(_ weather: TruckWeather) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: weather.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationCityName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(weather.condition)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                Spacer()
                Text(weather.temperatureText)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 0) {
                weatherMetric(icon: "drop.fill", value: weather.precipText, label: "Precip")
                weatherDivider
                weatherMetric(icon: "thermometer.medium", value: "\(Int(weather.temperatureF))°", label: "Temp")
                weatherDivider
                weatherMetric(icon: "wind", value: weather.windText, label: "Wind")
            }
            .padding(.vertical, 10)
        }
        .background(Color.white.opacity(0.07))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var weatherDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 28)
    }

    private func weatherMetric(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
    }

    // MARK: - Share Trip Row

    private var shareTripRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lang.shareTripProgressLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(lang.shareLocationWithDispatcher)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: { showingShareTrip = true }) {
                Text(lang.shareLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color(hex: "#1d6ae5"))
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var locationCityName: String {
        if let loc = locationManager.currentLocation {
            return String(format: "%.2f, %.2f", loc.coordinate.latitude, loc.coordinate.longitude)
        }
        return "Current Location"
    }

    private func formatDistance(_ meters: Double) -> String {
        region.formatDistance(meters)
    }

    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes) min"
    }

    private func adjustedTruckETA(seconds: Double, distanceMeters: Double) -> String {
        let miles = distanceMeters / 1609.34
        let truckHours = miles / 62.0
        return formatTime(truckHours * 3600)
    }
}
