//
//  HorizonLaneGuidanceBar.swift — Lane guidance strip (spec Tela 3, gold brand).
//

import SwiftUI

struct HorizonLaneGuidanceBar: View {
    let totalLanes: Int
    let activeLaneMask: [Bool]

    init(totalLanes: Int = 4, activeLaneMask: [Bool]? = nil) {
        let count = max(1, min(totalLanes, 8))
        self.totalLanes = count
        if let mask = activeLaneMask, mask.count == count {
            self.activeLaneMask = mask
        } else {
            self.activeLaneMask = Array(repeating: true, count: count)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<totalLanes, id: \.self) { index in
                laneArrow(isActive: activeLaneMask[index])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: GPSDesignSystem.Metrics.laneGuidanceHeight)
        .background(GPSDesignSystem.Colors.primaryAction.opacity(0.92))
    }

    @ViewBuilder
    private func laneArrow(isActive: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isActive ? .white : GPSDesignSystem.Colors.textMuted)
            Rectangle()
                .fill(isActive ? Color.white : GPSDesignSystem.Colors.textMuted)
                .frame(width: 4, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .frame(maxWidth: .infinity)
    }
}
