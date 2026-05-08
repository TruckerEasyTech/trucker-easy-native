//
//  AppState.swift
//  Trucker Easy
//
//  Global app state management
//

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isSubscribed: Bool = false
    @Published var isInTrial: Bool = false
    @Published var trialStartDate: Date?
    @Published var subscriptionType: SubscriptionType?
    @Published var selectedLanguage: String = "en" // Default English
    @Published var userProfile: UserProfile?
    
    private let trialDuration: TimeInterval = 3 * 24 * 60 * 60 // 3 days
    
    enum SubscriptionType: String, Codable {
        case monthly = "monthly"
        case annual = "annual"
    }
    
    init() {
        loadSubscriptionStatus()
        checkTrialStatus()
    }
    
    func startTrial() {
        trialStartDate = Date()
        isInTrial = true
        UserDefaults.standard.set(trialStartDate, forKey: "trialStartDate")
    }
    
    func checkTrialStatus() {
        guard let startDate = UserDefaults.standard.object(forKey: "trialStartDate") as? Date else {
            isInTrial = false
            return
        }
        
        let elapsed = Date().timeIntervalSince(startDate)
        isInTrial = elapsed < trialDuration && !isSubscribed
        
        if !isInTrial && trialStartDate != nil {
            trialStartDate = nil
            UserDefaults.standard.removeObject(forKey: "trialStartDate")
        }
    }
    
    func subscribe(type: SubscriptionType) {
        subscriptionType = type
        isSubscribed = true
        isInTrial = false
        UserDefaults.standard.set(type.rawValue, forKey: "subscriptionType")
        UserDefaults.standard.set(true, forKey: "isSubscribed")
    }
    
    private func loadSubscriptionStatus() {
        isSubscribed = UserDefaults.standard.bool(forKey: "isSubscribed")
        if let typeString = UserDefaults.standard.string(forKey: "subscriptionType") {
            subscriptionType = SubscriptionType(rawValue: typeString)
        }
    }
}

struct UserProfile: Codable {
    var id: String
    var name: String
    var healthConditions: [HealthCondition]
    var allergies: [String]
    var dietaryPreferences: DietaryPreference
    
    enum HealthCondition: String, Codable, CaseIterable {
        case diabetic = "Diabetic"
        case hypertensive = "Hypertensive"
        case celiac = "Celiac"
        case none = "None"
    }
    
    enum DietaryPreference: String, Codable, CaseIterable {
        case regular = "Regular"
        case lowCarb = "Low Carb"
        case lowSodium = "Low Sodium"
        case vegetarian = "Vegetarian"
        case glutenFree = "Gluten Free"
    }
}
