import SwiftUI
import StoreKit

// MARK: - Subscription View (Checkout Page)
// Inspired by Trucker Path - "Built by a driver. For drivers."
struct SubscriptionView: View {
    var highlightPlan: TruckerEasyPlan? = nil

    @State private var selectedPlan: Plan = .annual
    @State private var showingTrial = false
    @State private var showingError = false
    @State private var purchaseSucceeded = false

    @State private var store = StoreKitManager.shared

    enum Plan { case monthly, annual }

    private var selectedProductID: String {
        selectedPlan == .annual ? TruckerEasyProduct.annual : TruckerEasyProduct.monthly
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if AppAccessPolicy.unlockAllFeaturesForTesting {
                        testingModeBanner
                    }
                    if let highlightPlan {
                        routeUpsellBanner(for: highlightPlan)
                    }
                    RouteEasyPlanComparison(highlight: highlightPlan)
                    // MARK: Hero Section
                    ZStack {
                        LinearGradient(
                            colors: [AppTheme.Colors.backgroundInput, AppTheme.Colors.background],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 280)

                        VStack(spacing: AppTheme.Spacing.md) {
                            Image(systemName: "truck.box.fill")
                                .font(.system(size: 56, weight: .bold))
                                .foregroundColor(AppTheme.Colors.accent)
                                .shadow(color: AppTheme.Colors.accent.opacity(0.4), radius: 20)

                            Text("TruckerEasy")
                                .font(.system(size: 38, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)

                            Text("Your Road Companion")
                                .font(AppTheme.Typography.body())
                                .foregroundColor(AppTheme.Colors.accent)

                            HStack(spacing: 6) {
                                Image(systemName: "star.fill").font(.caption).foregroundColor(AppTheme.Colors.ctaGlow)
                                Image(systemName: "star.fill").font(.caption).foregroundColor(AppTheme.Colors.ctaGlow)
                                Image(systemName: "star.fill").font(.caption).foregroundColor(AppTheme.Colors.ctaGlow)
                                Image(systemName: "star.fill").font(.caption).foregroundColor(AppTheme.Colors.ctaGlow)
                                Image(systemName: "star.fill").font(.caption).foregroundColor(AppTheme.Colors.ctaGlow)
                                Text("4.9 • 2,400+ drivers")
                                    .font(AppTheme.Typography.caption())
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                        }
                        .padding(.top, AppTheme.Spacing.xl)
                    }

                    VStack(spacing: AppTheme.Spacing.xl) {
                        // MARK: Feature Showcase
                        FeatureShowcase()

                        // MARK: Pricing Plans
                        VStack(spacing: AppTheme.Spacing.md) {
                            Text("Choose Your Plan")
                                .font(AppTheme.Typography.sectionTitle())
                                .foregroundColor(.white)

                            Text("3 days FREE — cancel anytime")
                                .font(AppTheme.Typography.caption())
                                .foregroundColor(AppTheme.Colors.success)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(AppTheme.Colors.success.opacity(0.1))
                                .cornerRadius(AppTheme.Radius.pill)

                            // Annual Plan (highlighted - best value)
                            PlanCard(
                                name: "Annual",
                                price: store.priceString(for: TruckerEasyProduct.annual),
                                period: "per year",
                                monthlyEquiv: "Only \(annualMonthlyPrice)/month",
                                savings: "Best Value",
                                isSelected: selectedPlan == .annual,
                                isBestValue: true
                            ) {
                                selectedPlan = .annual
                            }

                            // Monthly Plan
                            PlanCard(
                                name: "Monthly",
                                price: store.priceString(for: TruckerEasyProduct.monthly),
                                period: "per month",
                                monthlyEquiv: "Billed monthly",
                                savings: nil,
                                isSelected: selectedPlan == .monthly,
                                isBestValue: false
                            ) {
                                selectedPlan = .monthly
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.md)

                        // MARK: CTA Button (high contrast)
                        VStack(spacing: AppTheme.Spacing.sm) {
                            Button(action: { Task { await startPurchase() } }) {
                                HStack(spacing: 10) {
                                    if store.isPurchasing {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: store.isSubscribed ? "checkmark.seal.fill" : "lock.open.fill")
                                            .font(.system(size: 18, weight: .bold))
                                        Text(store.isSubscribed ? "Subscribed" : "Start 3-Day Free Trial")
                                            .font(.system(size: 18, weight: .heavy))
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    LinearGradient(
                                        colors: store.isSubscribed
                                            ? [AppTheme.Colors.success, AppTheme.Colors.success.opacity(0.8)]
                                            : [AppTheme.Colors.cta, Color(hex: "#E65100")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(AppTheme.Radius.md)
                                .shadow(color: AppTheme.Colors.cta.opacity(0.5), radius: 12, y: 4)
                            }
                            .disabled(store.isPurchasing || store.isSubscribed)
                            .padding(.horizontal, AppTheme.Spacing.md)

                            // Restore purchases link
                            Button(action: { Task { await store.restorePurchases() } }) {
                                Text("Restore Purchases")
                                    .font(AppTheme.Typography.caption())
                                    .foregroundColor(AppTheme.Colors.accent)
                                    .underline()
                            }

                            Text("No charge for 3 days. Cancel before trial ends and pay nothing.")
                                .font(AppTheme.Typography.caption())
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppTheme.Spacing.lg)
                        }

                        // MARK: Trust Badges
                        TrustBadges()
                            .padding(.horizontal, AppTheme.Spacing.md)

                        if AppDistributionConfig.hasPublicDownloadLink,
                           let downloadURL = AppDistributionConfig.publicDownloadURL {
                            Link(destination: downloadURL) {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.down.app.fill")
                                        .font(.system(size: 18, weight: .bold))
                                    Text(
                                        AppDistributionConfig.appStoreURL != nil
                                            ? "Download on the App Store"
                                            : "Join the TestFlight beta"
                                    )
                                    .font(.system(size: 16, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.Colors.accent)
                                .cornerRadius(AppTheme.Radius.md)
                            }
                            .padding(.horizontal, AppTheme.Spacing.md)
                        }

                        // MARK: Driver to Driver Quote
                        DriverToDriverQuote()
                            .padding(.horizontal, AppTheme.Spacing.md)

                        // MARK: FAQ
                        SubscriptionFAQ()
                            .padding(.horizontal, AppTheme.Spacing.md)

                        // Fine print
                        Text("Subscriptions auto-renew. Cancel anytime in Settings → Manage Plan. By subscribing you agree to our Terms of Service.")
                            .font(AppTheme.Typography.small())
                            .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.Spacing.xl)

                        Spacer(minLength: AppTheme.Spacing.xxl)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        // Purchase success confirmation
        .alert("Welcome to TruckerEasy Pro!", isPresented: $purchaseSucceeded) {
            Button("Let's Go!", role: .cancel) {}
        } message: {
            Text("Your 3-day free trial has started. No charge until \(trialEndDate).")
        }
        // Error alert
        .alert("Something went wrong", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "Unknown error. Please try again.")
        }
        .task {
            // Load products when view appears
            if store.products.isEmpty {
                await store.loadProducts()
            }
        }
        .onChange(of: store.errorMessage) { _, newValue in
            showingError = newValue != nil
        }
    }

    private var testingModeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "flask.fill")
                .foregroundColor(AppTheme.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Testing build")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("Premium, Route Easy, AI, and Valhalla truck routing are unlocked.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundCard)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.md)
    }

    private func routeUpsellBanner(for plan: TruckerEasyPlan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: plan >= .premium ? "sparkles" : "dollarsign.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(AppTheme.Colors.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(plan >= .premium ? "Unlock AI Smart Route" : "Unlock No-Toll Truck Routes")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(plan >= .premium
                     ? "Premium compares time, tolls, diesel price, and fuel stops for the most economical run."
                     : "Standard adds Valhalla truck routing that avoids tolls when possible.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(12)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.md)
    }

    // MARK: - Purchase Action
    @MainActor
    private func startPurchase() async {
        guard let product = store.product(for: selectedProductID) else {
            // Products not loaded yet — reload and retry
            await store.loadProducts()
            guard let retried = store.product(for: selectedProductID) else {
                return
            }
            let success = await store.purchase(retried)
            if success { purchaseSucceeded = true }
            return
        }
        let success = await store.purchase(product)
        if success { purchaseSucceeded = true }
    }

    // MARK: - Helpers
    private var trialEndDate: String {
        let date = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Approximate monthly equivalent for the annual plan
    private var annualMonthlyPrice: String {
        if let p = store.annualProduct {
            let monthly = p.price / 12
            let formatted = p.priceFormatStyle.format(monthly)
            return formatted
        }
        return AppDistributionConfig.MarketingPrice.annualPerMonthUSD
    }
}

// MARK: - Route Easy plan comparison (upsell at route start)

private struct RouteEasyPlanComparison: View {
    let highlight: TruckerEasyPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROUTE EASY — 3 OPTIONS")
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.2)

            routeTierRow(
                badge: "FREE",
                title: "Fastest route",
                detail: "Basic driving directions included.",
                color: Color(hex: "#60a5fa"),
                emphasized: highlight == nil || highlight == .free
            )
            routeTierRow(
                badge: "STANDARD",
                title: "No toll route",
                detail: "Truck-safe Valhalla routing that skips tolls when possible.",
                color: Color(hex: "#22c55e"),
                emphasized: highlight == .standard
            )
            routeTierRow(
                badge: "PREMIUM",
                title: "AI Smart route",
                detail: "Optimizes fuel + tolls + time — shows estimated savings before you roll.",
                color: Color(hex: "#f59e0b"),
                emphasized: highlight == .premium
            )
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.md)
    }

    private func routeTierRow(badge: String, title: String, detail: String, color: Color, emphasized: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(badge)
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(emphasized ? .black : color)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(emphasized ? color : color.opacity(0.2))
                .cornerRadius(4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
            if emphasized {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(color)
            }
        }
        .padding(12)
        .background(emphasized ? color.opacity(0.08) : AppTheme.Colors.backgroundCard)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(emphasized ? color.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Feature Showcase
struct FeatureShowcase: View {
    let features: [(icon: String, title: String, desc: String, color: Color)] = [
        ("map.fill", "My Horizon", "Full 3D map with truck routing & Got a Load? smart paste", AppTheme.Colors.accent),
        ("heart.fill", "My Check-up", "5-star mood check, medication alerts & geofencing food tips", AppTheme.Colors.danger),
        ("folder.fill", "My Cabin", "Digital vault for CDL, DOT, insurance with traffic light alerts", AppTheme.Colors.success),
        ("antenna.radiowaves.left.and.right", "Road Talk", "Live trucking news + AI assistant Easy", AppTheme.Colors.ctaGlow),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("EVERYTHING A DRIVER NEEDS")
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.5)
                .padding(.horizontal, AppTheme.Spacing.md)

            ForEach(features, id: \.title) { f in
                HStack(spacing: AppTheme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .fill(f.color.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: f.icon)
                            .font(.system(size: 22))
                            .foregroundColor(f.color)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(f.title)
                            .font(AppTheme.Typography.bodyBold())
                            .foregroundColor(.white)
                        Text(f.desc)
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(f.color)
                        .font(.system(size: 18))
                }
                .padding(AppTheme.Spacing.md)
                .background(AppTheme.Colors.backgroundCard)
                .cornerRadius(AppTheme.Radius.md)
                .padding(.horizontal, AppTheme.Spacing.md)
            }
        }
    }
}

// MARK: - Plan Card
struct PlanCard: View {
    let name: String
    let price: String
    let period: String
    let monthlyEquiv: String
    let savings: String?
    let isSelected: Bool
    let isBestValue: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: AppTheme.Spacing.sm) {
                if isBestValue {
                    Text("BEST VALUE")
                        .font(AppTheme.Typography.small())
                        .foregroundColor(.white)
                        .kerning(1.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(AppTheme.Colors.cta)
                        .cornerRadius(AppTheme.Radius.pill)
                }

                HStack(alignment: .center) {
                    // Selection circle
                    ZStack {
                        Circle()
                            .stroke(isSelected ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary.opacity(0.4), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Circle()
                                .fill(AppTheme.Colors.accent)
                                .frame(width: 12, height: 12)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(AppTheme.Typography.bodyBold())
                            .foregroundColor(.white)
                        Text(monthlyEquiv)
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(isSelected ? AppTheme.Colors.accent : .white)
                        Text(period)
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }

                if let savings = savings {
                    HStack {
                        Spacer()
                        Text(savings)
                            .font(AppTheme.Typography.captionBold())
                            .foregroundColor(AppTheme.Colors.success)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppTheme.Colors.success.opacity(0.1))
                            .cornerRadius(AppTheme.Radius.pill)
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(isSelected ? AppTheme.Colors.accent.opacity(0.08) : AppTheme.Colors.backgroundCard)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(isSelected ? AppTheme.Colors.accent : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Trust Badges
struct TrustBadges: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                TrustBadge(icon: "shield.fill", text: "Secure\nPayment", color: AppTheme.Colors.success)
                TrustBadge(icon: "arrow.counterclockwise", text: "Cancel\nAnytime", color: AppTheme.Colors.accent)
                TrustBadge(icon: "person.fill.checkmark", text: "Driver to\nDriver", color: AppTheme.Colors.cta)
            }
        }
    }
}

struct TrustBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            Text(text)
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
    }
}

// MARK: - Driver to Driver Quote
struct DriverToDriverQuote: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "quote.opening")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.Colors.accent.opacity(0.5))

            Text("TruckerEasy takes care of YOU.\nBuilt by a driver, for drivers.")
                .font(AppTheme.Typography.sectionTitle())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("— Powered by Driver for Driver")
                .font(AppTheme.Typography.caption())
                .foregroundColor(AppTheme.Colors.accent)
                .italic()

            // Stars
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.Colors.ctaGlow)
                }
            }

            Text("\"Finally an app that understands what we go through on the road. The document alerts alone saved me from a $2,400 fine when my Medical Card was expiring.\"")
                .font(AppTheme.Typography.caption())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Text("— Mike R., OTR Driver, 12 years")
                .font(AppTheme.Typography.captionBold())
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.lg)
        .background(
            LinearGradient(
                colors: [AppTheme.Colors.backgroundCard, AppTheme.Colors.backgroundInput],
                startPoint: .top, endPoint: .bottom
            )
        )
        .cornerRadius(AppTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .stroke(AppTheme.Colors.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - FAQ
struct SubscriptionFAQ: View {
    @State private var expandedIndex: Int? = nil

    let items: [(q: String, a: String)] = [
        ("What happens after the free trial?",
         "After 3 days, you'll be charged for your selected plan. Cancel anytime before the trial ends in Settings → Manage Plan."),
        ("Can I switch between monthly and annual?",
         "Yes! You can upgrade from monthly to annual anytime and we'll credit the remaining monthly days."),
        ("Is my data safe and private?",
         "Absolutely. All data is encrypted and stored securely. We never sell your data to third parties."),
        ("Does the app work offline?",
         "Yes! Once a route is started, navigation continues offline. Your documents and logs are always available without internet."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("FREQUENTLY ASKED")
                .font(AppTheme.Typography.small())
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.5)

            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            expandedIndex = expandedIndex == idx ? nil : idx
                        }
                    }) {
                        HStack {
                            Text(item.q)
                                .font(AppTheme.Typography.captionBold())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: expandedIndex == idx ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.accent)
                        }
                        .padding(AppTheme.Spacing.md)
                    }

                    if expandedIndex == idx {
                        Text(item.a)
                            .font(AppTheme.Typography.caption())
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .padding(.horizontal, AppTheme.Spacing.md)
                            .padding(.bottom, AppTheme.Spacing.md)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(AppTheme.Colors.backgroundCard)
                .cornerRadius(AppTheme.Radius.md)
            }
        }
    }
}

#Preview {
    SubscriptionView()
}
