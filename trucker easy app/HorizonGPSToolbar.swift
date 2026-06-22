//
//  HorizonGPSToolbar.swift — 8 quick tools above idle search (spec Tela 1).
//

import SwiftUI

struct HorizonGPSToolbar: View {
    var lang: AppLanguage = .english
    var embeddedInChrome: Bool = false
    let onDirections: () -> Void
    let onPlaces: () -> Void
    let onWeighStation: () -> Void
    let onRestAreas: () -> Void
    let onRouteOptions: () -> Void
    let onWeather: () -> Void

    // 6 categorias que abrem PAINÉIS/LISTAS (decisão: "barra = listas, flutuante = camadas").
    // Removidos: "Cam" (tinha ícone de vídeo mas abria o AI — duplicava o sparkle flutuante) e
    // "Tra" (na verdade trocava o estilo de mapa). Câmeras/radar/tráfego/AI agora SÓ no flutuante.
    var body: some View {
        HStack(spacing: 0) {
            tool(icon: "magnifyingglass", label: "Search", action: onDirections)
            tool(icon: "fuelpump.fill", label: "Stops", action: onPlaces)
            tool(icon: "scalemass.fill", label: "Scales", action: onWeighStation)
            tool(icon: "bed.double.fill", label: "Rest", action: onRestAreas)
            tool(icon: "dollarsign.circle", label: "Tolls", action: onRouteOptions)
            tool(icon: "cloud.sun.fill", label: "Weather", action: onWeather)
        }
        .padding(.horizontal, 6)
        .frame(height: GPSDesignSystem.Metrics.toolbarHeight)
        .modifier(EmbeddedToolbarChrome(embedded: embeddedInChrome))
    }
}

private struct EmbeddedToolbarChrome: ViewModifier {
    let embedded: Bool
    func body(content: Content) -> some View {
        if embedded {
            content
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(GPSDesignSystem.Colors.border)
                        .frame(height: 0.5)
                }
        } else {
            content.gpsChromePanel()
        }
    }
}

extension HorizonGPSToolbar {
    @ViewBuilder
    private func tool(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(GPSDesignSystem.Colors.textPrimary)
                    .frame(width: GPSDesignSystem.Metrics.toolbarIconSize, height: GPSDesignSystem.Metrics.toolbarIconSize)
                    .background(GPSDesignSystem.Colors.panelElevated)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(GPSDesignSystem.Colors.border, lineWidth: 0.5))

                Text(label)
                    .font(GPSDesignSystem.Typography.toolbarLabel())
                    .foregroundColor(GPSDesignSystem.Colors.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
