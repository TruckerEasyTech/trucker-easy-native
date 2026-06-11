//
//  NavigationVoiceAnnouncementManager.swift
//  trucker easy app
//
//  Created by AI Assistant on 4/1/26.
//
//  Voice announcement system with intelligent throttling and deduplication.
//  Prevents spam by tracking warning.id + distance range.

import Foundation
import AVFoundation
import CoreLocation

// MARK: - Voice Announcement Manager

/// Manages voice announcements for truck navigation with smart throttling and deduplication
@Observable
@MainActor
final class NavigationVoiceAnnouncementManager {
    
    // MARK: - Configuration
    
    /// Minimum time between any announcements (global throttle)
    private let minimumTimeBetweenAnnouncements: TimeInterval = 8.0
    
    /// Distance ranges that trigger announcements (meters)
    private let distanceRanges: [DistanceRange] = [
        DistanceRange(min: 2900, max: 3100, label: "3 kilometers"),
        DistanceRange(min: 900, max: 1100, label: "1 kilometer"),
        DistanceRange(min: 450, max: 550, label: "500 meters"),
        DistanceRange(min: 150, max: 250, label: "200 meters")
    ]
    
    // MARK: - Public Properties
    
    /// Whether voice announcements are enabled
    var isEnabled: Bool = true
    
    /// Speech rate (0.0 = very slow, 1.0 = very fast)
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    
    /// Speech volume (0.0 = mute, 1.0 = max)
    var volume: Float = 0.8
    
    /// Voice language
    var language: String = "en-US"
    
    /// Is currently speaking
    private(set) var isSpeaking: Bool = false
    
    // MARK: - Private Properties
    
    private let synthesizer = AVSpeechSynthesizer()
    private var lastAnnouncementTime: Date?
    
    /// Tracks which warnings have been announced at which distance ranges
    /// Key: "warningID:rangeIndex" (e.g., "ABC123:0" for 3km range)
    private var announcedWarnings: Set<String> = []
    
    // MARK: - Initialization
    
    init() {
        setupAudioSession()
    }
    
    // MARK: - Public Methods
    
    /// Announces a generic message
    /// - Parameter message: Text to speak
    func announce(_ message: String) async {
        guard isEnabled else { return }
        guard canAnnounce() else {
            #if DEBUG
            print("[Voice] 🔇 Throttled: Too soon since last announcement")
            #endif
            return
        }
        
        speak(message)
        lastAnnouncementTime = Date()
    }
    
    /// Announces a truck restriction warning with smart deduplication
    /// - Parameters:
    ///   - warning: The restriction warning to announce
    ///   - distance: Current distance to warning in meters
    func announceWarning(
        _ warning: TruckRestrictionWarning,
        distance: Double
    ) {
        guard isEnabled else { return }
        guard canAnnounce() else {
            #if DEBUG
            print("[Voice] 🔇 Throttled: Too soon since last announcement")
            #endif
            return
        }
        
        // Find which distance range this falls into
        guard let (rangeIndex, range) = findDistanceRange(for: distance) else {
            #if DEBUG
            print("[Voice] ⏭️ Skipped: Distance \(Int(distance))m not in announcement ranges")
            #endif
            return
        }
        
        // Check if we've already announced this warning at this range
        let deduplicationKey = "\(warning.id):\(rangeIndex)"
        if announcedWarnings.contains(deduplicationKey) {
            #if DEBUG
            print("[Voice] ✋ Deduplicated: Already announced \(warning.type.rawValue) at \(range.label)")
            #endif
            return
        }
        
        // Build announcement message
        let message = buildAnnouncementMessage(for: warning, at: range)
        
        // Speak it
        speak(message)
        
        // Mark as announced
        announcedWarnings.insert(deduplicationKey)
        lastAnnouncementTime = Date()
        
        #if DEBUG
        print("[Voice] 🔊 Announced: \(warning.type.rawValue) at \(range.label) (\(Int(distance))m)")
        #endif
    }
    
    /// Checks for nearby warnings and announces them intelligently
    /// - Parameters:
    ///   - warnings: All active warnings
    ///   - currentLocation: User's current location
    func checkAndAnnounceNearbyWarnings(
        _ warnings: [TruckRestrictionWarning],
        currentLocation: CLLocation
    ) {
        guard isEnabled else { return }
        
        // Find closest warning within announcement range
        var closestWarning: TruckRestrictionWarning?
        var closestDistance: Double = .infinity
        
        for warning in warnings {
            guard let coord = warning.coordinate else { continue }
            
            let warningLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = currentLocation.distance(from: warningLocation)
            
            // Check if in any announcement range
            if findDistanceRange(for: distance) != nil {
                if distance < closestDistance {
                    closestDistance = distance
                    closestWarning = warning
                }
            }
        }
        
        // Announce closest warning
        if let warning = closestWarning {
            announceWarning(warning, distance: closestDistance)
        }
    }
    
    /// Stops current speech
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    /// Clears deduplication cache (e.g., when route changes)
    func resetDeduplication() {
        announcedWarnings.removeAll()
        #if DEBUG
        print("[Voice] 🔄 Deduplication cache cleared")
        #endif
    }
    
    // MARK: - Private Methods
    
    /// Sets up audio session for voice announcements
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("[Voice] ⚠️ Audio session setup failed: \(error)")
            #endif
        }
    }
    
    /// Checks if enough time has passed since last announcement
    private func canAnnounce() -> Bool {
        guard let lastTime = lastAnnouncementTime else {
            return true
        }
        
        let elapsed = Date().timeIntervalSince(lastTime)
        return elapsed >= minimumTimeBetweenAnnouncements
    }
    
    /// Finds which distance range the given distance falls into
    /// - Returns: Tuple of (rangeIndex, range) or nil if not in any range
    private func findDistanceRange(for distance: Double) -> (Int, DistanceRange)? {
        for (index, range) in distanceRanges.enumerated() {
            if distance >= range.min && distance <= range.max {
                return (index, range)
            }
        }
        return nil
    }
    
    /// Builds a natural announcement message for a warning
    private func buildAnnouncementMessage(
        for warning: TruckRestrictionWarning,
        at range: DistanceRange
    ) -> String {
        let warningType = warning.type.rawValue
        let distanceLabel = range.label
        
        // Extract key info from warning message
        let message = warning.message
        
        // Build natural speech
        var announcement = "\(warningType) ahead in \(distanceLabel)."
        
        // Add details if available
        if message.contains("clearance") || message.contains("height") {
            announcement += " \(extractHeightInfo(from: message))"
        } else if message.contains("weight") || message.contains("limit") {
            announcement += " \(extractWeightInfo(from: message))"
        } else if message.contains("width") {
            announcement += " \(extractWidthInfo(from: message))"
        }
        
        return announcement
    }
    
    /// Extracts height information from warning message
    private func extractHeightInfo(from message: String) -> String {
        if let range = message.range(of: #"\d+(\.\d+)?\s*(feet|ft|meters?|m)\s*\d*(\.\d+)?\s*(inches|in)?"#, options: .regularExpression) {
            let height = String(message[range])
            return "Clearance: \(height)."
        } else if let range = message.range(of: #"\d+(\.\d+)?\s*(cm|meters?|m|feet|ft)"#, options: .regularExpression) {
            let height = String(message[range])
            return "Maximum height: \(height)."
        }
        return ""
    }
    
    /// Extracts weight information from warning message
    private func extractWeightInfo(from message: String) -> String {
        if let range = message.range(of: #"\d+(\.\d+)?\s*(kg|tons?|tonnes?|lbs?|pounds?)"#, options: .regularExpression) {
            let weight = String(message[range])
            return "Maximum weight: \(weight)."
        }
        return ""
    }
    
    /// Extracts width information from warning message
    private func extractWidthInfo(from message: String) -> String {
        if let range = message.range(of: #"\d+(\.\d+)?\s*(feet|ft|meters?|m)"#, options: .regularExpression) {
            let width = String(message[range])
            return "Maximum width: \(width)."
        }
        return ""
    }
    
    /// Performs actual speech synthesis
    private func speak(_ message: String) {
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = rate
        utterance.volume = volume
        
        isSpeaking = true
        synthesizer.speak(utterance)
        
        // Reset speaking flag when done
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(message.count) * 0.05) {
            self.isSpeaking = false
        }
    }
}

// MARK: - Distance Range

/// Represents a distance range that triggers announcements
private struct DistanceRange {
    let min: Double
    let max: Double
    let label: String
}

// MARK: - Warning Manager Integration Extension

extension TruckRestrictionWarningManager {
    
    /// Updates location and announces nearby warnings with voice
    /// - Parameters:
    ///   - location: Current location
    ///   - voiceManager: Voice announcement manager
    func updateLocation(_ location: CLLocation, voiceManager: NavigationVoiceAnnouncementManager) {
        // First update location (existing logic)
        self.updateLocation(location)
        
        // Then check for voice announcements
        voiceManager.checkAndAnnounceNearbyWarnings(
            activeWarnings,
            currentLocation: location
        )
    }
    
    /// Loads warnings and resets voice deduplication
    /// - Parameters:
    ///   - route: TruckRoute
    ///   - userLocation: Current location
    ///   - specs: Truck specifications
    ///   - regulations: Regulation profile
    ///   - voiceManager: Voice manager to reset
    func loadWarnings(
        from route: TruckRoute,
        userLocation: CLLocation,
        specs: TruckSpecifications,
        regulations: RegulationProfile? = nil,
        voiceManager: NavigationVoiceAnnouncementManager
    ) async {
        await self.loadWarnings(
            from: route,
            userLocation: userLocation,
            specs: specs,
            regulations: regulations
        )
        
        // Reset voice deduplication for new route
        voiceManager.resetDeduplication()
        
        // Announce route loaded
        if !activeWarnings.isEmpty {
            await voiceManager.announce("Route calculated with \(activeWarnings.count) restrictions ahead.")
        } else {
            await voiceManager.announce("Route calculated. No restrictions detected.")
        }
    }
}
