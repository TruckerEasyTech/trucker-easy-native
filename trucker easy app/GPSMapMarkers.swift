//
//  GPSMapMarkers.swift — Fuel + parking markers (SwiftUI port of TEFuelMarkerView / TEParkingMarkerView).
//

import SwiftUI

struct GPSFuelMarkerView: View {
    let price: Double
    var isDeal: Bool = false
    var size: CGFloat = GPSDesignSystem.Metrics.fuelMarkerSize

    var body: some View {
        ZStack {
            Circle()
                .fill(GPSDesignSystem.Colors.fuelMarkerBackground(isDeal: isDeal))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                )

            VStack(spacing: 0) {
                Triangle()
                    .fill(GPSDesignSystem.Colors.alert)
                    .frame(width: 20, height: 10)
                    .overlay(Triangle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))

                Text(String(format: "%.2f", price))
                    .font(GPSDesignSystem.Typography.fuelPrice())
                    .foregroundColor(.white)

                if isDeal {
                    Text("DEAL")
                        .font(GPSDesignSystem.Typography.fuelDeal())
                        .foregroundColor(.white)
                }
            }
            .offset(y: -2)
        }
    }
}

struct GPSParkingMarkerView: View {
    var size: CGFloat = GPSDesignSystem.Metrics.parkingMarkerSize

    var body: some View {
        ZStack {
            Circle()
                .fill(GPSDesignSystem.Colors.primaryAction)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            Text("P")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
