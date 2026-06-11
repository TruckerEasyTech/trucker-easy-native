// © 2024–2026 TruckerEasy LLC. All rights reserved.
// Proprietary and confidential. Unauthorized reproduction or distribution
// of this file or any portion thereof is strictly prohibited.

import SwiftUI
import MapKit

// MARK: - Welcome Onboarding View (3-page)

struct WelcomeOnboardingView: View {
    var onGetStarted: () -> Void

    @AppStorage("appLanguageCode") private var appLanguageCode: String = "en"
    @Environment(\.colorScheme) private var colorScheme

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingPrivacy = false
    @State private var showingTerms   = false
    @State private var currentPage    = 0
    @State private var logoScale: CGFloat  = 0.82
    @State private var logoOpacity: Double = 0
    @State private var heroOpacity: Double = 0

    private let brandNavy   = Color(hex: "#0d1b2a")
    private let brandOrange = Color(hex: "#ff6b00")
    private let brandCyan   = Color(hex: "#00d4ff")

    private let features: [(icon: String, title: String, desc: String, color: String)] = [
        ("map.fill",                          "Truck-Safe Navigation",   "Routes optimized for height, weight & hazmat restrictions", "#ff6b00"),
        ("scalemass.fill",                    "Weigh Station Bypass",    "Live alerts & PrePass integration ahead of time",            "#00d4ff"),
        ("heart.fill",                        "Driver Wellness",         "Daily health check-ins & medication reminders",              "#ff4b6e"),
        ("folder.fill",                       "Document Vault",          "CDL, insurance & permits with expiry alerts",                "#c9a84c"),
        ("clock.fill",                        "HOS Tracker",             "DOT hours-of-service for USA, Canada, EU & Brazil",          "#34d399"),
        ("antenna.radiowaves.left.and.right", "Road Community",          "Live road reports, weigh station tips & driver feed",        "#a78bfa"),
    ]

    private let languages: [(flag: String, name: String, code: String)] = [
        ("🇺🇸", "English",         "en"),
        ("🇧🇷", "Português",       "pt"),
        ("🇲🇽", "Español",         "es-la"),
        ("🇷🇺", "Русский",         "ru"),
        ("🇵🇱", "Polski",          "pl"),
        ("🇮🇳", "हिन्दी",           "hi"),
        ("🇸🇦", "العربية",          "ar"),
    ]

    var body: some View {
        ZStack {
            // Globe map — always live in background
            Map(position: $cameraPosition) {}
                .mapStyle(.imagery(elevation: .realistic))
                .ignoresSafeArea()
                .task { startGlobeAnimation() }

            // Base dark layer — prevents green/bright globe from showing through page overlays
            Color.black.opacity(0.55).ignoresSafeArea()

            // Per-page overlay darkness
            pageOverlay

            // Swipeable pages
            TabView(selection: $currentPage) {
                heroPage.tag(0)
                featuresPage.tag(1)
                languagePage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Bottom nav (dots + button)
            VStack {
                Spacer()
                bottomNav
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showingPrivacy) { PrivacyPolicyView() }
        .sheet(isPresented: $showingTerms)   { TermsOfServiceView() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Page 1: Hero

    private var heroPage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Truck icon with layered glow
                ZStack {
                    Circle()
                        .fill(brandOrange.opacity(0.10))
                        .frame(width: 130, height: 130)
                        .blur(radius: 16)
                    Circle()
                        .fill(brandOrange.opacity(0.06))
                        .frame(width: 100, height: 100)
                    Image(systemName: "truck.box.fill")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [brandOrange, Color(hex: "#ff9a00")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: brandOrange.opacity(0.95), radius: 24)
                }
                .te_uniformScale(logoScale)
                .opacity(logoOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.68).delay(0.15)) {
                        logoScale   = 1.0
                        logoOpacity = 1.0
                    }
                }

                // Brand name
                VStack(spacing: 8) {
                    Text("TRUCKER EASY")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(hex: "#cce4ff")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .kerning(3.5)
                        .shadow(color: .black.opacity(0.65), radius: 8)

                    // Decorated divider
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color.clear, brandOrange.opacity(0.7)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1)
                        Image(systemName: "truck.box.fill")
                            .font(.system(size: 10))
                            .foregroundColor(brandOrange.opacity(0.85))
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [brandOrange.opacity(0.7), Color.clear],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1)
                    }
                    .frame(width: 230)

                    Text(localizedSubtitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(brandCyan.opacity(0.9))
                        .kerning(1.3)
                }
                .opacity(heroOpacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.65).delay(0.4)) {
                        heroOpacity = 1.0
                    }
                }

                // Swipe hint
                VStack(spacing: 4) {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Swipe to explore")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                        .kerning(0.5)
                }
                .padding(.top, 8)
                .opacity(heroOpacity)
            }
            .padding(.horizontal, 28)

            Spacer()
            // Bottom spacing for nav
            Spacer().frame(height: 100)
        }
    }

    // MARK: - Page 2: Features

    private var featuresPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer().frame(height: 72)

                // Header
                VStack(spacing: 6) {
                    Text("Everything You Need")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                    Text("on the road")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(brandCyan.opacity(0.85))
                }
                .padding(.bottom, 24)

                // Feature rows
                VStack(spacing: 11) {
                    ForEach(features.indices, id: \.self) { i in
                        OnboardingFeatureRow(
                            icon: features[i].icon,
                            title: features[i].title,
                            desc: features[i].desc,
                            color: Color(hex: features[i].color)
                        )
                    }
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 130)
            }
        }
    }

    // MARK: - Page 3: Language & Get Started

    private var languagePage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                // Header
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(brandCyan.opacity(0.08))
                            .frame(width: 80, height: 80)
                            .blur(radius: 8)
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [brandCyan, brandOrange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: brandCyan.opacity(0.4), radius: 12)
                    }

                    Text(localizedChooseLanguage)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                }

                // Language grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(languages, id: \.code) { lang in
                        Button(action: { appLanguageCode = lang.code }) {
                            HStack(spacing: 8) {
                                Text(lang.flag)
                                    .font(.system(size: 19))
                                Text(lang.name)
                                    .font(.system(size: 13, weight: appLanguageCode == lang.code ? .bold : .medium))
                                    .foregroundColor(appLanguageCode == lang.code ? brandOrange : .white.opacity(0.85))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                                if appLanguageCode == lang.code {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(brandOrange)
                                }
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .background(
                                Group {
                                    if appLanguageCode == lang.code {
                                        brandOrange.opacity(0.13)
                                    } else {
                                        Color.white.opacity(0.04)
                                    }
                                }
                            )
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        appLanguageCode == lang.code ? brandOrange.opacity(0.55) : Color.white.opacity(0.07),
                                        lineWidth: appLanguageCode == lang.code ? 1.5 : 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()
            // Bottom spacing for nav bar
            Spacer().frame(height: 120)
        }
    }

    // MARK: - Bottom Navigation

    private var bottomNav: some View {
        VStack(spacing: 14) {
            // Page dots
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? brandOrange : Color.white.opacity(0.28))
                        .frame(width: i == currentPage ? 24 : 7, height: 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }

            // Primary action button
            if currentPage < 2 {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentPage += 1
                    }
                }) {
                    HStack(spacing: 10) {
                        Text("Next")
                            .font(.system(size: 17, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [brandOrange, Color(hex: "#e65000")],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: brandOrange.opacity(0.55), radius: 16, y: 5)
                }
            } else {
                VStack(spacing: 10) {
                    Button(action: onGetStarted) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text(localizedGetStarted)
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [brandOrange, Color(hex: "#e65000")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: brandOrange.opacity(0.55), radius: 16, y: 5)
                    }

                    // Legal links
                    HStack(spacing: 12) {
                        Button(localizedPrivacyLabel) { showingPrivacy = true }
                        Text("·").foregroundColor(.white.opacity(0.25))
                        Button(localizedTermsLabel) { showingTerms = true }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                }
            }
        }
    }

    // MARK: - Per-page overlay

    @ViewBuilder
    private var pageOverlay: some View {
        switch currentPage {
        case 0:
            // Hero: lighter top so globe shows, heavier bottom for text legibility
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.38), Color.black.opacity(0.0)],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.28)
                )
                LinearGradient(
                    colors: [Color.black.opacity(0.0), brandNavy.opacity(0.93)],
                    startPoint: UnitPoint(x: 0.5, y: 0.32), endPoint: .bottom
                )
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)
        case 1:
            // Features: solid enough to read list
            brandNavy.opacity(0.88)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: currentPage)
        default:
            // Language: moderate — globe slightly visible at top
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.42), Color.black.opacity(0.0)],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)
                )
                LinearGradient(
                    colors: [Color.black.opacity(0.0), brandNavy.opacity(0.97)],
                    startPoint: UnitPoint(x: 0.5, y: 0.22), endPoint: .bottom
                )
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)
        }
    }

    // MARK: - Globe animation

    private func startGlobeAnimation() {
        // Start from high altitude over North America (neutral gray/brown tones)
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 42, longitude: -100),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 140)
        ))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 9.0)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 38, longitude: -96),
                    span: MKCoordinateSpan(latitudeDelta: 55, longitudeDelta: 55)
                ))
            }
        }
    }

    // MARK: - Localized strings

    private var localizedSubtitle: String {
        switch appLanguageCode {
        case "pt":            return "Por caminhoneiros · Para caminhoneiros"
        case "es-la", "es-es": return "Por camioneros · Para camioneros"
        case "ru":            return "От дальнобойщиков · Для дальнобойщиков"
        case "pl":            return "Od kierowców · Dla kierowców"
        case "hi":            return "ट्रक चालकों द्वारा · ट्रक चालकों के लिए"
        case "ar":            return "من السائقين · للسائقين"
        default:              return "By Truckers · For Truckers"
        }
    }
    private var localizedGetStarted: String {
        switch appLanguageCode {
        case "pt":            return "Começar"
        case "es-la", "es-es": return "Empezar"
        case "ru":            return "Начать"
        case "pl":            return "Zaczynamy"
        case "hi":            return "शुरू करें"
        case "ar":            return "ابدأ الآن"
        default:              return "Get Started"
        }
    }
    private var localizedChooseLanguage: String {
        switch appLanguageCode {
        case "pt":            return "Escolha seu idioma"
        case "es-la", "es-es": return "Elige tu idioma"
        case "ru":            return "Выберите язык"
        case "pl":            return "Wybierz język"
        case "hi":            return "भाषा चुनें"
        case "ar":            return "اختر لغتك"
        default:              return "Choose Your Language"
        }
    }
    private var localizedPrivacyLabel: String {
        switch appLanguageCode {
        case "pt":            return "Privacidade"
        case "es-la", "es-es": return "Privacidad"
        case "ru":            return "Конфиденциальность"
        case "pl":            return "Prywatność"
        case "hi":            return "गोपनीयता"
        case "ar":            return "الخصوصية"
        default:              return "Privacy Policy"
        }
    }
    private var localizedTermsLabel: String {
        switch appLanguageCode {
        case "pt":            return "Termos"
        case "es-la", "es-es": return "Términos"
        case "ru":            return "Условия"
        case "pl":            return "Warunki"
        case "hi":            return "शर्तें"
        case "ar":            return "الشروط"
        default:              return "Terms of Service"
        }
    }
}

// MARK: - Feature Row (onboarding)

private struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let desc: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.14))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.03))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Privacy Policy View
// © 2024–2026 TruckerEasy LLC — All rights reserved.

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0d1b2a").ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // Header
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Privacy Policy")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("TruckerEasy LLC · Effective: January 1, 2026")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#a8adbc"))
                        }
                        .padding(.bottom, 4)

                        privacySection("1. Information We Collect",
                        """
                        We collect information you provide directly:
                        • Account information (name, email, preferred language)
                        • Vehicle and load data you enter
                        • Health and wellness data (mood logs, medication reminders)
                        • Documents you upload (CDL, insurance, permits)
                        • Location data (GPS, only while app is active)
                        • Trip, fuel and expense records

                        We do NOT sell your personal data to third parties.
                        """)

                        privacySection("2. How We Use Your Information",
                        """
                        • To provide navigation, HOS tracking and dispatch services
                        • To send local notifications (medication reminders, document expiry)
                        • To improve app functionality and safety features
                        • To comply with legal obligations (e.g., FMCSA, DOT regulations)

                        Your documents and health data are stored locally on your device using Apple's SwiftData framework and are NOT transmitted to our servers without your explicit consent.
                        """)

                        privacySection("3. Data Storage & Security",
                        """
                        • All data is encrypted at rest using iOS device encryption
                        • Documents are stored locally; cloud backup uses Apple iCloud (if enabled by you)
                        • We implement industry-standard security measures to protect your information
                        • We do not have access to data stored solely on your device
                        """)

                        privacySection("4. Third-Party Services",
                        """
                        TruckerEasy uses:
                        • Apple MapKit — for navigation (subject to Apple privacy policies)
                        • Apple HealthKit — for wellness features (opt-in only)
                        • Apple Push Notifications — for dispatch and reminders

                        We do not share your GPS location or personal data with advertisers.
                        """)

                        privacySection("5. Your Rights",
                        """
                        You have the right to:
                        • Access, correct or delete your data at any time from within the app
                        • Opt out of health data collection (Settings → My Check-up)
                        • Disable location services (iOS Settings → Privacy)
                        • Request a copy of your data by contacting support@truckereasy.com
                        """)

                        privacySection("6. Children",
                        """
                        TruckerEasy is designed for professional commercial truck drivers (18+). We do not knowingly collect data from minors.
                        """)

                        privacySection("7. Copyright & Intellectual Property",
                        """
                        © 2024–2026 TruckerEasy LLC. All rights reserved.

                        The TruckerEasy application, its source code, design, graphics, trademarks, trade dress and all content are the exclusive intellectual property of TruckerEasy LLC.

                        Unauthorized copying, reverse engineering, decompiling, disassembling, distribution or creation of derivative works is strictly prohibited and may result in civil and criminal penalties.

                        "TruckerEasy" and the TruckerEasy truck logo are trademarks of TruckerEasy LLC. All third-party trademarks are the property of their respective owners.
                        """)

                        privacySection("8. Contact",
                        """
                        TruckerEasy LLC
                        Email: privacy@truckereasy.com
                        Website: truckereasy.com

                        For DMCA notices or intellectual property concerns:
                        legal@truckereasy.com
                        """)

                        Text("This policy is governed by the laws of the United States. We reserve the right to update this policy; changes will be notified via the app.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#a8adbc"))
                            .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "#ff6b00"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func privacySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "#00d4ff"))
            Text(body)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#d0d8e8"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(hex: "#1e3a5f").opacity(0.5))
        .cornerRadius(10)
    }
}

// MARK: - Terms of Service View

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0d1b2a").ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Terms of Service")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("TruckerEasy LLC · Effective: January 1, 2026")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#a8adbc"))
                        }
                        .padding(.bottom, 4)

                        termsSection("1. Acceptance",
                        """
                        By downloading or using TruckerEasy, you agree to these Terms of Service. If you do not agree, do not use the app.
                        """)

                        termsSection("2. License",
                        """
                        TruckerEasy LLC grants you a limited, non-exclusive, non-transferable, revocable license to use this application for your personal, non-commercial trucking activities.

                        You may NOT:
                        • Copy, modify, distribute or create derivative works of the app
                        • Reverse engineer, decompile or disassemble the app
                        • Use the app for illegal commercial purposes
                        • Share your account credentials
                        • Scrape data, use automated bots or attempt unauthorized access
                        """)

                        termsSection("3. Safety Disclaimer",
                        """
                        TruckerEasy provides navigation assistance and informational tools. YOU are solely responsible for:
                        • Obeying all traffic laws, HOS regulations and DOT requirements
                        • Safe operation of your vehicle at all times
                        • Verifying route information independently
                        """)

                        termsSection("4. Intellectual Property",
                        """
                        © 2024–2026 TruckerEasy LLC. All rights reserved.

                        All content, code, design, graphics and trademarks are the exclusive property of TruckerEasy LLC. Unauthorized use is strictly prohibited.
                        """)

                        termsSection("5. Limitation of Liability",
                        """
                        TruckerEasy LLC is not liable for:
                        • Accidents, fines or losses resulting from following app guidance
                        • Inaccurate navigation or route data
                        • Data loss due to device failure or app errors
                        """)

                        termsSection("6. Contact",
                        """
                        TruckerEasy LLC
                        Email: legal@truckereasy.com
                        Website: truckereasy.com
                        """)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "#ff6b00"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func termsSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "#00d4ff"))
            Text(body)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#d0d8e8"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(hex: "#1e3a5f").opacity(0.5))
        .cornerRadius(10)
    }
}
