import Foundation
import AVFoundation

// MARK: - VoiceNavigationManager
// Natural-sounding turn-by-turn navigation voice using AVSpeechSynthesizer.
// Selects the highest quality downloaded voice for each language.
// All public methods are main-actor-bound.

@Observable
@MainActor
final class VoiceNavigationManager {

    // MARK: - Shared instance
    static let shared = VoiceNavigationManager()

    // MARK: - State
    var isEnabled: Bool {
        get { _isEnabled }
        set {
            _isEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: "voiceNavigationEnabled")
            if !newValue { synthesizer.stopSpeaking(at: .immediate) }
        }
    }

    // MARK: - Private
    private var _isEnabled: Bool
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenStepIndex: Int = -1
    private var lastSpokenAlertId: UUID? = nil
    private var lastSpokenScaleName: String = ""
    /// Diesel / truck-stop ETA prompts once per named stop per navigation session (stop model IDs are not stable across searches).
    private var spokenTruckFuelStopNames: Set<String> = []
    private var lastSpeechTime: Date = .distantPast
    private let minIntervalSeconds: TimeInterval = 7

    // Cache resolved voices per language code
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    // MARK: - Init
    private init() {
        _isEnabled = UserDefaults.standard.object(forKey: "voiceNavigationEnabled") as? Bool ?? true
        configureAudioSession()
    }

    // MARK: - Audio Session
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // voicePrompt mode: optimized for spoken navigation, ducks music/podcasts
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[Voice] Audio session setup failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Public API

    func announceStep(instructions: String, stepIndex: Int, distanceText: String, lang: AppLanguage) {
        guard isEnabled else { return }
        guard stepIndex != lastSpokenStepIndex else { return }
        lastSpokenStepIndex = stepIndex
        let raw = String(format: lang.voiceTurnPhrase, distanceText, instructions)
        speak(naturalize(raw, lang: lang), language: lang.speechLanguageCode)
    }

    func announceArrival(lang: AppLanguage) {
        guard isEnabled else { return }
        lastSpokenStepIndex = -1
        speak(lang.voiceArrivedPhrase, language: lang.speechLanguageCode, priority: true)
    }

    func announceScaleAhead(stationName: String, distanceText: String, lang: AppLanguage) {
        guard isEnabled else { return }
        guard stationName != lastSpokenScaleName else { return }
        lastSpokenScaleName = stationName
        let phrase = String(format: lang.voiceScaleAheadPhrase, distanceText)
        speak(phrase, language: lang.speechLanguageCode)
    }

    /// Same as `announceScaleAhead` but includes crowd‑reported open / closed when known (navigation awareness).
    func announceScaleAheadWithStatus(stationName: String, distanceText: String, statusNote: String?, lang: AppLanguage) {
        guard isEnabled else { return }
        guard stationName != lastSpokenScaleName else { return }
        lastSpokenScaleName = stationName
        var phrase = String(format: lang.voiceScaleAheadPhrase, distanceText)
        if let statusNote, !statusNote.isEmpty {
            phrase += " \(statusNote)"
        }
        speak(phrase, language: lang.speechLanguageCode)
    }

    func announceTruckFuelEta(stopName: String, etaMinutes: Int, parkingNote: String? = nil, lang: AppLanguage) {
        guard isEnabled else { return }
        guard !spokenTruckFuelStopNames.contains(stopName) else { return }
        spokenTruckFuelStopNames.insert(stopName)
        var phrase = String(format: lang.voiceTruckFuelEtaPhrase, stopName, etaMinutes)
        if let parkingNote, !parkingNote.isEmpty {
            phrase += " \(parkingNote)."
        }
        speak(naturalize(phrase, lang: lang), language: lang.speechLanguageCode)
    }

    func announceRoadAlert(type: String, alertId: UUID, lang: AppLanguage) {
        guard isEnabled else { return }
        guard alertId != lastSpokenAlertId else { return }
        lastSpokenAlertId = alertId
        let phrase = String(format: lang.voiceRoadAlertPhrase, type)
        speak(phrase, language: lang.speechLanguageCode)
    }

    /// ETA × HOS — fala se a chegada cabe (ou não) nas horas de direção restantes do DOT.
    func announceHosEta(_ phrase: String, lang: AppLanguage) {
        guard isEnabled else { return }
        speak(naturalize(phrase, lang: lang), language: lang.speechLanguageCode, priority: true)
    }

    func resetForNewRoute() {
        lastSpokenStepIndex = -1
        lastSpokenAlertId = nil
        lastSpokenScaleName = ""
        spokenTruckFuelStopNames.removeAll()
        synthesizer.stopSpeaking(at: .word)
    }

    // MARK: - Text naturalizer

    /// Expands abbreviations and cleans up navigation text so TTS reads naturally.
    private func naturalize(_ text: String, lang: AppLanguage) -> String {
        var s = text

        // Road type abbreviations → full words (avoids awkward letter-spelling)
        let abbr: [(String, String)] = [
            ("I-",     "Interstate "),
            (" St ",   " Street "),
            (" St.",   " Street."),
            (" Ave ",  " Avenue "),
            (" Ave.",  " Avenue."),
            (" Blvd",  " Boulevard"),
            (" Hwy",   " Highway"),
            (" Pkwy",  " Parkway"),
            (" Dr ",   " Drive "),
            (" Dr.",   " Drive."),
            (" Rd ",   " Road "),
            (" Rd.",   " Road."),
            (" Ln ",   " Lane "),
            (" Ct ",   " Court "),
            (" Fwy",   " Freeway"),
            (" Expy",  " Expressway"),
        ]
        for (from, to) in abbr {
            s = s.replacingOccurrences(of: from, with: to)
        }

        // Compass abbreviations that TTS reads as letters ("N" → "North")
        // Only apply when surrounded by spaces to avoid breaking words like "No"
        let compass: [(String, String)] = [
            (" N ", " North "), (" S ", " South "),
            (" E ", " East "),  (" W ", " West "),
            (" NE ", " Northeast "), (" NW ", " Northwest "),
            (" SE ", " Southeast "), (" SW ", " Southwest "),
        ]
        for (from, to) in compass {
            s = s.replacingOccurrences(of: from, with: to)
        }

        // "0.x miles" → "point x miles" — TTS sometimes stumbles on "0.3"
        // Regex-free replacement for most common cases
        for digit in 1...9 {
            s = s.replacingOccurrences(of: "0.\(digit) mile", with: "point \(digit) mile")
        }

        // Remove double spaces
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }

        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Voice resolution (quality-first)

    /// Picks the most natural-sounding voice for the language.
    /// Priority: premium → enhanced → any matching language → English fallback.
    /// Quality is preferred over gender — a premium female voice sounds far better
    /// than a standard male one.
    private func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice {
        if let cached = voiceCache[languageCode] { return cached }

        let all = AVSpeechSynthesisVoice.speechVoices()
        let lang = languageCode.lowercased()

        // Exact locale first (e.g. "en-us"), then language prefix (e.g. "en")
        let exact  = all.filter { $0.language.lowercased() == lang }
        let prefix = all.filter { $0.language.lowercased().hasPrefix(String(lang.prefix(2))) }
        let pool   = exact.isEmpty ? prefix : exact

        // Ordena: 1º qualidade (premium > enhanced > default), 2º naturalidade da voz
        // (Siri/Ava/Zoe/Allison soam bem mais suaves e fluidas que Samantha default).
        let ranked = pool.sorted { a, b in
            let qa = qualityRank(a.quality), qb = qualityRank(b.quality)
            if qa != qb { return qa > qb }
            return naturalnessRank(a) < naturalnessRank(b)   // índice menor = mais natural
        }

        guard let resolved = ranked.first
            ?? AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice.speechVoices().first else {
            return AVSpeechSynthesisVoice()
        }

        voiceCache[languageCode] = resolved
        #if DEBUG
        print("[Voice] Selected: \(resolved.name) [\(resolved.language)] quality:\(resolved.quality.rawValue)")
        #endif
        return resolved
    }

    private func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium:  return 3
        case .enhanced: return 2
        default:        return 1
        }
    }

    /// Vozes en mais suaves/fluidas primeiro. Siri e as premium modernas (Ava/Zoe/Allison/Evan)
    /// soam naturais; Samantha (default) é a mais "robótica". Índice menor = preferida.
    private func naturalnessRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        let id = voice.identifier.lowercased()
        let name = voice.name.lowercased()
        // Siri voices (as mais fluidas quando o SO as expõe ao AVSpeech).
        if id.contains("siri") { return 0 }
        let preferred = ["ava", "zoe", "allison", "evan", "joelle", "nicky", "samantha"]
        for (i, n) in preferred.enumerated() where name.contains(n) || id.contains(n) {
            return 1 + i
        }
        return 50   // não-listada: depois das preferidas, antes de nada
    }

    // MARK: - Core speech

    private func speak(_ text: String, language: String, priority: Bool = false) {
        let now = Date()
        guard priority || now.timeIntervalSince(lastSpeechTime) >= minIntervalSeconds else { return }
        lastSpeechTime = now

        if priority { synthesizer.stopSpeaking(at: .word) }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice(for: language)

        // Levemente abaixo do default — fala calma e fluida, sem soar apressada nem robótica.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96

        // Pitch quase neutro, com um toque mais suave (evita o efeito mecânico agudo).
        utterance.pitchMultiplier = 0.98

        utterance.volume = 1.0

        // Lead-in maior suaviza a entrada (1ª palavra não é cortada pelo ducking do áudio).
        utterance.preUtteranceDelay  = priority ? 0.10 : 0.18

        // Respiro no fim pra não parecer cortada — dá fluidez entre frases.
        utterance.postUtteranceDelay = 0.18

        synthesizer.speak(utterance)
        #if DEBUG
        print("[Voice] ▶︎ \"\(text)\"  voice:\(utterance.voice?.name ?? "?")")
        #endif
    }
}
