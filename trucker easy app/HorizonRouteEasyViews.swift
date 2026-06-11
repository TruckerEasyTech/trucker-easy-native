// HorizonRouteEasyViews.swift — Route Easy picker + plan upsell funnel

import SwiftUI

struct HorizonRouteEasyPickerSheet: View {
    let options: [RouteEasyOption]
    let destinationName: String
    let useMiles: Bool
    let currentPlan: TruckerEasyPlan
    let lang: AppLanguage
    let onSelect: (RouteEasyOption) -> Void
    let onUpgrade: (RouteEasyKind) -> Void
    let onCancel: () -> Void

    @State private var highlightedKind: RouteEasyKind?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if AppAccessPolicy.unlockAllFeaturesForTesting {
                            testingBanner
                        }
                        headerBlock
                        planLegend

                        if options.isEmpty {
                            Text(lang.routeEasyPickerSubtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }

                        ForEach(options) { option in
                            RouteEasyOptionCard(
                                option: option,
                                useMiles: useMiles,
                                isLocked: isLocked(option),
                                isHighlighted: highlightedKind == option.kind,
                                lang: lang,
                                onTap: { handleTierSelection(option.kind, scrollProxy: proxy) }
                            )
                            .id(option.kind)
                        }

                        if !AppAccessPolicy.unlockAllFeaturesForTesting {
                            comparePlansButton
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(hex: "#0a0906"))
            .navigationTitle(lang.routeEasyPickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.cancelLabel, action: onCancel)
                }
            }
            .toolbarBackground(Color(hex: "#141210"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(destinationName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
            Text(AppAccessPolicy.unlockAllFeaturesForTesting
                 ? lang.routeEasyPickerTestingSubtitle
                 : lang.routeEasyPickerSubtitle)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
    }

    private var planLegend: some View {
        HStack(spacing: 8) {
            tierChip(.fastest, label: lang.routeEasyPlanFree, color: Color(hex: "#60a5fa"))
            tierChip(.fewerTolls, label: "Standard", color: Color(hex: "#22c55e"))
            tierChip(.fuelSmart, label: "Premium", color: Color(hex: "#f59e0b"))
        }
    }

    private func tierChip(_ kind: RouteEasyKind, label: String, color: Color) -> some View {
        let unlocked = !isLocked(kind: kind)
        return Button {
            handleTierSelection(kind, scrollProxy: nil)
        } label: {
            planChip(
                label: label,
                color: color,
                active: unlocked,
                selected: highlightedKind == kind
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) route")
        .accessibilityHint(unlocked ? "Start navigation with this plan" : "Upgrade to unlock this plan")
    }

    private func isLocked(_ option: RouteEasyOption) -> Bool {
        isLocked(kind: option.kind)
    }

    private func isLocked(kind: RouteEasyKind) -> Bool {
        !AppAccessPolicy.unlockAllFeaturesForTesting
            && !(options.first(where: { $0.kind == kind })?.isAccessible(for: currentPlan) ?? false)
    }

    private func handleTierSelection(_ kind: RouteEasyKind, scrollProxy: ScrollViewProxy?) {
        highlightedKind = kind
        withAnimation(.easeInOut(duration: 0.2)) {
            scrollProxy?.scrollTo(kind, anchor: .center)
        }
        guard let option = options.first(where: { $0.kind == kind }) else { return }
        if isLocked(option) {
            onUpgrade(kind)
        } else {
            onSelect(option)
        }
    }

    private var testingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "flask.fill")
                .foregroundColor(AppTheme.Colors.accent)
            Text(lang.routeEasyTestingBanner)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.accent.opacity(0.1))
        .cornerRadius(10)
    }

    private func planChip(label: String, color: Color, active: Bool, selected: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(active ? .black : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? color : color.opacity(0.15))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.white : Color.clear, lineWidth: 2)
            )
    }

    private var comparePlansButton: some View {
        Button { onUpgrade(.fuelSmart) } label: {
            HStack {
                Image(systemName: "sparkles")
                Text(lang.routeEasyComparePlans)
                    .font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.Colors.accent.opacity(0.15))
            .foregroundColor(AppTheme.Colors.accent)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.Colors.accent.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

private struct RouteEasyOptionCard: View {
    let option: RouteEasyOption
    let useMiles: Bool
    let isLocked: Bool
    var isHighlighted: Bool = false
    let lang: AppLanguage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                cardContent
                    .opacity(isLocked ? 0.72 : 1)

                if isLocked {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text(lang.routeEasyUnlockPlan(option.requiredPlan.displayName))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text(lang.routeEasyComparePlans)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(accent)
                        if let save = option.estimatedSavingsUSD, save > 1 {
                            Text(lang.routeEasyEstimatedSavings(save))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(accent)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(14)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(accent)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                planBadge
                Text("\(option.durationMinutes) min")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(option.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                if let summary = option.decisionSummary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(3)
                }
            }

            HStack(spacing: 12) {
                metric(icon: "road.lanes", text: distanceText)
                metric(icon: "dollarsign.circle", text: tollText)
                metric(icon: "fuelpump.fill", text: fuelText)
                if option.recommendedStopsCount > 0 {
                    metric(icon: "mappin.and.ellipse", text: "\(option.recommendedStopsCount) stop")
                }
            }

            if !isLocked {
                HStack {
                    Spacer()
                    Text(lang.routeEasyStartNavigation)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(accent)
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(accent)
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#1c1a16"))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isHighlighted ? accent : accent.opacity(isLocked ? 0.2 : 0.35),
                    lineWidth: isHighlighted ? 2.5 : 1
                )
        )
    }

    private var planBadge: some View {
        Text(badgeLabel)
            .font(.system(size: 9, weight: .heavy))
            .foregroundColor(isLocked ? .white.opacity(0.7) : .black)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isLocked ? Color.white.opacity(0.12) : accent.opacity(0.85))
            .cornerRadius(4)
    }

    private var badgeLabel: String {
        switch option.kind {
        case .fastest: return lang.routeEasyPlanFree.uppercased()
        case .fewerTolls: return "STANDARD"
        case .fuelSmart: return "PREMIUM"
        }
    }

    private var title: String {
        switch option.kind {
        case .fastest: return lang.routeEasyKindFastest
        case .fewerTolls: return lang.routeEasyKindNoTolls
        case .fuelSmart: return lang.routeEasyKindSmart
        }
    }

    private var iconName: String {
        switch option.kind {
        case .fastest: return "bolt.fill"
        case .fewerTolls: return "dollarsign.circle.fill"
        case .fuelSmart: return "sparkles"
        }
    }

    private var accent: Color {
        switch option.kind {
        case .fastest: return Color(hex: "#60a5fa")
        case .fewerTolls: return Color(hex: "#22c55e")
        case .fuelSmart: return Color(hex: "#f59e0b")
        }
    }

    private var distanceText: String {
        if useMiles {
            return String(format: "%.0f mi", option.distanceMeters / 1609.34)
        }
        return String(format: "%.0f km", option.distanceMeters / 1000)
    }

    private var tollText: String {
        option.tollUSD > 0.01 ? String(format: "$%.0f toll", option.tollUSD) : "No toll est."
    }

    private var fuelText: String {
        if let s = option.estimatedSavingsUSD, s > 1 {
            return String(format: "~$%.0f save", s)
        }
        if let s = option.fuelSavingsUSD, s > 1 {
            return String(format: "~$%.0f save", s)
        }
        return String(format: "~$%.0f fuel", option.fuelUSD)
    }

    private func metric(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white.opacity(0.85))
    }
}
