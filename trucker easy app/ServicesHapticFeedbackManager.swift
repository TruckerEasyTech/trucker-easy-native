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
        #if DEBUG
        print("📳 [Haptic] Success")
        #endif
    }
    
    /// Warning feedback (truck restriction ahead)
    func warning() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
        #if DEBUG
        print("📳 [Haptic] Warning")
        #endif
    }
    
    /// Error feedback (route calculation failed, GPS lost)
    func error() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.error)
        #if DEBUG
        print("📳 [Haptic] Error")
        #endif
    }
    
    // MARK: - Impact Feedback
    
    /// Light impact (button tap, selection)
    func lightImpact() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #if DEBUG
        print("📳 [Haptic] Light impact")
        #endif
    }
    
    /// Medium impact (navigation started, warning dismissed)
    func mediumImpact() {
        guard isEnabled else { return }
        impactGenerator.impactOccurred()
        #if DEBUG
        print("📳 [Haptic] Medium impact")
        #endif
    }
    
    /// Heavy impact (critical warning, immediate action needed)
    func heavyImpact() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        #if DEBUG
        print("📳 [Haptic] Heavy impact")
        #endif
    }
    
    /// Rigid impact (error, obstacle detected)
    func rigidImpact() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        #if DEBUG
        print("📳 [Haptic] Rigid impact")
        #endif
    }
    
    /// Soft impact (info notification)
    func softImpact() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
        #if DEBUG
        print("📳 [Haptic] Soft impact")
        #endif
    }
    
    // MARK: - Selection Feedback
    
    /// Selection changed (scrolling through warnings, selecting route)
    func selection() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
        #if DEBUG
        print("📳 [Haptic] Selection")
        #endif
    }
    
    // MARK: - Custom Patterns
    
    /// Critical warning pattern (low bridge ahead < 500m)
    func criticalWarning() {
        guard isEnabled else { return }
        heavyImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.heavyImpact()
        }
        #if DEBUG
        print("📳 [Haptic] Critical warning pattern")
        #endif
    }
    
    /// Approaching restriction pattern (1km - 3km)
    func approachingRestriction() {
        guard isEnabled else { return }
        mediumImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.lightImpact()
        }
        #if DEBUG
        print("📳 [Haptic] Approaching restriction pattern")
        #endif
    }
    
    /// Navigation started pattern
    func navigationStarted() {
        guard isEnabled else { return }
        lightImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.mediumImpact()
        }
        #if DEBUG
        print("📳 [Haptic] Navigation started pattern")
        #endif
    }
    
    /// Navigation ended pattern (arrival)
    func navigationEnded() {
        guard isEnabled else { return }
        mediumImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.success()
        }
        #if DEBUG
        print("📳 [Haptic] Navigation ended pattern")
        #endif
    }
    
    /// Rerouting pattern
    func rerouting() {
        guard isEnabled else { return }
        warning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.mediumImpact()
        }
        #if DEBUG
        print("📳 [Haptic] Rerouting pattern")
        #endif
    }
    
    // MARK: - Enable/Disable
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        #if DEBUG
        print("📳 [Haptic] \(enabled ? "Enabled" : "Disabled")")
        #endif
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
