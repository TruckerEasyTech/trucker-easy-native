//
//  HapticFeedbackManager.swift
//  trucker easy app
//
//  Created by AI Assistant on 3/31/26.
//
//  Haptic feedback system for truck navigation events

import UIKit

// MARK: - Haptic Feedback Manager

@MainActor
class HapticFeedbackManager {
    
    // Generators
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    
    private var isEnabled = true
    
    init() {
        prepareGenerators()
    }
    
    // MARK: - Prepare
    
    /// Prepare haptic generators for reduced latency
    func prepareGenerators() {
        notificationGenerator.prepare()
        impactGenerator.prepare()
        selectionGenerator.prepare()
    }
    
    // MARK: - Notification Feedback
    
    /// Success feedback (route calculated, destination reached)
    func success() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
        print("📳 [Haptic] Success")
    }
    
    /// Warning feedback (truck restriction ahead)
    func warning() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
        print("📳 [Haptic] Warning")
    }
    
    /// Error feedback (route calculation failed, GPS lost)
    func error() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.error)
        print("📳 [Haptic] Error")
    }
    
    // MARK: - Impact Feedback
    
    /// Light impact (button tap, selection)
    func lightImpact() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        print("📳 [Haptic] Light impact")
    }
    
    /// Medium impact (navigation started, warning dismissed)
    func mediumImpact() {
        guard isEnabled else { return }
        impactGenerator.impactOccurred()
        print("📳 [Haptic] Medium impact")
    }
    
    /// Heavy impact (critical warning, immediate action needed)
    func heavyImpact() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        print("📳 [Haptic] Heavy impact")
    }
    
    /// Rigid impact (error, obstacle detected)
    func rigidImpact() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        print("📳 [Haptic] Rigid impact")
    }
    
    /// Soft impact (info notification)
    func softImpact() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
        print("📳 [Haptic] Soft impact")
    }
    
    // MARK: - Selection Feedback
    
    /// Selection changed (scrolling through warnings, selecting route)
    func selection() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
        print("📳 [Haptic] Selection")
    }
    
    // MARK: - Custom Patterns
    
    /// Critical warning pattern (low bridge ahead < 500m)
    func criticalWarning() {
        guard isEnabled else { return }
        heavyImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.heavyImpact()
        }
        print("📳 [Haptic] Critical warning pattern")
    }
    
    /// Approaching restriction pattern (1km - 3km)
    func approachingRestriction() {
        guard isEnabled else { return }
        mediumImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.lightImpact()
        }
        print("📳 [Haptic] Approaching restriction pattern")
    }
    
    /// Navigation started pattern
    func navigationStarted() {
        guard isEnabled else { return }
        lightImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.mediumImpact()
        }
        print("📳 [Haptic] Navigation started pattern")
    }
    
    /// Navigation ended pattern (arrival)
    func navigationEnded() {
        guard isEnabled else { return }
        mediumImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.success()
        }
        print("📳 [Haptic] Navigation ended pattern")
    }
    
    /// Rerouting pattern
    func rerouting() {
        guard isEnabled else { return }
        warning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.mediumImpact()
        }
        print("📳 [Haptic] Rerouting pattern")
    }
    
    // MARK: - Enable/Disable
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        print("📳 [Haptic] \(enabled ? "Enabled" : "Disabled")")
    }
}

// MARK: - Truck Navigation Events

extension HapticFeedbackManager {
    
    /// Feedback for truck warning based on distance
    func warningAtDistance(_ distance: Double) {
        guard isEnabled else { return }
        
        if distance < 500 {
            // Critical - immediate action needed
            criticalWarning()
        } else if distance < 1000 {
            // High priority - approaching fast
            heavyImpact()
        } else if distance < 3000 {
            // Normal - approaching
            approachingRestriction()
        } else {
            // Info only
            notification()
        }
    }
    
    /// Feedback for different warning types
    func feedbackForWarningType(_ type: TruckRestrictionWarning.WarningType) {
        guard isEnabled else { return }
        
        switch type {
        case .lowBridge, .heightLimit:
            // Critical warnings
            criticalWarning()
            
        case .weightLimit:
            // High priority
            heavyImpact()
            
        case .tunnel, .narrowRoad:
            // Medium priority
            warning()
            
        case .hazmat:
            // High priority for HAZMAT
            heavyImpact()
            
        case .general:
            // Low priority
            notification()
        }
    }
    
    /// Generic notification (info only)
    func notification() {
        guard isEnabled else { return }
        lightImpact()
    }
}

// MARK: - Example Usage

/*
 
 // Initialize
 let hapticManager = HapticFeedbackManager()
 
 // Route calculated successfully
 hapticManager.success()
 
 // Warning detected
 hapticManager.warningAtDistance(2500)  // 2.5km away
 
 // Critical warning (< 500m)
 hapticManager.warningAtDistance(350)
 
 // Navigation started
 hapticManager.navigationStarted()
 
 // Arrived at destination
 hapticManager.navigationEnded()
 
 // Error occurred
 hapticManager.error()
 
 // User dismissed warning
 hapticManager.mediumImpact()
 
 // User tapped button
 hapticManager.lightImpact()
 
 // Disable haptics
 hapticManager.setEnabled(false)
 
 */
