//
//  ViewModels.swift
//  Trucker Easy
//
//  ViewModels for all major views
//

import Foundation
import SwiftUI
import CoreLocation
import Combine

// MARK: - Map ViewModel
@MainActor
class MapViewModel: ObservableObject {
    @Published var communityAlerts: [CommunityAlert] = []
    @Published var isNavigating = false
    @Published var currentRoute: TruckRoute?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadCommunityAlerts()
    }
    
    func loadCommunityAlerts() {
        // Load from Supabase
        Task {
            communityAlerts = await SupabaseManager.shared.fetchCommunityAlerts()
        }
    }
    
    func confirmAlert(_ alert: CommunityAlert) {
        Task {
            await SupabaseManager.shared.confirmAlert(alert)
            loadCommunityAlerts()
        }
    }
    
    func dismissAlert(_ alert: CommunityAlert) {
        communityAlerts.removeAll { $0.id == alert.id }
    }
    
    func startNavigation(route: TruckRoute) {
        currentRoute = route
        isNavigating = true
        
        // Save route to cache for offline use
        RouteCache.shared.saveRoute(route, for: route.destinationName)
    }
}

// MARK: - Checkup ViewModel
@MainActor
class CheckupViewModel: ObservableObject {
    @Published var medications: [Medication] = []
    @Published var recentSuggestions: [FoodSuggestion] = []
    @Published var todaysMoodRating: Int = 0
    
    private let supabase = SupabaseManager.shared
    
    init() {
        loadData()
    }
    
    func loadData() {
        Task {
            medications = await supabase.fetchMedications()
            recentSuggestions = await supabase.fetchFoodSuggestions()
            todaysMoodRating = await supabase.fetchTodaysMood()
        }
    }
    
    func saveMoodRating(_ rating: Int) {
        todaysMoodRating = rating
        
        Task {
            await supabase.saveMoodRating(rating)
        }
    }
    
    func addMedication(_ medication: Medication) {
        medications.append(medication)
        
        Task {
            await supabase.saveMedication(medication)
            scheduleNotification(for: medication)
        }
    }
    
    func markAsTaken(_ medication: Medication) {
        if let index = medications.firstIndex(where: { $0.id == medication.id }) {
            medications[index].lastTaken = Date()
            
            Task {
                await supabase.updateMedication(medications[index])
            }
        }
    }
    
    func deleteMedication(_ medication: Medication) {
        medications.removeAll { $0.id == medication.id }
        
        Task {
            await supabase.deleteMedication(medication)
        }
    }
    
    private func scheduleNotification(for medication: Medication) {
        NotificationManager.shared.scheduleMedicationReminder(medication)
    }
}

// MARK: - Cabin (Documents) ViewModel
@MainActor
class CabinViewModel: ObservableObject {
    @Published var documents: [Document] = []
    @Published var selectedDocumentType: DocumentType?
    
    private let supabase = SupabaseManager.shared
    
    var validDocuments: Int {
        documents.filter { $0.statusColor == .green }.count
    }
    
    var expiringDocuments: Int {
        documents.filter { $0.statusColor == .orange }.count
    }
    
    var expiredDocuments: Int {
        documents.filter { $0.statusColor == .red }.count
    }
    
    init() {
        loadDocuments()
    }
    
    func loadDocuments() {
        Task {
            documents = await supabase.fetchDocuments()
        }
    }
    
    func getDocument(type: DocumentType) -> Document? {
        documents.first { $0.type == type }
    }
    
    func addDocument(_ document: Document) {
        documents.append(document)
        
        Task {
            await supabase.saveDocument(document)
        }
    }
    
    func updateDocument(_ document: Document) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
            
            Task {
                await supabase.updateDocument(document)
            }
        }
    }
    
    func deleteDocument(_ document: Document) {
        documents.removeAll { $0.id == document.id }
        
        Task {
            await supabase.deleteDocument(document)
        }
    }
}

// MARK: - Road Talk ViewModel
@MainActor
class RoadTalkViewModel: ObservableObject {
    @Published var newsArticles: [NewsArticle] = []
    @Published var isLoadingNews = false
    
    private let newsAPI = NewsAPIService.shared
    
    func loadNews() async {
        isLoadingNews = true
        newsArticles = await newsAPI.fetchTruckingNews()
        isLoadingNews = false
    }
    
    func refreshNews() async {
        await loadNews()
    }
}

// MARK: - AI Chat ViewModel
@MainActor
class AIChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false
    
    private let aiService = AIService.shared
    
    func addWelcomeMessage() {
        let welcomeMessage = ChatMessage(
            text: "Hey driver! I'm Easy, your AI assistant. Ask me about truck routes, DOT regulations, app features, or anything else you need help with on the road. 🚛",
            isUser: false
        )
        messages.append(welcomeMessage)
    }
    
    func sendMessage(_ text: String) async {
        // Add user message
        let userMessage = ChatMessage(text: text, isUser: true)
        messages.append(userMessage)
        
        isProcessing = true
        
        // Get AI response
        let response = await aiService.getResponse(for: text, conversationHistory: messages)
        
        // Add AI response
        let aiMessage = ChatMessage(text: response, isUser: false)
        messages.append(aiMessage)
        
        isProcessing = false
    }
    
    func startVoiceRecording() {
        VoiceRecorder.shared.startRecording()
    }
    
    func stopVoiceRecording() async {
        let transcription = await VoiceRecorder.shared.stopRecording()
        if !transcription.isEmpty {
            await sendMessage(transcription)
        }
    }
    
    func clearHistory() {
        messages.removeAll()
        addWelcomeMessage()
    }
}
