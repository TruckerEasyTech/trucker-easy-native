import Foundation
import SwiftUI

// MARK: - TruckerEasy Design System
// Colors extracted from truckereasy.com
// Theme: Dark Navy + Cyan Accent + Orange CTA
// Fonts: Rajdhani (headings) + Inter (body) via SF Pro equivalents

enum AppTheme {
    // MARK: - Brand Colors  (Matte Gold + Black  — TruckerEasy v3)
    // Primary palette: deep charcoal black + matte gold + warm off-white text
    enum Colors {
        // Backgrounds — true blacks with slight warmth
        static let background        = Color(hex: "#0f0d0b")   // Deep matte black (warm)
        static let backgroundSecond  = Color(hex: "#1a1712")   // Dark brown-black
        static let backgroundCard    = Color(hex: "#201d17")   // Warm dark card
        static let backgroundInput   = Color(hex: "#151210")   // Deepest input bg

        // Accents — matte gold palette
        static let accent            = Color(hex: "#c9a84c")   // Matte gold — primary highlight
        static let accentSoft        = Color(hex: "#e0c070")   // Light matte gold
        static let cta               = Color(hex: "#b8860b")   // Dark goldenrod — CTA
        static let ctaGlow           = Color(hex: "#d4a017")   // Warm gold glow

        // Status (traffic light) — kept vivid for safety readability
        static let success           = Color(hex: "#22c55e")   // Green - OK
        static let warning           = Color(hex: "#f59e0b")   // Amber - expiring soon
        static let danger            = Color(hex: "#ef4444")   // Red - expired/urgent

        // Text — warm off-white for black background
        static let textPrimary       = Color(hex: "#f5f0e8")   // Warm off-white
        static let textSecondary     = Color(hex: "#a09070")   // Muted warm gold-gray
        static let textDim           = Color(hex: "#4a4030")   // Dim warm

        // Map alert colors
        static let alertPolice       = Color(hex: "#4a90d9")   // Steel blue
        static let alertScale        = Color(hex: "#c9a84c")   // Matte gold
        static let alertAccident     = Color(hex: "#ef4444")   // Red

        // Tab bar
        static let tabBarBg          = Color(hex: "#0a0906")   // Deepest warm black
        static let tabActive         = Color(hex: "#c9a84c")   // Matte gold active
        static let tabInactive       = Color(hex: "#6b5a3a")   // Dim gold inactive
    }

    // MARK: - Typography
    enum Typography {
        // Rajdhani-style bold headings (closest SF Pro equivalent)
        static func heroTitle() -> Font { .system(size: 34, weight: .heavy, design: .rounded) }
        static func sectionTitle() -> Font { .system(size: 24, weight: .bold, design: .rounded) }
        static func cardTitle() -> Font { .system(size: 18, weight: .bold, design: .rounded) }
        static func tabLabel() -> Font { .system(size: 10, weight: .semibold, design: .rounded) }

        // Inter-style body text
        static func body() -> Font { .system(size: 16, weight: .regular) }
        static func bodyBold() -> Font { .system(size: 16, weight: .semibold) }
        static func caption() -> Font { .system(size: 13, weight: .regular) }
        static func captionBold() -> Font { .system(size: 13, weight: .semibold) }
        static func small() -> Font { .system(size: 11, weight: .regular) }
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let pill: CGFloat = 100
    }
}

// MARK: - AppConstants (backward compat + new)
enum AppConstants {
    static let appName = "TruckerEasy"
    static let appTagline = "Your Road Companion"
    static let appSlogan = "Built by a driver. For drivers."
    static let version = "2.0.0"

    enum Colors {
        static let primary   = AppTheme.Colors.accent
        static let success   = AppTheme.Colors.success
        static let warning   = AppTheme.Colors.warning
        static let danger    = AppTheme.Colors.danger
        static let secondary = AppTheme.Colors.textSecondary
    }

    enum Defaults {
        static let reminderDaysBefore = 30
        static let defaultMPG = 6.5
        static let quarterMonths = 3
    }

    enum Formatting {
        static let currencySymbol = "$"
        static let distanceUnit = "mi"
        static let fuelUnit = "gal"
        static let dateFormat = "MM/dd/yyyy"
    }

    enum Limits {
        static let maxPhotoSizeMB = 10.0
        static let maxNotesLength = 500
        static let maxDocumentNameLength = 100
    }

    // MARK: - US States
    static let usStates = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]

    static let stateNames: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
        "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
        "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
        "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah",
        "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
        "WI": "Wisconsin", "WY": "Wyoming"
    ]
}

// MARK: - Color from Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Reusable UI Components
struct TECard<Content: View>: View {
    let content: Content
    var padding: CGFloat = AppTheme.Spacing.md

    init(padding: CGFloat = AppTheme.Spacing.md, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(AppTheme.Colors.backgroundCard)
            .cornerRadius(AppTheme.Radius.md)
    }
}

struct TEButton: View {
    let title: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void

    enum ButtonStyle { case primary, cta, ghost, danger }

    init(_ title: String, icon: String? = nil, style: ButtonStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(AppTheme.Typography.bodyBold())
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, AppTheme.Spacing.md)
            .background(backgroundColor)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(borderColor, lineWidth: style == .ghost ? 1.5 : 0)
            )
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return AppTheme.Colors.accent.opacity(0.15)
        case .cta:     return AppTheme.Colors.cta
        case .ghost:   return Color.clear
        case .danger:  return AppTheme.Colors.danger.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return AppTheme.Colors.accent
        case .cta:     return .white
        case .ghost:   return AppTheme.Colors.textSecondary
        case .danger:  return AppTheme.Colors.danger
        }
    }

    private var borderColor: Color {
        switch style {
        case .ghost:   return AppTheme.Colors.textSecondary.opacity(0.4)
        default:       return Color.clear
        }
    }
}

struct TEStatusBadge: View {
    enum Status { case ok, warning, expired }
    let status: Status
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(AppTheme.Typography.captionBold())
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(AppTheme.Radius.pill)
    }

    private var color: Color {
        switch status {
        case .ok:      return AppTheme.Colors.success
        case .warning: return AppTheme.Colors.warning
        case .expired: return AppTheme.Colors.danger
        }
    }
}

// MARK: - Helper Extensions
extension Double {
    var asCurrency: String { String(format: "$%.2f", self) }
    var asDistance: String { String(format: "%.1f mi", self) }
    var asFuel: String { String(format: "%.2f gal", self) }
    var asMPG: String { String(format: "%.2f MPG", self) }
}

extension Date {
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isThisWeek: Bool { Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear) }
    var isThisMonth: Bool { Calendar.current.isDate(self, equalTo: Date(), toGranularity: .month) }
    var isThisYear: Bool { Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year) }

    func quarterDates() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: self)
        let year = calendar.component(.year, from: self)
        let quarterMonth = ((month - 1) / 3) * 3 + 1
        let startComponents = DateComponents(year: year, month: quarterMonth, day: 1)
        let start = calendar.date(from: startComponents)!
        let end = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: start)!
        return (start, end)
    }
}
