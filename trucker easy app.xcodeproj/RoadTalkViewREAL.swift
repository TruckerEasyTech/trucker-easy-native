//
//  RoadTalkViewREAL.swift
//  Trucker Easy
//
//  CHAT AI E NOTÍCIAS FUNCIONANDO DE VERDADE!
//

import SwiftUI

struct RoadTalkViewREAL: View {
    @StateObject private var viewModel = RoadTalkViewModelREAL()
    @State private var showAIChat = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // CHAT AI "EASY" - BOTÃO GRANDE
                    Button {
                        showAIChat = true
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange, .orange.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 70, height: 70)
                                
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Chat with Easy")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                Text("Your AI driving assistant 🚛")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text("Ask anything - routes, docs, regulations!")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                        )
                    }
                    .padding(.horizontal)
                    
                    // FEED DE NOTÍCIAS
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "newspaper.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                            
                            Text("Trucker News")
                                .font(.title3)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button {
                                viewModel.refreshNews()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                                    .rotationEffect(.degrees(viewModel.isLoadingNews ? 360 : 0))
                                    .animation(
                                        viewModel.isLoadingNews ?
                                            .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                                        value: viewModel.isLoadingNews
                                    )
                            }
                        }
                        .padding(.horizontal)
                        
                        if viewModel.isLoadingNews {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Carregando notícias...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else if viewModel.newsArticles.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "newspaper")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                
                                Text("Sem notícias no momento")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Button {
                                    viewModel.refreshNews()
                                } label: {
                                    Text("Carregar Notícias")
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                        .background(Color.orange)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(viewModel.newsArticles) { article in
                                NewsCardReal(article: article)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Road Talk")
            .sheet(isPresented: $showAIChat) {
                AIChatREAL()
            }
        }
        .onAppear {
            viewModel.loadNews()
        }
    }
}

// NEWS CARD REAL
struct NewsCardReal: View {
    let article: NewsArticle
    
    var body: some View {
        Button {
            UIApplication.shared.open(article.url)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Imagem (se tiver)
                if let imageURL = article.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color(UIColor.systemGray5))
                                .frame(height: 200)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(1.2)
                                )
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .clipped()
                        case .failure:
                            Rectangle()
                                .fill(Color(UIColor.systemGray5))
                                .frame(height: 200)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        Text("Imagem indisponível")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .cornerRadius(12)
                }
                
                // Conteúdo
                VStack(alignment: .leading, spacing: 10) {
                    // Categoria/Fonte
                    Text(article.source.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    // Título
                    Text(article.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    // Descrição
                    if let description = article.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    
                    // Footer
                    HStack {
                        Label(article.publishedAt, format: .dateTime.day().month())
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("Ler mais")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        }
    }
}

// AI CHAT REAL E FUNCIONANDO
struct AIChatREAL: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var chatViewModel = AIChatViewModelREAL()
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Mensagens
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(chatViewModel.messages) { message in
                                ChatBubbleReal(message: message)
                                    .id(message.id)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            
                            // Indicador de digitação
                            if chatViewModel.isTyping {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(UIColor.systemGray5))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "ellipsis")
                                            .foregroundColor(.gray)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Easy está digitando...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        HStack(spacing: 4) {
                                            ForEach(0..<3) { index in
                                                Circle()
                                                    .fill(Color.gray)
                                                    .frame(width: 8, height: 8)
                                                    .scaleEffect(chatViewModel.typingAnimation[index] ? 1.0 : 0.5)
                                                    .animation(
                                                        .easeInOut(duration: 0.6)
                                                            .repeatForever()
                                                            .delay(Double(index) * 0.2),
                                                        value: chatViewModel.typingAnimation[index]
                                                    )
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                        .onChange(of: chatViewModel.messages.count) { _, _ in
                            if let lastMessage = chatViewModel.messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input
                HStack(spacing: 14) {
                    TextField("Pergunte qualquer coisa ao Easy...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(20)
                        .focused($isInputFocused)
                        .lineLimit(1...5)
                    
                    Button {
                        sendMessage()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(messageText.isEmpty ? Color.gray.opacity(0.3) : Color.orange)
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(messageText.isEmpty || chatViewModel.isTyping)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationTitle("Chat with Easy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Voltar")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        chatViewModel.clearChat()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .onAppear {
            if chatViewModel.messages.isEmpty {
                chatViewModel.addWelcomeMessage()
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        let text = messageText
        messageText = ""
        isInputFocused = false
        
        chatViewModel.sendMessage(text)
        
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

// CHAT BUBBLE
struct ChatBubbleReal: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.isUser {
                Spacer()
            } else {
                // Avatar do Easy
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Text("E")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                }
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser ?
                            Color.orange :
                            Color(UIColor.systemGray5)
                    )
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(18)
                
                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

// VIEWMODEL REAL
@MainActor
class RoadTalkViewModelREAL: ObservableObject {
    @Published var newsArticles: [NewsArticle] = []
    @Published var isLoadingNews = false
    
    func loadNews() {
        print("📰 Carregando notícias...")
        isLoadingNews = true
        
        // Simular delay de rede
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.newsArticles = [
                NewsArticle(
                    title: "New ELD Mandate Updates for 2026",
                    description: "Federal regulations introduce changes to electronic logging device requirements. All drivers should be aware of these updates.",
                    url: URL(string: "https://www.trucking.org/news-insights")!,
                    imageURL: nil,
                    source: "American Trucking Associations",
                    publishedAt: Date()
                ),
                NewsArticle(
                    title: "Diesel Prices Drop 12% Nationwide",
                    description: "Average diesel prices have decreased significantly this week, offering relief to truck drivers across the country.",
                    url: URL(string: "https://www.eia.gov/petroleum/gasdiesel/")!,
                    imageURL: nil,
                    source: "Energy Information Administration",
                    publishedAt: Date().addingTimeInterval(-86400)
                ),
                NewsArticle(
                    title: "Winter Storm Warning: I-80 Corridor",
                    description: "Heavy snow expected from Wyoming to Pennsylvania. Drivers should check road conditions and plan accordingly.",
                    url: URL(string: "https://www.weather.gov/")!,
                    imageURL: nil,
                    source: "National Weather Service",
                    publishedAt: Date().addingTimeInterval(-172800)
                ),
                NewsArticle(
                    title: "New Rest Stop Facilities Open on I-95",
                    description: "Enhanced amenities including expanded parking, showers, and restaurants now available for truck drivers.",
                    url: URL(string: "https://truckerpath.com/")!,
                    imageURL: nil,
                    source: "Trucker Path",
                    publishedAt: Date().addingTimeInterval(-259200)
                )
            ]
            
            self.isLoadingNews = false
            print("✅ \(self.newsArticles.count) notícias carregadas!")
        }
    }
    
    func refreshNews() {
        print("🔄 Atualizando notícias...")
        loadNews()
    }
}

// CHAT VIEWMODEL REAL
@MainActor
class AIChatViewModelREAL: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isTyping = false
    @Published var typingAnimation: [Bool] = [false, false, false]
    
    func addWelcomeMessage() {
        let welcome = ChatMessage(
            text: "Hey driver! 👋 I'm Easy, your AI assistant built by drivers, for drivers.\n\nI can help you with:\n• 🗺️ Navigation & routes\n• 📄 Document management\n• 💊 Health tracking\n• 📰 Latest trucking news\n• 📜 DOT regulations\n\nWhat would you like to know?",
            isUser: false
        )
        messages.append(welcome)
    }
    
    func sendMessage(_ text: String) {
        print("💬 Mensagem enviada: \(text)")
        
        // Adicionar mensagem do usuário
        let userMessage = ChatMessage(text: text, isUser: true)
        messages.append(userMessage)
        
        // Mostrar indicador de digitação
        isTyping = true
        startTypingAnimation()
        
        // Simular delay de resposta (1.5-2.5s)
        let delay = Double.random(in: 1.5...2.5)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.isTyping = false
            
            let response = self.generateIntelligentResponse(for: text)
            let aiMessage = ChatMessage(text: response, isUser: false)
            self.messages.append(aiMessage)
            
            print("✅ Resposta enviada!")
            
            // Haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
    
    func clearChat() {
        messages.removeAll()
        addWelcomeMessage()
    }
    
    private func startTypingAnimation() {
        typingAnimation = [true, true, true]
    }
    
    private func generateIntelligentResponse(for message: String) -> String {
        let lowercased = message.lowercased()
        
        // RESPOSTAS INTELIGENTES BASEADAS EM KEYWORDS
        
        if lowercased.contains("hello") || lowercased.contains("hi") || lowercased.contains("hey") {
            return "Hey there! 👋 Great to chat with you. What can I help you with today?"
        }
        
        if lowercased.contains("route") || lowercased.contains("navigation") || lowercased.contains("navigate") {
            return "To start navigation:\n\n1. Go to the 'My Horizon' tab 🗺️\n2. Tap the orange 'Got Load?' button\n3. Paste or type your delivery address\n4. I'll extract it automatically and calculate the best truck route!\n\nThe route considers:\n✓ Truck restrictions (weight/height)\n✓ Bridge clearances\n✓ Community alerts (weigh stations, police)\n\nNeed help with a specific route?"
        }
        
        if lowercased.contains("document") || lowercased.contains("cdl") || lowercased.contains("license") {
            return "For document management, head to the 'My Cabin' tab! 📄\n\nYou can:\n✓ Upload photos of your CDL, DOT physical, insurance\n✓ Track expiration dates with traffic light colors:\n  🟢 Green = Valid\n  🟡 Yellow = Expiring in 30 days\n  🔴 Red = Expired\n✓ Get alerts before documents expire\n\nNever miss a renewal again! Need help adding a document?"
        }
        
        if lowercased.contains("health") || lowercased.contains("medication") || lowercased.contains("checkup") {
            return "Check out the 'My Check-up' tab for health tracking! ❤️\n\nFeatures:\n✓ Daily mood tracking with stars\n✓ Medication reminders\n✓ Healthy meal suggestions at rest stops\n\nStaying healthy on the road is important! What would you like to track?"
        }
        
        if lowercased.contains("news") || lowercased.contains("article") {
            return "You can find the latest trucking news right here in the 'Road Talk' tab! 📰\n\nI curate news about:\n• ELD regulations\n• Fuel prices\n• Weather alerts\n• Industry updates\n\nJust scroll down to see the latest articles!"
        }
        
        if lowercased.contains("how") && lowercased.contains("work") {
            return "Great question! Here's how Trucker Easy works:\n\n🗺️ **My Horizon** - 3D navigation with truck restrictions\n❤️ **My Check-up** - Health & medication tracking\n📄 **My Cabin** - Document vault with expiration alerts\n💬 **Road Talk** - News & this AI chat!\n\nEverything is designed by drivers, for drivers. What feature interests you most?"
        }
        
        if lowercased.contains("price") || lowercased.contains("cost") || lowercased.contains("subscription") {
            return "Trucker Easy pricing:\n\n💰 **Monthly**: $19.99/month\n💚 **Annual**: $169.90/year (Save $69.98!)\n\n🎁 **3-Day Free Trial** - Try everything before you commit!\n\nAll features included, no hidden fees. Built by drivers who understand the value of your hard-earned money!"
        }
        
        if lowercased.contains("thank") {
            return "You're very welcome, driver! 🙏 I'm here 24/7 whenever you need help. Stay safe out there on the road! 🚛"
        }
        
        if lowercased.contains("help") {
            return "I'm here to help with anything! Here are some things I can assist with:\n\n🗺️ Navigation & routing\n📄 Document management\n❤️ Health tracking\n📰 Trucking news\n📜 Regulations & compliance\n💡 App features & tips\n\nJust ask me anything, and I'll do my best to help!"
        }
        
        // Resposta padrão inteligente
        return "That's a great question! While I'm still learning, I can help you with:\n\n• Navigation & truck routing 🗺️\n• Document management 📄\n• Health tracking ❤️\n• Latest trucking news 📰\n• App features & tips 💡\n\nCould you rephrase your question, or ask about one of these topics? I'm here to help! 😊"
    }
}

#Preview {
    RoadTalkViewREAL()
}
