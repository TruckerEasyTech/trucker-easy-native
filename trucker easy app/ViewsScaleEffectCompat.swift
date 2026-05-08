import SwiftUI

extension View {
    /// Uniform scale without using `View.scaleEffect(_:)` — MapboxMaps adds overloads that
    /// make `scaleEffect` ambiguous when linked into the same target as SwiftUI.
    func te_uniformScale(_ scale: CGFloat) -> some View {
        transformEffect(CGAffineTransform(scaleX: scale, y: scale))
    }

    func te_uniformScale(_ scale: Double) -> some View {
        te_uniformScale(CGFloat(scale))
    }
}
