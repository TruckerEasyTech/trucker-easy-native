// © 2024–2025 TruckerEasy. All rights reserved.
// Proprietary and confidential. Unauthorized copying, distribution or modification
// of this file or any portion thereof via any medium is strictly prohibited.
// "TruckerEasy" and the TruckerEasy logo are trademarks of TruckerEasy LLC.

import SwiftUI
import UIKit

// MARK: - Splash Screen View

struct SplashScreenView: View {
    @Binding var isShowing: Bool

    @State private var logoOpacity: Double     = 0
    @State private var logoScale: CGFloat      = 0.82
    @State private var taglineOpacity: Double  = 0
    @State private var taglineOffset: CGFloat  = 18
    @State private var bgOpacity: Double       = 1
    @State private var particleOpacity: Double = 0
    @State private var roadOpacity: Double     = 0
    @State private var dashOffset: CGFloat     = 0
    @State private var truckX: CGFloat         = -220   // starts off-screen left
    @State private var headlightGlow: CGFloat  = 0

    var body: some View {
        ZStack {
            nightSkyGradient
                .ignoresSafeArea()
                .opacity(bgOpacity)

            SplashStarsField()
                .opacity(particleOpacity)

            VStack(spacing: 0) {
                Spacer()

                SideHighwayScene(
                    truckX: truckX,
                    dashOffset: dashOffset,
                    headlightGlow: headlightGlow
                )
                .frame(height: 180)
                .opacity(roadOpacity)

                Spacer().frame(height: 32)

                brandLogo
                    .te_uniformScale(logoScale)
                    .opacity(logoOpacity)

                Spacer()

                VStack(spacing: 8) {
                    ProgressView()
                        .tint(Color(uiColor: UIColor(red: 1, green: 107 / 255, blue: 0, alpha: 0.7)))
                        .te_uniformScale(0.75)
                    Text("truckereasy.com")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                        .kerning(1.5)
                }
                .opacity(taglineOpacity)
                .padding(.bottom, 48)
            }
        }
        .onAppear { runAnimation() }
    }

    // MARK: - Night Sky

    private var nightSkyGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "#020810"),
                Color(hex: "#040d1c"),
                Color(hex: "#060f22"),
                Color(hex: "#0d1b2a")
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Brand Logo

    private var brandLogo: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#ff6b00").opacity(0.08))
                    .frame(width: 100, height: 100)
                Circle()
                    .fill(Color(hex: "#ff6b00").opacity(0.04))
                    .frame(width: 80, height: 80)
                    .blur(radius: 4)
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#ff6b00"), Color(hex: "#ff9a00")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color(hex: "#ff6b00").opacity(0.9), radius: 18)
            }

            Text("TRUCKER EASY")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Color(hex: "#d0e8ff")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .kerning(3.5)
                .shadow(color: Color(hex: "#00d4ff").opacity(0.3), radius: 8)

            HStack(spacing: 8) {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.clear, Color(hex: "#ff6b00").opacity(0.6)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#ff6b00").opacity(0.7))
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "#ff6b00").opacity(0.6), Color.clear],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
            }
            .frame(width: 240)

            Text("By Truckers · For Truckers")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#00d4ff").opacity(0.85))
                .kerning(1.5)
                .offset(y: taglineOffset)
                .opacity(taglineOpacity)
        }
    }

    // MARK: - Animation Sequence

    private func runAnimation() {
        // Phase 1 — sky + stars + road fade in
        withAnimation(.easeIn(duration: 0.3)) {
            roadOpacity     = 1
            particleOpacity = 0.7
        }

        // Phase 2 — road dashes scroll forever
        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
            dashOffset = 84
        }

        // Phase 3 — truck sweeps left to right in ~0.85s
        withAnimation(.easeIn(duration: 0.85).delay(0.1)) {
            truckX = 590
        }

        // Headlight glow activates as truck appears
        withAnimation(.easeIn(duration: 0.2).delay(0.1)) {
            headlightGlow = 1
        }

        // Phase 4 — logo springs in
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.4)) {
            logoOpacity = 1
            logoScale   = 1.0
        }

        // Phase 5 — tagline slides up
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.75)) {
            taglineOpacity = 1
            taglineOffset  = 0
        }

        // Phase 6 — subtle logo pulse while loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 0.35)) {
                logoScale = 1.04
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    logoScale = 1.0
                }
            }
        }

        // Phase 7 — dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) {
            withAnimation(.easeOut(duration: 0.35)) {
                bgOpacity       = 0
                logoOpacity     = 0
                roadOpacity     = 0
                particleOpacity = 0
                taglineOpacity  = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                isShowing = false
            }
        }
    }
}

// MARK: - Side Highway Scene

private struct SideHighwayScene: View {
    let truckX: CGFloat
    let dashOffset: CGFloat
    let headlightGlow: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let roadTop: CGFloat = h * 0.44

            ZStack(alignment: .topLeading) {
                // Sky atmosphere — subtle warm glow at horizon
                LinearGradient(
                    colors: [Color.clear, Color(hex: "#ff6b00").opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                )

                // Road surface
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "#0c1018"), Color(hex: "#080b0f")],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: w, height: h - roadTop)
                    .position(x: w / 2, y: roadTop + (h - roadTop) / 2)

                // Road top edge line
                Rectangle()
                    .fill(Color(hex: "#1e2d40").opacity(0.8))
                    .frame(width: w, height: 1.5)
                    .position(x: w / 2, y: roadTop)

                // Animated center lane dashes
                Canvas { ctx, size in
                    let dashW: CGFloat  = 26
                    let dashH: CGFloat  = 2.5
                    let period: CGFloat = 84
                    let lineY = roadTop + (h - roadTop) * 0.38
                    let offset = dashOffset.truncatingRemainder(dividingBy: period)
                    var x: CGFloat = -period + offset
                    while x < w + period {
                        ctx.fill(
                            Path(CGRect(x: x, y: lineY - dashH / 2, width: dashW, height: dashH)),
                            with: .color(Color(hex: "#ffe082").opacity(0.40))
                        )
                        x += period
                    }
                }

                // Headlight beam cone (projects forward/right of truck)
                Canvas { ctx, size in
                    let hx = truckX + 100.0
                    let hy = roadTop + (h - roadTop) * 0.26
                    let alpha = Double(0.07 * headlightGlow)

                    // Main upper beam
                    var cone = Path()
                    cone.move(to: CGPoint(x: hx, y: hy))
                    cone.addLine(to: CGPoint(x: w + 60, y: hy - 45))
                    cone.addLine(to: CGPoint(x: w + 60, y: hy + 55))
                    cone.closeSubpath()
                    ctx.fill(cone, with: .color(Color(hex: "#ffe082").opacity(alpha)))

                    // Road illumination (lower cone on road surface)
                    var ground = Path()
                    ground.move(to: CGPoint(x: hx, y: hy + 14))
                    ground.addLine(to: CGPoint(x: w + 60, y: roadTop + (h - roadTop) * 0.85))
                    ground.addLine(to: CGPoint(x: hx + 50, y: roadTop + (h - roadTop) * 0.85))
                    ground.closeSubpath()
                    ctx.fill(ground, with: .color(Color(hex: "#ffe082").opacity(alpha * 0.35)))
                }
                .blur(radius: 16)
                .blendMode(.plusLighter)

                // Speed lines behind the truck (motion blur effect)
                Canvas { ctx, size in
                    let rearX = truckX - 150.0
                    let baseY = roadTop + (h - roadTop) * 0.28
                    let lines: [(dy: CGFloat, len: CGFloat, alpha: Double, thick: CGFloat)] = [
                        (-14, 100, 0.14, 1.0),
                        (-7,  140, 0.09, 0.8),
                        (0,   120, 0.12, 1.0),
                        (9,   90,  0.10, 0.8),
                        (17,  110, 0.08, 1.0),
                        (-20, 70,  0.07, 0.6),
                        (5,   160, 0.06, 0.6),
                    ]
                    for ln in lines {
                        var line = Path()
                        line.move(to: CGPoint(x: rearX, y: baseY + ln.dy))
                        line.addLine(to: CGPoint(x: rearX - ln.len, y: baseY + ln.dy))
                        ctx.stroke(line,
                                   with: .color(Color(hex: "#90b8d8").opacity(ln.alpha)),
                                   lineWidth: ln.thick)
                    }
                }

                // Truck silhouette
                SideViewTruck()
                    .frame(width: 300, height: (h - roadTop) * 0.84)
                    .position(x: truckX, y: roadTop + (h - roadTop) * 0.40)

                // Ground shadow under truck
                Ellipse()
                    .fill(Color.black.opacity(0.30))
                    .frame(width: 270, height: 7)
                    .blur(radius: 4)
                    .position(x: truckX, y: h - 5)

                // Ambient road glow from headlights
                RadialGradient(
                    colors: [
                        Color(hex: "#ffe082").opacity(Double(0.13 * headlightGlow)),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 55
                )
                .frame(width: 110, height: 36)
                .blur(radius: 6)
                .position(x: truckX + 130, y: roadTop + (h - roadTop) * 0.72)
            }
            .clipped()
        }
    }
}

// MARK: - Side View Truck (Canvas drawing, faces RIGHT)

private struct SideViewTruck: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // Core measurements
            let wheelR:   CGFloat = h * 0.19
            let groundY:  CGFloat = h
            let floorY:   CGFloat = groundY - wheelR * 1.85

            // Trailer (left portion = rear)
            let trailerW: CGFloat = w * 0.655
            let trailerH: CGFloat = h * 0.50
            let trailerX: CGFloat = 0
            let trailerY: CGFloat = floorY - trailerH

            // Cab (right portion = front, faces right)
            let cabW:     CGFloat = w * 0.215
            let cabH:     CGFloat = h * 0.70
            let cabX:     CGFloat = trailerW - 5  // slight overlap for seamless join
            let cabY:     CGFloat = floorY - cabH

            // ── Trailer body ─────────────────────────────────────────────
            let trailerRect = CGRect(x: trailerX, y: trailerY, width: trailerW, height: trailerH)
            ctx.fill(
                Path(roundedRect: trailerRect, cornerRadius: 3),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: "#1e2f40"), location: 0),
                        .init(color: Color(hex: "#0d1920"), location: 1)
                    ]),
                    startPoint: CGPoint(x: 0, y: trailerY),
                    endPoint: CGPoint(x: 0, y: trailerY + trailerH)
                )
            )
            ctx.stroke(
                Path(roundedRect: trailerRect, cornerRadius: 3),
                with: .color(Color(hex: "#2e4a60").opacity(0.65)),
                lineWidth: 1
            )

            // Trailer horizontal panel lines
            for i in 1...2 {
                let ly = trailerY + trailerH * CGFloat(i) / 3.0
                var line = Path()
                line.move(to: CGPoint(x: trailerX + 8, y: ly))
                line.addLine(to: CGPoint(x: trailerX + trailerW - 6, y: ly))
                ctx.stroke(line, with: .color(Color(hex: "#2e4a60").opacity(0.22)), lineWidth: 0.5)
            }

            // Running lights (amber dots on top edge of trailer)
            for i in 0..<5 {
                let lx = trailerX + 14 + (trailerW - 28) * CGFloat(i) / 4.0
                ctx.fill(
                    Path(roundedRect: CGRect(x: lx - 3, y: trailerY + 3, width: 6, height: 4), cornerRadius: 2),
                    with: .color(Color(hex: "#ffb300").opacity(0.95))
                )
            }

            // Tail lights — upper (rear left face)
            ctx.fill(
                Path(CGRect(x: trailerX, y: trailerY + 8, width: 5, height: 10)),
                with: .color(Color(hex: "#ff2020").opacity(0.95))
            )
            ctx.fill(
                Path(CGRect(x: trailerX - 1, y: trailerY + 7, width: 7, height: 12)),
                with: .color(Color(hex: "#ff5050").opacity(0.28))
            )
            // Tail lights — lower
            ctx.fill(
                Path(CGRect(x: trailerX, y: trailerY + trailerH - 19, width: 5, height: 10)),
                with: .color(Color(hex: "#ff2020").opacity(0.95))
            )
            ctx.fill(
                Path(CGRect(x: trailerX - 1, y: trailerY + trailerH - 20, width: 7, height: 12)),
                with: .color(Color(hex: "#ff5050").opacity(0.28))
            )

            // Amber reflector strip at rear bottom
            ctx.fill(
                Path(CGRect(x: trailerX, y: trailerY + trailerH - 5, width: 22, height: 3)),
                with: .color(Color(hex: "#ffb300").opacity(0.60))
            )

            // ── Cab body ─────────────────────────────────────────────────
            let cabRect = CGRect(x: cabX, y: cabY, width: cabW, height: cabH)
            ctx.fill(
                Path(roundedRect: cabRect, cornerRadius: 5),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: "#14253a"), location: 0),
                        .init(color: Color(hex: "#0a1825"), location: 1)
                    ]),
                    startPoint: CGPoint(x: cabX, y: cabY),
                    endPoint: CGPoint(x: cabX, y: cabY + cabH)
                )
            )
            ctx.stroke(
                Path(roundedRect: cabRect, cornerRadius: 5),
                with: .color(Color(hex: "#2e4a60").opacity(0.80)),
                lineWidth: 1.2
            )

            // Windshield (angled front face of cab)
            var ws = Path()
            ws.move(to:    CGPoint(x: cabX + cabW * 0.36, y: cabY + 4))
            ws.addLine(to: CGPoint(x: cabX + cabW - 4,    y: cabY + 2))
            ws.addLine(to: CGPoint(x: cabX + cabW - 3,    y: cabY + cabH * 0.45))
            ws.addLine(to: CGPoint(x: cabX + cabW * 0.32, y: cabY + cabH * 0.50))
            ws.closeSubpath()
            ctx.fill(ws, with: .color(Color(hex: "#00d4ff").opacity(0.10)))
            ctx.stroke(ws, with: .color(Color(hex: "#00d4ff").opacity(0.18)), lineWidth: 0.5)

            // Side window
            let swRect = CGRect(x: cabX + 4, y: cabY + 5,
                                width: cabW * 0.34, height: cabH * 0.30)
            ctx.fill(
                Path(roundedRect: swRect, cornerRadius: 2),
                with: .color(Color(hex: "#00d4ff").opacity(0.07))
            )
            ctx.stroke(
                Path(roundedRect: swRect, cornerRadius: 2),
                with: .color(Color(hex: "#00d4ff").opacity(0.15)),
                lineWidth: 0.5
            )

            // Headlight (right/front face of cab)
            let hlX = cabX + cabW - 8
            let hlY = cabY + cabH * 0.56
            ctx.fill(
                Path(roundedRect: CGRect(x: hlX, y: hlY, width: 8, height: 5), cornerRadius: 2),
                with: .color(Color(hex: "#ffe082"))
            )
            // Headlight halo glow
            ctx.fill(
                Path(roundedRect: CGRect(x: hlX - 3, y: hlY - 3, width: 14, height: 11), cornerRadius: 4),
                with: .color(Color(hex: "#ffe082").opacity(0.22))
            )
            // DRL strip above headlight
            ctx.fill(
                Path(CGRect(x: hlX - 5, y: hlY - 5, width: 13, height: 2)),
                with: .color(Color(hex: "#ffffff").opacity(0.38))
            )

            // Grill slats (front bottom of cab)
            for gi in 0..<3 {
                let gy = cabY + cabH * 0.72 + CGFloat(gi) * 4
                ctx.fill(
                    Path(CGRect(x: cabX + cabW - 8, y: gy, width: 7, height: 2)),
                    with: .color(Color(hex: "#2e4a60").opacity(0.45))
                )
            }

            // Exhaust stacks (vertical, above/behind cab)
            for si in 0..<2 {
                let sx = cabX + 10 + CGFloat(si) * 9
                let stackRect = CGRect(x: sx, y: cabY - 13, width: 5, height: 15)
                ctx.fill(Path(roundedRect: stackRect, cornerRadius: 2),
                         with: .color(Color(hex: "#1a2838")))
                ctx.stroke(Path(roundedRect: stackRect, cornerRadius: 2),
                           with: .color(Color(hex: "#2e4a60").opacity(0.45)), lineWidth: 0.7)
                // Stack cap (flared top)
                ctx.fill(
                    Path(roundedRect: CGRect(x: sx - 1, y: cabY - 15, width: 7, height: 4), cornerRadius: 2),
                    with: .color(Color(hex: "#1a2838"))
                )
            }

            // Step board under cab door
            ctx.fill(
                Path(roundedRect: CGRect(x: cabX + 4, y: floorY - 7, width: cabW - 10, height: 5), cornerRadius: 2),
                with: .color(Color(hex: "#1a2535"))
            )

            // ── Chassis / frame rail ──────────────────────────────────────
            ctx.fill(
                Path(CGRect(x: trailerX + 12, y: floorY - 4, width: cabX + cabW - 12, height: 4)),
                with: .color(Color(hex: "#0f1a25"))
            )

            // ── Wheels ───────────────────────────────────────────────────
            let wheelY = groundY - wheelR
            let axles: [CGFloat] = [
                cabX + cabW * 0.38,           // front steer axle
                trailerX + trailerW * 0.72,   // drive axle 1
                trailerX + trailerW * 0.84,   // drive axle 2
                trailerX + trailerW * 0.15,   // trailer axle 1
                trailerX + trailerW * 0.27,   // trailer axle 2
            ]
            for wx in axles {
                // Tire
                ctx.fill(
                    Path(ellipseIn: CGRect(x: wx - wheelR, y: wheelY - wheelR,
                                          width: wheelR * 2, height: wheelR * 2)),
                    with: .color(Color(hex: "#070a0d"))
                )
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: wx - wheelR, y: wheelY - wheelR,
                                          width: wheelR * 2, height: wheelR * 2)),
                    with: .color(Color(hex: "#2e4a60").opacity(0.42)),
                    lineWidth: 1.5
                )
                // Rim
                let rimR = wheelR * 0.58
                ctx.fill(
                    Path(ellipseIn: CGRect(x: wx - rimR, y: wheelY - rimR,
                                          width: rimR * 2, height: rimR * 2)),
                    with: .color(Color(hex: "#18283a"))
                )
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: wx - rimR, y: wheelY - rimR,
                                          width: rimR * 2, height: rimR * 2)),
                    with: .color(Color(hex: "#3a5878").opacity(0.55)),
                    lineWidth: 0.8
                )
                // Hub dot
                let hubR: CGFloat = 2.5
                ctx.fill(
                    Path(ellipseIn: CGRect(x: wx - hubR, y: wheelY - hubR,
                                          width: hubR * 2, height: hubR * 2)),
                    with: .color(Color(hex: "#4a6890"))
                )
            }
        }
    }
}

// MARK: - Stars Field

private struct SplashStarsField: View {
    private struct Star: Identifiable {
        let id = UUID()
        let x, y, size: CGFloat
        let opacity: Double
        let twinkle: Bool
    }

    private let stars: [Star] = (0..<90).map { _ in
        Star(
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...0.62),
            size: CGFloat.random(in: 0.8...2.8),
            opacity: Double.random(in: 0.15...0.75),
            twinkle: Bool.random()
        )
    }

    @State private var twinklePhase: Double = 0

    var body: some View {
        GeometryReader { geo in
            ForEach(stars) { star in
                Circle()
                    .fill(Color.white)
                    .frame(width: star.size, height: star.size)
                    .position(x: star.x * geo.size.width, y: star.y * geo.size.height)
                    .opacity(star.twinkle
                             ? star.opacity * (0.6 + 0.4 * sin(twinklePhase + star.x * 10))
                             : star.opacity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                twinklePhase = .pi * 2
            }
        }
    }
}
