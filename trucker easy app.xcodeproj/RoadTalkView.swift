//
//  RoadTalkView.swift
//  Trucker Easy
//
//  Tab 4: Community & News
//  Features: Auto news feed (NewsAPI), AI chat assistant "Easy"
//

import SwiftUI

struct RoadTalkView: View {
    @StateObject private var viewModel = RoadTalkViewModel()
    @State private var showAIChat = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // AI Chat "Easy" - Quick Access
                    Button {
                        showAIChat = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 36))
                                .foregroundColor(Color("TruckerOrange"))
                            
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
                        .background(
                            LinearGradient(
                                colors: [Color("TruckerOrange").opacity(0.1), Color("TruckerOrange").opacity(0.05)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color("TruckerOrange"), lineWidth: 2)
                        )
                    }
                    .padding(.horizontal)
                    
                    // News Feed
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "newspaper.fill")
                                .font(.title2)
                                .foregroundColor(Color("TruckerOrange"))
                            
                            Text("Trucker News")
                                .font(.title3)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button {
                                Task {
                                    await viewModel.refreshNews()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(Color("TruckerOrange"))
                            }
                        }
                        .padding(.horizontal)
                        
                        if viewModel.isLoadingNews {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if viewModel.newsArticles.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "newspaper")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("No news available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            ForEach(viewModel.newsArticles) { article in
                                NewsArticleCard(article: article)
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
                AIChat()
            }
        }
        .task {
            await viewModel.loadNews()
        }
    }
}

// MARK: - News Article Card
struct NewsArticleCard: View {
    let article: NewsArticle
    
    var body: some View {
        Link(destination: article.url) {
            VStack(alignment: .leading, spacing: 12) {
                // Image
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
                
                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                    
                    if let description = article.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    HStack {
                        Text(article.source)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(article.publishedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - AI Chat View
struct AIChat: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = AIChatViewModel()
    @State private var messageText = ""
    @State private var isRecording = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat messages
                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
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
                
                // Input bar
                HStack(spacing: 12) {
                    // Voice input button
                    Button {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(isRecording ? .red : Color("TruckerOrange"))
                    }
                    
                    // Text input
                    TextField("Ask Easy anything...", text: $messageText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit {
                            sendMessage()
                        }
                    
                    // Send button
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(messageText.isEmpty ? .gray : Color("TruckerOrange"))
                    }
                    .disabled(messageText.isEmpty)
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
        
        Task {
            await viewModel.sendMessage(messageText)
            messageText = ""
        }
    }
    
    private func startRecording() {
        isRecording = true
        viewModel.startVoiceRecording()
    }
    
    private func stopRecording() {
        isRecording = false
        Task {
            await viewModel.stopVoiceRecording()
        }
    }
}

// MARK: - Chat Bubble
struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(message.isUser ? Color("TruckerOrange") : Color(UIColor.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
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

#Preview {
    RoadTalkView()
}
