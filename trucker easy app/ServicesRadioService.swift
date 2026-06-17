//  ServicesRadioService.swift
//  Rádio REAL via AVPlayer (streaming ao vivo) — comunidade/Copa 2026.
//  Estações default com URLs TESTADAS ao vivo (16/06/2026) que respondem 200 audio.
//  A estação da Copa/jogo é atualizável (a URL com direitos do jogo muda) — ver `replaceStations`.
//
//  Criado pelo Jarvis · 2026-06-16

import Foundation
import AVFoundation

struct RadioStation: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let genre: String        // "Notícias" / "Música" / "Esportes" / "Copa 2026"
    let streamURL: String
}

@MainActor
@Observable
final class RadioService {
    static let shared = RadioService()

    private(set) var stations: [RadioStation]
    private(set) var currentStation: RadioStation?
    private(set) var isPlaying = false
    private(set) var isBuffering = false

    private var player: AVPlayer?
    private var statusObserver: NSKeyValueObservation?

    private init() {
        stations = RadioService.defaultStations
    }

    /// URLs testadas ao vivo (16/06/2026) — HTTP 200, content-type audio. Nada inventado.
    static let defaultStations: [RadioStation] = [
        RadioStation(id: "bbcws",  name: "BBC World Service",     genre: "Mundo · Copa",
                     streamURL: "https://stream.live.vc.bbcmedia.co.uk/bbc_world_service"),
        RadioStation(id: "npr",    name: "NPR News",              genre: "Notícias",
                     streamURL: "https://npr-ice.streamguys1.com/live.mp3"),
        RadioStation(id: "somafm", name: "SomaFM · Groove Salad", genre: "Música",
                     streamURL: "https://ice1.somafm.com/groovesalad-128-mp3"),
        RadioStation(id: "kexp",   name: "KEXP Seattle",          genre: "Música",
                     streamURL: "https://kexp-mp3-128.streamguys1.com/kexp128.mp3")
    ]

    /// Substitui a lista (ex.: estações vindas da nuvem — Copa/jogo — sem precisar de release).
    func replaceStations(_ new: [RadioStation]) {
        guard !new.isEmpty else { return }
        stations = new
    }

    func toggle(_ station: RadioStation) {
        if currentStation == station, isPlaying { stop() } else { play(station) }
    }

    func play(_ station: RadioStation) {
        guard let url = URL(string: station.streamURL) else { return }
        configureSession()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay: self.isBuffering = false; self.isPlaying = true
                case .failed:      self.isBuffering = false; self.stop()   // falhou → para, sem fingir
                default:           break
                }
            }
        }
        player = p
        currentStation = station
        isBuffering = true
        isPlaying = true
        p.play()
    }

    func stop() {
        player?.pause()
        statusObserver?.invalidate()
        statusObserver = nil
        player = nil
        isPlaying = false
        isBuffering = false
        currentStation = nil
    }

    /// `.playback` + `.mixWithOthers`: rádio toca em background e deixa a voz de navegação sobrepor.
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
