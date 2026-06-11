//
//  VoiceAnnouncer.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/31/26.
//
//  Voice announcement system for truck navigation warnings

import Foundation
import AVFoundation

// MARK: - Voice Announcer

@MainActor
@Observable
class VoiceAnnouncer {
    private let synthesizer = AVSpeechSynthesizer()
    private var isEnabled = true
    private var currentUtterance: AVSpeechUtterance?
    
    // Voice settings
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var pitch: Float = 1.0
    var volume: Float = 1.0
    var language: String = "en-US"
    
    init() {
        configureAudioSessionCategory()
    }
    
    // MARK: - Public Methods
    
    /// Announce a message with voice
    func announce(_ message: String, priority: Priority = .normal) {
        guard isEnabled else { return }
        
        // Stop current announcement if lower priority
        if currentUtterance != nil, priority == .high {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = volume
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        
        // Adjust based on priority
        switch priority {
        case .high:
            utterance.rate = rate * 1.1  // Slightly faster
            utterance.volume = min(volume * 1.2, 1.0)  // Louder
        case .normal:
            break
        case .low:
            utterance.rate = rate * 0.9  // Slightly slower
            utterance.volume = volume * 0.8  // Quieter
        }
        
        activateAudioSession()
        currentUtterance = utterance
        synthesizer.speak(utterance)
        
        #if DEBUG
        print("🔊 [Voice] Announcing: \(message)")
        #endif
    }
    
    /// Announce truck warning with appropriate priority
    func announceWarning(_ warning: TruckRestrictionWarning, distance: Double) {
        let distanceText: String
        let priority: Priority
        
        if distance < 500 {
            distanceText = "immediately ahead"
            priority = .high
        } else if distance < 1000 {
            distanceText = "in \(Int(distance)) meters"
            priority = .high
        } else {
            let miles = distance / 1609.34
            distanceText = "in \(String(format: "%.1f", miles)) miles"
            priority = .normal
        }
        
        let message = "\(warning.type.rawValue). \(warning.message) \(distanceText)"
        announce(message, priority: priority)
    }
    
    /// Stop current announcement
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
    }
    
    /// Pause current announcement
    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }
    
    /// Resume paused announcement
    func resume() {
        synthesizer.continueSpeaking()
    }
    
    /// Enable/disable voice announcements
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            stop()
        }
    }
    
    // MARK: - Audio Session Setup

    /// Configure category/mode at launch (safe to call early — does NOT activate the session).
    private func configureAudioSessionCategory() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            #if DEBUG
            print("✅ [Voice] Audio session category configured")
            #endif
        } catch {
            #if DEBUG
            print("❌ [Voice] Audio session category setup failed: \(error)")
            #endif
        }
    }

    /// Activate the audio session just before speaking (avoids IPCAUClient errors on cold start).
    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            #if DEBUG
            print("❌ [Voice] Audio session activation failed: \(error)")
            #endif
        }
    }
    
    // MARK: - Priority
    
    enum Priority {
        case high    // Immediate danger (< 500m)
        case normal  // Standard warning (500m - 3km)
        case low     // Information only
    }
}

// MARK: - Predefined Announcements

extension VoiceAnnouncer {
    
    /// Announce route calculation started
    func announceRouteCalculation() {
        announce("Calculating truck-safe route", priority: .low)
    }
    
    /// Announce route calculated successfully
    func announceRouteReady(distance: Double, duration: Double, warningCount: Int) {
        let miles = Int(distance)
        let hours = Int(duration)
        let minutes = Int((duration - Double(hours)) * 60)
        
        var message = "Route calculated. \(miles) miles"
        
        if hours > 0 {
            message += ", \(hours) hour"
            if hours > 1 { message += "s" }
        }
        if minutes > 0 {
            message += " and \(minutes) minute"
            if minutes > 1 { message += "s" }
        }
        
        if warningCount > 0 {
            message += ". \(warningCount) truck restriction"
            if warningCount > 1 { message += "s" }
            message += " detected"
        }
        
        announce(message, priority: .normal)
    }
    
    /// Announce navigation started
    func announceNavigationStart(destination: String) {
        announce("Navigation started to \(destination)", priority: .normal)
    }
    
    /// Announce navigation cancelled
    func announceNavigationCancelled() {
        announce("Navigation cancelled", priority: .low)
    }
    
    /// Announce arrival
    func announceArrival(destination: String) {
        announce("You have arrived at \(destination)", priority: .normal)
    }
    
    /// Announce rerouting
    func announceRerouting() {
        announce("Rerouting to avoid truck restrictions", priority: .normal)
    }
}

// MARK: - Voice Settings Presets

extension VoiceAnnouncer {
    
    /// Apply default voice settings (balanced)
    func applyDefaultSettings() {
        rate = AVSpeechUtteranceDefaultSpeechRate
        pitch = 1.0
        volume = 1.0
        language = "en-US"
    }
    
    /// Apply fast voice settings (for experienced drivers)
    func applyFastSettings() {
        rate = AVSpeechUtteranceDefaultSpeechRate * 1.2
        pitch = 1.1
        volume = 0.9
        language = "en-US"
    }
    
    /// Apply clear voice settings (for better clarity)
    func applyClearSettings() {
        rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        pitch = 1.0
        volume = 1.0
        language = "en-US"
    }
    
    /// Apply loud voice settings (for noisy environments)
    func applyLoudSettings() {
        rate = AVSpeechUtteranceDefaultSpeechRate
        pitch = 1.0
        volume = 1.0  // Max volume
        language = "en-US"
    }
}

// MARK: - Available Voices

extension VoiceAnnouncer {
    
    /// Get available voices for current language
    static func availableVoices(for language: String = "en-US") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix(language.prefix(2))
        }
    }
    
    /// Get recommended voice for navigation
    static func recommendedVoice(for language: String = "en-US") -> AVSpeechSynthesisVoice? {
        // Prefer enhanced quality voices
        let voices = availableVoices(for: language)
        return voices.first { $0.quality == .enhanced } ?? voices.first
    }
}
