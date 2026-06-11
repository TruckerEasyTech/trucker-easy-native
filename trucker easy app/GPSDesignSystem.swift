//
//  GPSDesignSystem.swift
//  Layout + semantic colors for truck GPS chrome (spec → Trucker Easy gold brand).
//

import SwiftUI

/// Pixel/layout metrics from `TruckerEasyGPS_Documentacao_Completa/especificacao_visual_gps.md`,
/// mapped to **AppTheme** colors (matte gold — never raw Trucker Path blue).
enum GPSDesignSystem {

    enum Metrics {
        static let screenHorizontalInset: CGFloat = 8
        static let statusBarHeight: CGFloat = 24
        static let navHeaderHeight: CGFloat = 120
        static let laneGuidanceHeight: CGFloat = 32
        static let toolbarHeight: CGFloat = 48
        static let searchBarHeight: CGFloat = 44
        static let bottomNavHeight: CGFloat = 56
        static let summaryBarHeight: CGFloat = 80
        static let actionButtonHeight: CGFloat = 40
        static let clearTripWidth: CGFloat = 100
        static let fuelMarkerSize: CGFloat = 56
        static let parkingMarkerSize: CGFloat = 40
        static let navArrowSize: CGFloat = 64
        static let pulseRingSize: CGFloat = 88
        static let speedPanelWidth: CGFloat = 80
        static let speedPanelHeight: CGFloat = 60
        static let zoomButtonSize: CGFloat = 30
        static let floatingIconSize: CGFloat = 40
        static let toolbarIconSize: CGFloat = 30
        static let cornerSmall: CGFloat = 4
        static let cornerMedium: CGFloat = 8
        static let cornerLarge: CGFloat = 12
    }

    enum Colors {
        static var chromeBackground: Color { AppTheme.Colors.backgroundInput }
        static var panelBackground: Color { AppTheme.Colors.backgroundCard }
        static var panelElevated: Color { AppTheme.Colors.backgroundSecond }
        static var primaryAction: Color { AppTheme.Colors.accent }
        static var primaryActionSoft: Color { AppTheme.Colors.accentSoft }
        static var routeActive: Color { HorizonRouteColors.routeOrangeSwift }
        static var alert: Color { AppTheme.Colors.danger }
        static var alertDark: Color { Color(hex: "#7f1d1d") }
        static var attention: Color { AppTheme.Colors.warning }
        static var speedCurrent: Color { AppTheme.Colors.accentSoft }
        static var textPrimary: Color { AppTheme.Colors.textPrimary }
        static var textSecondary: Color { AppTheme.Colors.textSecondary }
        static var textMuted: Color { AppTheme.Colors.tabInactive }
        static var border: Color { Color.white.opacity(0.12) }

        static func fuelMarkerBackground(isDeal: Bool) -> Color {
            isDeal ? AppTheme.Colors.success : AppTheme.Colors.backgroundSecond
        }
    }

    enum Typography {
        static func navDistance() -> Font { .system(size: 24, weight: .bold, design: .rounded) }
        static func navStreet() -> Font { .system(size: 10, weight: .regular) }
        static func searchPlaceholder() -> Font { .system(size: 12, weight: .regular) }
        static func toolbarLabel() -> Font { .system(size: 5, weight: .regular) }
        static func fuelPrice() -> Font { .system(size: 16, weight: .bold) }
        static func fuelDeal() -> Font { .system(size: 8, weight: .bold) }
    }
}

// MARK: - Shared chrome styles

struct GPSChromePanel: ViewModifier {
    var cornerRadius: CGFloat = GPSDesignSystem.Metrics.cornerMedium

    func body(content: Content) -> some View {
        content
            .background(GPSDesignSystem.Colors.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(GPSDesignSystem.Colors.border, lineWidth: 0.5)
            )
    }
}

extension View {
    func gpsChromePanel(cornerRadius: CGFloat = GPSDesignSystem.Metrics.cornerMedium) -> some View {
        modifier(GPSChromePanel(cornerRadius: cornerRadius))
    }
}
