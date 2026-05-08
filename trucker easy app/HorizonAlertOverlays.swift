// HorizonAlertOverlays.swift — Safety alert banners
// Grade, curve, wind, speed compliance, dock finder alerts.

import SwiftUI

// MARK: - Speed Compliance Banner

struct SpeedComplianceBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speedometer")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.Colors.warning)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(AppTheme.Colors.warning.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8)
    }
}

// MARK: - Grade Alert Banner

struct GradeAlertBanner: View {
    let message: String
    let isDescending: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isDescending ? "arrow.down.forward.circle.fill" : "arrow.up.forward.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(isDescending ? Color(hex: "#f59e0b") : Color(hex: "#3b82f6"))
            VStack(alignment: .leading, spacing: 2) {
                Text(isDescending ? "STEEP DESCENT" : "STEEP ASCENT")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(isDescending ? Color(hex: "#f59e0b") : Color(hex: "#3b82f6"))
                    .tracking(1)
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke((isDescending ? Color(hex: "#f59e0b") : Color(hex: "#3b82f6")).opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8)
    }
}

// MARK: - Sharp Curve Alert Banner

struct SharpCurveAlertBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "road.lanes.curved.right")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(hex: "#ef4444"))
            VStack(alignment: .leading, spacing: 2) {
                Text("SHARP CURVE AHEAD")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(Color(hex: "#ef4444"))
                    .tracking(1)
                Text("Reduce speed — risk of load shift or rollover")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(Color(hex: "#ef4444").opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8)
    }
}

// MARK: - Wind Alert Banner

struct WindAlertBanner: View {
    let mph: Int
    let isGust: Bool
    let onDismiss: () -> Void

    private var severity: Color { mph >= 45 ? Color(hex: "#ef4444") : Color(hex: "#f59e0b") }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wind")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(severity)
            VStack(alignment: .leading, spacing: 2) {
                Text(isGust ? "WIND GUST \(mph) MPH" : "STRONG WIND \(mph) MPH")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(severity)
                    .tracking(1)
                Text(mph >= 45
                     ? "Extreme wind — consider pulling over safely"
                     : "High wind — reduce speed, grip wheel firmly")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(severity.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8)
    }
}

// MARK: - Dock Finder Panel

struct DockFinderPanel: View {
    let results: [NearbyStopItem]
    let onSelect: (NearbyStopItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "#00d4c8"))
                Text("Truck Entrance / Loading Dock")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(Color.white.opacity(0.08))

            ForEach(results) { item in
                Button(action: { onSelect(item) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.uturn.right.circle")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#00d4c8"))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(item.address)
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(item.distanceText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#00d4c8"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
                if item.id != results.last?.id {
                    Divider().background(Color.white.opacity(0.06)).padding(.leading, 44)
                }
            }
        }
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(Color(hex: "#00d4c8").opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 12)
    }
}

// MARK: - Food Suggestion Banner

struct FoodSuggestionBanner: View {
    let suggestion: FoodSuggestion
    var lang: AppLanguage = .english
    let onNavigate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(AppTheme.Colors.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(suggestion.reason + " · " + suggestion.distanceText)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            Spacer()
            Button(action: onNavigate) {
                Text(lang.goLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AppTheme.Colors.success)
                    .cornerRadius(10)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.md).stroke(AppTheme.Colors.success.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8)
    }
}

// MARK: - Map Alert Pin

struct MapAlertPin: View {
    let alert: MapAlert
    let onConfirm: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button("Confirm (\(alert.confirmations))", action: onConfirm)
            Button("Remove", role: .destructive, action: onDelete)
        } label: {
            ZStack {
                Circle()
                    .fill(alert.type.color.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: alert.type.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(alert.type.color)
            }
        }
    }
}
