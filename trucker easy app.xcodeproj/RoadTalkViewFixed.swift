//
//  RoadTalkViewFixed.swift
//  Trucker Easy
//
//  NOTÍCIAS E CHAT AI FUNCIONANDO - 100% NATIVO
//

import SwiftUI

struct RoadTalkViewFixed: View {
    @StateObject private var viewModel = RoadTalkViewModelWorking()
    @State private var showAIChat = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // CHAT AI "EASY" - FUNCIONANDO!
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
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chat with Easy")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Your AI driving assistant - Ask anything!")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.05), radius: 8)
                    }
                    .padding(.horizontal)
                    
                    // FEED DE NOTÍCIAS - FUNCIONANDO!
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
                                Image(systemName: viewModel.isLoadingNews ? "arrow.clockwise" : "arrow.clockwise")
                                    .foregroundColor(.orange)
                                    .rotationEffect(.degrees(viewModel.isLoadingNews ? 360 : 0))
                                    .animation(.linear(duration: 1).repeatWhile(viewModel.isLoadingNews), value: viewModel.isLoadingNews)
                            }
                        }
                        .padding(.horizontal)
                        
                        if viewModel.isLoadingNews {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Spacer()
                            }
                            .padding()
                        } else if viewModel.newsArticles.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "newspaper")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("No news available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Button("Tap to load news") {
                                    viewModel.refreshNews()
                                }
                                .foregroundColor(.orange)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            ForEach(viewModel.newsArticles) { article in
                                NewsArticleCardWorking(article: article)
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
                AIChatWorking()
            }
        }
        .onAppear {
            viewModel.loadMockNews()
        }
    }
}

// Card de notícia FUNCIONANDO
struct NewsArticleCardWorking: View {
    let article: NewsArticle
    
    var body: some View {
        Button {
            // Abrir URL no Safari
            UIApplication.shared.open(article.url)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Imagem (se tiver)
                if let imageURL = article.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color(UIColor.systemGray5))
                                .frame(height: 180)
                                .overlay(ProgressView())
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 180)
                                .clipped()
                        case .failure:
                            Rectangle()
                                .fill(Color(UIColor.systemGray5))
                                .frame(height: 180)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .cornerRadius(12)
                }
                
                // Título e descrição
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    if let description = article.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    HStack {
                        Text(article.source)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(article.publishedAt, format: .dateTime.month().day())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8)
        }
    }
}

// CHAT AI FUNCIONANDO!
struct AIChatWorking: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = AIChatViewModelWorking()
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Mensagens do chat
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                ChatBubbleWorking(message: message)
                                    .id(message.id)
                            }
                            
                            if viewModel.isProcessing {
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                    Text("Easy is thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            }
                        }
                        .padding()
                        .onChange(of: viewModel.messages.count) { _, _ in
                            if let lastMessage = viewModel.messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                // Barra de input FUNCIONANDO
                HStack(spacing: 12) {
                    // Text field
                    TextField("Ask Easy anything...", text: $messageText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            sendMessage()
                        }
                    
                    // Botão enviar
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(messageText.isEmpty ? .gray : .orange)
                    }
                    .disabled(messageText.isEmpty || viewModel.isProcessing)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationTitle("Chat with Easy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .onAppear {
            if viewModel.messages.isEmpty {
                viewModel.addWelcomeMessage()
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        let message = messageText
        messageText = ""
        isInputFocused = false
        
        viewModel.sendMessage(message)
    }
}

// Bubble do chat
struct ChatBubbleWorking: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(message.isUser ? Color.orange : Color(UIColor.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

// ViewModel para Road Talk
@MainActor
class RoadTalkViewModelWorking: ObservableObject {
    @Published var newsArticles: [NewsArticle] = []
    @Published var isLoadingNews = false
    
    func loadMockNews() {
        print("📰 Carregando notícias mock...")
        
        newsArticles = [
            NewsArticle(
                title: "New Federal Trucking Regulations Take Effect",
                description: "Important changes to hours of service rules that every driver should know about.",
                url: URL(string: "https://example.com/news1")!,
                imageURL: nil,
                source: "Transport Topics",
                publishedAt: Date()
            ),
            NewsArticle(
                title: "Diesel Prices Drop Nationwide",
                description: "Average diesel prices have decreased by 15 cents per gallon this week.",
                url: URL(string: "https://example.com/news2")!,
                imageURL: nil,
                source: "Trucking Info",
                publishedAt: Date().addingTimeInterval(-86400)
            ),
            NewsArticle(
                title: "Winter Weather Advisory for I-80 Corridor",
                description: "Heavy snow expected across Wyoming and Nebraska. Drivers should prepare for delays.",
                url: URL(string: "https://example.com/news3")!,
                imageURL: nil,
                source: "Weather Channel",
                publishedAt: Date().addingTimeInterval(-172800)
            )
        ]
        
        print("✅ \(newsArticles.count) notícias carregadas")
    }
    
    func refreshNews() {
        print("🔄 Atualizando notícias...")
        isLoadingNews = true
        
        // Simular delay de rede
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.loadMockNews()
            self.isLoadingNews = false
        }
    }
}

// ViewModel para AI Chat
@MainActor
class AIChatViewModelWorking: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing = false
    
    func addWelcomeMessage() {
        let welcomeMessage = ChatMessage(
            text: "Hey driver! 👋 I'm Easy, your AI assistant. Ask me about truck routes, DOT regulations, app features, or anything else you need help with on the road. 🚛",
            isUser: false
        )
        messages.append(welcomeMessage)
    }
    
    func sendMessage(_ text: String) {
        print("💬 Enviando mensagem: \(text)")
        
        // Adicionar mensagem do usuário
        let userMessage = ChatMessage(text: text, isUser: true)
        messages.append(userMessage)
        
        isProcessing = true
        
        // Simular resposta da AI (depois você integra com API real)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let response = self.generateResponse(for: text)
            let aiMessage = ChatMessage(text: response, isUser: false)
            self.messages.append(aiMessage)
            self.isProcessing = false
            
            print("✅ Resposta gerada")
        }
    }
    
    func clearHistory() {
        print("🗑️ Limpando histórico do chat")
        messages.removeAll()
        addWelcomeMessage()
    }
    
    private func generateResponse(for message: String) -> String {
        let lowercased = message.lowercased()
        
        // Respostas inteligentes baseadas em palavras-chave
        if lowercased.contains("hello") || lowercased.contains("hi") || lowercased.contains("hey") {
            return "Hey there, driver! What can I help you with today? 😊"
        } else if lowercased.contains("route") || lowercased.contains("navigation") {
            return "To start navigation, tap 'Got Load?' and paste or type your delivery address. I'll extract it automatically and calculate the best truck route! 🗺️"
        } else if lowercased.contains("document") || lowercased.contains("cdl") {
            return "Go to the 'My Cabin' tab to manage all your documents. You can upload photos and I'll track expiration dates for you. Never miss a renewal again! 📄"
        } else if lowercased.contains("health") || lowercased.contains("medication") {
            return "Check out 'My Check-up' tab! You can track your daily mood, set medication reminders, and get healthy meal suggestions at rest stops. 💊"
        } else if lowercased.contains("how") && lowercased.contains("you") {
            return "I'm doing great, thanks for asking! I'm here 24/7 to help you stay safe and organized on the road. 🚛"
        } else if lowercased.contains("thank") {
            return "You're very welcome, driver! Stay safe out there! 🙏"
        } else {
            return "That's a great question! While I'm still learning, you can explore the app's features:\n\n• My Horizon - Navigation\n• My Check-up - Health tracking\n• My Cabin - Documents\n• Road Talk - News & chat\n\nWhat would you like to know more about?"
        }
    }
}

// Extension para animação de rotação contínua
extension Animation {
    static func linear(duration: TimeInterval) -> Animation {
        Animation.linear(duration: duration)
    }
    
    func repeatWhile(_ condition: Bool) -> Animation {
        condition ? self.repeatForever(autoreverses: false) : self
    }
}

#Preview {
    RoadTalkViewFixed()
}
