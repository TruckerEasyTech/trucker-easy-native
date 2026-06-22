//
//  ViewsTripShareSheet.swift
//  trucker easy app
//
//  Folha de "Compartilhar viagem" (acompanhamento read-only estilo Life360).
//  Gera o link, deixa enviar pra família e encerrar. A família só VÊ a posição —
//  nunca recebe navegação.

import SwiftUI
import UIKit

struct TripShareSheet: View {
    let lang: AppLanguage
    let originName: String?
    let destinationName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var share = TripShareService.shared
    @State private var starting = false
    @State private var failed = false

    private var t: TripShareStrings { TripShareStrings(lang: lang) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    if starting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color(hex: "#f57c17"))
                            .padding(.vertical, 28)
                        Text(t.starting).font(.subheadline).foregroundStyle(.secondary)
                    } else if failed {
                        failureCard
                    } else if let url = share.shareURL {
                        liveCard(url: url)
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "#0f0f12").ignoresSafeArea())
            .navigationTitle(t.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t.done) { dismiss() }.tint(Color(hex: "#f57c17"))
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Inicia só se ainda não estiver compartilhando (idempotente).
            guard !share.isSharing else { return }
            starting = true; failed = false
            let url = await share.startSharing(origin: originName, destination: destinationName)
            starting = false
            failed = (url == nil)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(hex: "#f57c17").opacity(0.16)).frame(width: 64, height: 64)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(hex: "#f57c17"))
            }
            Text(t.headline).font(.headline).multilineTextAlignment(.center)
            Text(t.subhead)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private func liveCard(url: URL) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 9, height: 9)
                Text(t.liveNow).font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }

            // Link copiável
            Button {
                UIPasteboard.general.string = url.absoluteString
            } label: {
                HStack {
                    Image(systemName: "link").font(.footnote)
                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Image(systemName: "doc.on.doc").font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            ShareLink(item: url, subject: Text(t.title), message: Text(t.shareMessage)) {
                Label(t.sendLink, systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#f57c17"))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(t.readOnlyNote)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)

            Button(role: .destructive) {
                Task { await share.stopSharing(); dismiss() }
            } label: {
                Label(t.stop, systemImage: "stop.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .tint(.red)
        }
    }

    private var failureCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34)).foregroundStyle(.secondary)
            Text(t.failed).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    starting = true; failed = false
                    let url = await share.startSharing(origin: originName, destination: destinationName)
                    starting = false; failed = (url == nil)
                }
            } label: {
                Text(t.tryAgain).font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color(hex: "#f57c17")).foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.vertical, 18)
    }
}

// MARK: - Strings (en / pt / es / fr — fallback inglês)

private struct TripShareStrings {
    let lang: AppLanguage
    private var c: String { lang.code }
    private var isPT: Bool { c.hasPrefix("pt") }
    private var isES: Bool { c.hasPrefix("es") }
    private var isFR: Bool { c.hasPrefix("fr") }

    var title: String { isPT ? "Compartilhar viagem" : isES ? "Compartir viaje" : isFR ? "Partager le trajet" : "Share trip" }
    var done: String { isPT ? "OK" : isES ? "Listo" : isFR ? "OK" : "Done" }
    var headline: String {
        isPT ? "Deixe a família acompanhar você" :
        isES ? "Deja que tu familia te siga" :
        isFR ? "Laissez vos proches vous suivre" :
        "Let your family follow along"
    }
    var subhead: String {
        isPT ? "Eles veem sua localização ao vivo no mapa — só acompanhar, sem navegação." :
        isES ? "Ven tu ubicación en vivo en el mapa — solo seguimiento, sin navegación." :
        isFR ? "Ils voient votre position en direct — suivi seul, sans navigation." :
        "They see your live location on a map — view only, no navigation."
    }
    var starting: String {
        isPT ? "Criando o link…" : isES ? "Creando el enlace…" : isFR ? "Création du lien…" : "Creating link…"
    }
    var liveNow: String { isPT ? "Ao vivo" : isES ? "En vivo" : isFR ? "En direct" : "Live now" }
    var sendLink: String { isPT ? "Enviar link" : isES ? "Enviar enlace" : isFR ? "Envoyer le lien" : "Send link" }
    var shareMessage: String {
        isPT ? "Acompanhe minha viagem ao vivo:" :
        isES ? "Sigue mi viaje en vivo:" :
        isFR ? "Suivez mon trajet en direct :" :
        "Follow my trip live:"
    }
    var readOnlyNote: String {
        isPT ? "Quem abrir o link só consegue VER onde você está. Ninguém recebe navegação nem pode alterar sua rota." :
        isES ? "Quien abra el enlace solo puede VER dónde estás. Nadie recibe navegación ni puede cambiar tu ruta." :
        isFR ? "Le lien permet seulement de VOIR où vous êtes. Personne ne reçoit la navigation." :
        "Anyone with the link can only SEE where you are. No one gets navigation or can change your route."
    }
    var stop: String { isPT ? "Parar de compartilhar" : isES ? "Dejar de compartir" : isFR ? "Arrêter le partage" : "Stop sharing" }
    var failed: String {
        isPT ? "Não foi possível iniciar agora. Verifique a conexão." :
        isES ? "No se pudo iniciar. Revisa la conexión." :
        isFR ? "Impossible de démarrer. Vérifiez la connexion." :
        "Couldn't start right now. Check your connection."
    }
    var tryAgain: String { isPT ? "Tentar de novo" : isES ? "Reintentar" : isFR ? "Réessayer" : "Try again" }
}
