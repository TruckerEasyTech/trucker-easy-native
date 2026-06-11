//
//  GPSSpeedPanelView.swift — Limit + current speed (spec Tela 3).
//

import SwiftUI

struct GPSSpeedPanelView: View {
    let speedLimit: String
    let currentSpeed: String
    let unitLabel: String
    var isOverspeeding: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 1) {
                Text(speedLimit)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(GPSDesignSystem.Colors.textPrimary)
                Text("LIMIT")
                    .font(.system(size: 5, weight: .regular))
                    .foregroundColor(GPSDesignSystem.Colors.textSecondary)
            }
            .frame(width: 40)

            Rectangle()
                .fill(GPSDesignSystem.Colors.border)
                .frame(width: 1, height: 28)

            VStack(spacing: 1) {
                Text(currentSpeed)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(isOverspeeding ? GPSDesignSystem.Colors.alert : GPSDesignSystem.Colors.speedCurrent)
                Text(unitLabel)
                    .font(.system(size: 5, weight: .regular))
                    .foregroundColor(GPSDesignSystem.Colors.textSecondary)
            }
            .frame(width: 40)
        }
        .frame(width: 68, height: 48)
        .background(Color(hex: "#0d1117").opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}
