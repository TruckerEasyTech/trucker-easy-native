//
//  ViewsTrafficCameraSheet.swift
//  Visualizador da câmera de trânsito 511 — imagem AO VIVO do DOT.
//
//  A URL é a imagem real do DOT (refresca no servidor). O cache-buster força o AsyncImage a
//  buscar um frame fresco ao abrir e no botão de recarregar. Nada fabricado: se a câmera não
//  responde, mostra "indisponível" honestamente.
//

import SwiftUI

struct TrafficCameraSheet: View {
    let camera: TrafficCamera
    var lang: AppLanguage = .english

    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "video.fill").foregroundColor(Color(hex: "#1aa6a6"))
                Text(camera.label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Spacer()
                Button { reloadToken = UUID() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
            }

            AsyncImage(url: URL(string: cacheBustedURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                case .failure:
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash").font(.system(size: 26))
                        Text("Câmera indisponível no momento")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, minHeight: 200)
                case .empty:
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, minHeight: 200)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)

            Text("511 · \(camera.source.uppercased()) · imagem ao vivo")
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0a0906"))
        .preferredColorScheme(.dark)
    }

    /// Mesma URL real do DOT + um token pra furar o cache (imagem fresca ao abrir/recarregar).
    private var cacheBustedURL: String {
        let sep = camera.imageURL.contains("?") ? "&" : "?"
        return "\(camera.imageURL)\(sep)_t=\(reloadToken.uuidString)"
    }
}
