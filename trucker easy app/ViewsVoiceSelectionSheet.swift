//
//  ViewsVoiceSelectionSheet.swift
//  Seletor de voz da navegação — lista as vozes REAIS instaladas no device (nada inventado),
//  deixa o motorista ouvir uma amostra e escolher. "Automática" usa a melhor voz disponível.
//
//  As vozes premium (mais suaves) precisam ser baixadas nos Ajustes do iOS; o app não pode baixar
//  por conta própria, então mostramos o caminho honesto e o app passa a usá-las assim que existirem.
//

import SwiftUI
import AVFoundation

struct VoiceSelectionSheet: View {
    var regionalSettings: RegionalSettingsManager

    @Environment(\.dismiss) private var dismiss
    @State private var voiceManager = VoiceNavigationManager.shared
    @State private var selectedId: String = VoiceNavigationManager.shared.preferredVoiceIdentifier
    @State private var voices: [AVSpeechSynthesisVoice] = []

    private var langPrefix: String {
        String(regionalSettings.currentLanguage.speechLanguageCode.prefix(2))
    }

    /// Amostra falada no idioma do app (com a unidade certa pro preview).
    private var sampleText: String {
        switch regionalSettings.currentLanguage {
        case .portuguese:           return "Em duzentos metros, vire à direita na próxima saída."
        case .spanish, .spanishLatam: return "En doscientos metros, gire a la derecha."
        case .french:               return "Dans deux cents mètres, tournez à droite."
        case .german:               return "In zweihundert Metern rechts abbiegen."
        default:                    return "In a quarter mile, turn right onto Main Street."
        }
    }

    private var onlyDefaultQuality: Bool {
        !voices.isEmpty && voices.allSatisfy { $0.quality == .default }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    enableToggleCard
                    if voiceManager.isEnabled {
                        voiceListCard
                        if onlyDefaultQuality { premiumHintCard }
                        Text("Toque numa voz para ouvir uma amostra e selecioná-la.")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(16)
            }
            .background(Color(hex: "#0a0906").ignoresSafeArea())
            .navigationTitle("Voz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { voices = voiceManager.installedVoices(forLanguagePrefix: langPrefix) }
    }

    // Liga/desliga a voz
    private var enableToggleCard: some View {
        HStack {
            Image(systemName: voiceManager.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 18))
                .foregroundColor(AppTheme.Colors.accent)
                .frame(width: 30)
            Text("Voz da navegação")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: Binding(
                get: { voiceManager.isEnabled },
                set: { voiceManager.isEnabled = $0 }
            ))
            .tint(AppTheme.Colors.accent)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // Automática + lista de vozes instaladas
    private var voiceListCard: some View {
        VStack(spacing: 0) {
            voiceRow(id: "", name: "Automática (melhor voz)",
                     detail: "Escolhe sozinho a voz mais natural instalada", quality: nil)
            ForEach(voices, id: \.identifier) { v in
                Divider().background(Color.white.opacity(0.06))
                voiceRow(id: v.identifier, name: v.name, detail: v.language, quality: v.quality)
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // Dica honesta: só voz padrão instalada → como baixar uma premium
    private var premiumHintCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quer uma voz bem mais suave?", systemImage: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "#f59e0b"))
            Text("Só a voz padrão está instalada neste aparelho. Baixe uma voz Premium (grátis) e o app passa a usá-la automaticamente:")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            Text("Ajustes → Acessibilidade → Conteúdo Falado → Vozes → Inglês → Ava (Premium)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button(action: openSettings) {
                Text("Abrir Ajustes do iOS")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.Colors.accent)
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func voiceRow(id: String, name: String, detail: String, quality: AVSpeechSynthesisVoiceQuality?) -> some View {
        Button {
            selectedId = id
            voiceManager.preferredVoiceIdentifier = id
            if id.isEmpty {
                // Preview da automática: usa a 1ª (melhor) da lista, se houver.
                if let best = voices.first { voiceManager.previewVoice(identifier: best.identifier, sample: sampleText) }
            } else {
                voiceManager.previewVoice(identifier: id, sample: sampleText)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedId == id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selectedId == id ? AppTheme.Colors.accent : .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Text(detail).font(.system(size: 11)).foregroundColor(.gray)
                        if let quality {
                            Text(voiceManager.qualityLabel(quality))
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(quality == .default ? Color.gray.opacity(0.25) : AppTheme.Colors.accent.opacity(0.25))
                                .foregroundColor(quality == .default ? .gray : AppTheme.Colors.accent)
                                .clipShape(Capsule())
                        }
                    }
                }
                Spacer()
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
