//
//  TruckerEasyTests.swift
//  Trucker Easy Tests
//
//  Unit tests using Swift Testing framework
//

import Testing
import Foundation
@testable import TruckerEasy

@Suite("Load Input Address Extraction Tests")
struct LoadInputTests {
    
    @Test("Extract full US address with zip code")
    func extractFullAddress() async throws {
        let viewModel = LoadInputViewModel()
        
        let loadInfo = """
        Pick up at 123 Main Street, Columbus, OH 43215
        Deliver by 5 PM tomorrow
        """
        
        let address = viewModel.extractAddress(from: loadInfo)
        
        #expect(address.contains("123 Main Street"))
        #expect(address.contains("OH"))
        #expect(address.contains("43215"))
    }
    
    @Test("Extract address from complex load document")
    func extractComplexAddress() async throws {
        let viewModel = LoadInputViewModel()
        
        let loadInfo = """
        LOAD #12345
        Weight: 45,000 lbs
        Pickup: 456 Industrial Blvd, Dallas, TX 75201
        Contact: John Doe (555-1234)
        """
        
        let address = viewModel.extractAddress(from: loadInfo)
        
        #expect(!address.isEmpty)
        #expect(address.contains("Industrial Blvd"))
    }
    
    @Test("Handle clipboard with no address")
    func handleNoAddress() async throws {
        let viewModel = LoadInputViewModel()
        
        let nonAddress = "Just some random text with no location"
        let address = viewModel.extractAddress(from: nonAddress)
        
        #expect(address.isEmpty)
    }
}

@Suite("Document Status Tests")
struct DocumentTests {
    
    @Test("Valid document shows green status")
    func validDocumentStatus() async throws {
        let futureDate = Calendar.current.date(byAdding: .day, value: 60, to: Date())!
        
        let document = Document(
            type: .cdl,
            expirationDate: futureDate
        )
        
        #expect(document.statusColor == .green)
        #expect(document.statusIcon == "checkmark.circle.fill")
    }
    
    @Test("Expiring document shows yellow status")
    func expiringDocumentStatus() async throws {
        let nearDate = Calendar.current.date(byAdding: .day, value: 15, to: Date())!
        
        let document = Document(
            type: .medicalCard,
            expirationDate: nearDate
        )
        
        #expect(document.statusColor == .orange)
        #expect(document.statusIcon == "exclamationmark.circle.fill")
    }
    
    @Test("Expired document shows red status")
    func expiredDocumentStatus() async throws {
        let pastDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        
        let document = Document(
            type: .dotPhysical,
            expirationDate: pastDate
        )
        
        #expect(document.statusColor == .red)
        #expect(document.statusIcon == "xmark.circle.fill")
        #expect(document.statusMessage.contains("EXPIRED"))
    }
}

@Suite("Route Caching Tests")
struct RouteCacheTests {
    
    @Test("Cache saves and retrieves route")
    func cacheRouteRetrieval() async throws {
        let cache = RouteCache.shared
        
        let mockRoute = TruckRoute(
            destinationName: "Dallas Distribution Center",
            destination: CLLocationCoordinate2D(latitude: 32.7767, longitude: -96.7970),
            distance: "250.5",
            estimatedTime: "4h 30m",
            polyline: MKPolyline(),
            truckRestrictions: TruckRestrictions()
        )
        
        await cache.saveRoute(mockRoute, for: "Dallas Distribution Center")
        
        let retrieved = await cache.getRoute(for: "Dallas Distribution Center")
        
        #expect(retrieved != nil)
        #expect(retrieved?.destinationName == "Dallas Distribution Center")
    }
    
    @Test("Cache handles case-insensitive destinations")
    func cacheCaseInsensitive() async throws {
        let cache = RouteCache.shared
        
        let mockRoute = TruckRoute(
            destinationName: "Chicago Warehouse",
            destination: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
            distance: "180.0",
            estimatedTime: "3h 15m",
            polyline: MKPolyline(),
            truckRestrictions: TruckRestrictions()
        )
        
        await cache.saveRoute(mockRoute, for: "Chicago Warehouse")
        
        // Test case variations
        let lowerCase = await cache.getRoute(for: "chicago warehouse")
        let upperCase = await cache.getRoute(for: "CHICAGO WAREHOUSE")
        
        #expect(lowerCase != nil)
        #expect(upperCase != nil)
    }
}

@Suite("Subscription Tests")
struct SubscriptionTests {
    
    @Test("Trial starts correctly")
    func trialStartTest() async throws {
        let appState = AppState()
        
        appState.startTrial()
        
        #expect(appState.isInTrial == true)
        #expect(appState.trialStartDate != nil)
    }
    
    @Test("Trial expires after 3 days")
    func trialExpirationTest() async throws {
        let appState = AppState()
        
        // Manually set trial start date to 4 days ago
        let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: Date())!
        UserDefaults.standard.set(fourDaysAgo, forKey: "trialStartDate")
        
        appState.checkTrialStatus()
        
        #expect(appState.isInTrial == false)
    }
    
    @Test("Subscription overrides trial")
    func subscriptionOverridesTrial() async throws {
        let appState = AppState()
        
        appState.startTrial()
        #expect(appState.isInTrial == true)
        
        appState.subscribe(type: .annual)
        
        #expect(appState.isSubscribed == true)
        #expect(appState.isInTrial == false)
    }
}

@Suite("Medication Reminder Tests")
struct MedicationTests {
    
    @Test("Medication time formatting")
    func medicationTimeFormat() async throws {
        var components = DateComponents()
        components.hour = 14
        components.minute = 30
        
        let time = Calendar.current.date(from: components)!
        
        let medication = Medication(
            name: "Blood Pressure Med",
            time: time,
            repeatDaily: true
        )
        
        // Time should be formatted as "2:30 PM" or similar
        #expect(medication.timeFormatted.contains("2") || medication.timeFormatted.contains("14"))
        #expect(medication.timeFormatted.contains("30"))
    }
}

@Suite("Community Alert Tests")
struct CommunityAlertTests {
    
    @Test("Alert types have correct icons")
    func alertTypeIcons() async throws {
        #expect(CommunityAlert.AlertType.weigh.icon == "scalemass.fill")
        #expect(CommunityAlert.AlertType.police.icon == "exclamationmark.shield.fill")
        #expect(CommunityAlert.AlertType.accident.icon == "car.2.fill")
    }
    
    @Test("Alert types have correct colors")
    func alertTypeColors() async throws {
        #expect(CommunityAlert.AlertType.weigh.color == .blue)
        #expect(CommunityAlert.AlertType.police.color == .red)
        #expect(CommunityAlert.AlertType.accident.color == .orange)
    }
}

@Suite("Health Profile Tests")
struct HealthProfileTests {
    
    @Test("User profile with dietary preferences")
    func userProfileCreation() async throws {
        let profile = UserProfile(
            id: "test-user-123",
            name: "Test Driver",
            healthConditions: [.diabetic, .hypertensive],
            allergies: ["Peanuts", "Shellfish"],
            dietaryPreferences: .lowSodium
        )
        
        #expect(profile.healthConditions.contains(.diabetic))
        #expect(profile.allergies.count == 2)
        #expect(profile.dietaryPreferences == .lowSodium)
    }
}

// MARK: - Performance Tests

@Suite("Performance Tests")
struct PerformanceTests {
    
    @Test("Address extraction performance")
    func addressExtractionPerformance() async throws {
        let viewModel = LoadInputViewModel()
        
        let loadInfo = """
        Multiple addresses in here:
        1. 123 Main St, Columbus, OH 43215
        2. 456 Oak Ave, Dallas, TX 75201
        3. 789 Pine Road, Miami, FL 33101
        Pick the first one
        """
        
        let startTime = Date()
        let _ = viewModel.extractAddress(from: loadInfo)
        let duration = Date().timeIntervalSince(startTime)
        
        // Should extract address in less than 100ms
        #expect(duration < 0.1)
    }
}
