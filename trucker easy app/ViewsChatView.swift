//
//  ChatView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 3/1/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import Combine
import AVFoundation

@MainActor
struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var channels: [ChatChannel]

    @State private var showingNewChannel = false
    @State private var selectedCategory: String? = nil

    private let categoryOrder = ["general", "routes", "safety", "regional", "help"]

    private var activeChannels: [ChatChannel] {
        channels.filter { $0.isActive }
    }

    private var filteredChannels: [ChatChannel] {
        if let cat = selectedCategory {
            return activeChannels.filter { $0.category == cat }
        }
        return activeChannels
    }

    // Category display info
    private func catIcon(_ cat: String) -> String {
        switch cat {
        case "general":  return "bubble.left.and.bubble.right.fill"
        case "routes":   return "road.lanes"
        case "safety":   return "shield.fill"
        case "regional": return "map.fill"
        case "help":     return "questionmark.circle.fill"
        default:         return "number"
        }
    }
    private func catColor(_ cat: String) -> Color {
        switch cat {
        case "general":  return Color(hex: "#6366f1")
        case "routes":   return Color(hex: "#f59e0b")
        case "safety":   return Color(hex: "#ef4444")
        case "regional": return Color(hex: "#10b981")
        case "help":     return Color(hex: "#0ea5e9")
        default:         return Color.gray
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0d1117").ignoresSafeArea()
                VStack(spacing: 0) {
                    // Category filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryChip(nil, label: "Todos", icon: "square.grid.2x2.fill")
                            ForEach(categoryOrder, id: \.self) { cat in
                                categoryChip(cat, label: cat.capitalized, icon: catIcon(cat))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    Divider().background(Color.white.opacity(0.08))

                    // Channel list
                    if filteredChannels.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 44))
                                .foregroundColor(Color.white.opacity(0.15))
                            Text("Nenhuma sala nesta categoria")
                                .font(.system(size: 15))
                                .foregroundColor(Color.white.opacity(0.35))
                            Button(action: { showingNewChannel = true }) {
                                Label("Criar Sala", systemImage: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(hex: "#c9a84c"))
                            }
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredChannels) { channel in
                                    NavigationLink(destination: ChatChannelView(channel: channel)) {
                                        DriverChannelRow(channel: channel, catColor: catColor(channel.category), catIcon: catIcon(channel.category))
                                    }
                                    .buttonStyle(.plain)
                                    Divider().background(Color.white.opacity(0.06)).padding(.leading, 72)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .navigationTitle("Salas de Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "#0d1117"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewChannel = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(hex: "#c9a84c"))
                    }
                }
            }
            .sheet(isPresented: $showingNewChannel) {
                NewChannelView()
            }
            .onAppear {
                createDefaultChannels()
            }
        }
    }

    @ViewBuilder
    private func categoryChip(_ cat: String?, label: String, icon: String) -> some View {
        let isSelected = selectedCategory == cat
        Button(action: { selectedCategory = cat }) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(label).font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(isSelected ? .white : Color.white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? (cat.map { catColor($0) } ?? Color(hex: "#6366f1")) : Color.white.opacity(0.07))
            .cornerRadius(20)
        }
    }

    private func createDefaultChannels() {
        if channels.isEmpty {
            let defaultChannels = [
                ChatChannel(name: "Geral / General", description: "Bate-papo geral dos motoristas", category: "general"),
                ChatChannel(name: "Rotas & Dicas", description: "Compartilhe rotas e dicas de viagem", category: "routes"),
                ChatChannel(name: "Segurança", description: "Alertas e dicas de segurança", category: "safety"),
                ChatChannel(name: "Sudeste (BR)", description: "Motoristas do Sudeste", category: "regional"),
                ChatChannel(name: "I-95 Corridor", description: "East Coast drivers", category: "regional"),
                ChatChannel(name: "Ajuda & Suporte", description: "Tire suas dúvidas", category: "help")
            ]
            for channel in defaultChannels {
                modelContext.insert(channel)
            }
        }
    }
}

// MARK: - Driver Channel Row (dark themed)

private struct DriverChannelRow: View {
    let channel: ChatChannel
    let catColor: Color
    let catIcon: String

    var body: some View {
        HStack(spacing: 14) {
            // Category icon circle
            ZStack {
                Circle()
                    .fill(catColor.opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: catIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(catColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(channel.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    if channel.memberCount > 10 {
                        Text("🔥")
                            .font(.system(size: 11))
                    }
                }
                Text(channel.channelDescription)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.2))
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.3))
                    Text("\(channel.memberCount)")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "#0d1117"))
    }
}

struct ChannelRow: View {
    let channel: ChatChannel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "number")
                    .foregroundColor(.blue)
                
                Text(channel.name)
                    .font(.headline)
                
                Spacer()
                
                Text("\(channel.memberCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Image(systemName: "person.2")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(channel.channelDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
struct ChatChannelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var messages: [ChatMessage]
    @Bindable var channel: ChatChannel
    
    @State private var newMessage = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    
    // AI related state
    @State private var isAITyping = false
    @State private var aiStreamingText: String = ""
    @State private var suggestions: [String] = []
    
    private let ai = AIService.shared
    
    var channelMessages: [ChatMessage] {
        messages.filter { $0.channelId == channel.id.uuidString }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(channelMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if isAITyping {
                            AIResponseBubble(text: aiStreamingText)
                                .id("aiTypingIndicator")
                        }
                    }
                    .padding()
                }
                .onChange(of: channelMessages.count) {
                    if let last = channelMessages.last {
                        withAnimation {
                            scrollViewProxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: aiStreamingText) {
                    withAnimation {
                        scrollViewProxy.scrollTo("aiTypingIndicator", anchor: .bottom)
                    }
                }
                .onChange(of: isAITyping) { _, newValue in
                    if newValue == false, let last = channelMessages.last {
                        withAnimation {
                            scrollViewProxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                newMessage = suggestion
                            } label: {
                                Text(suggestion)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Color(.systemGray5))
                                    .foregroundColor(.primary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                .background(Color(.systemBackground).shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: -1))
            }
            
            Divider()
            
            // Input Bar
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
                
                TextField(String(localized: "Type a message..."), text: $newMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                
                if imageData != nil {
                    Button {
                        newMessage = "Analyze this photo for route/safety tips"
                        sendMessage()
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
                .disabled(newMessage.isEmpty && imageData == nil)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhoto) { oldValue, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                    imageData = data
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !newMessage.isEmpty || imageData != nil else { return }
        let message = ChatMessage(
            content: newMessage,
            senderId: "user-\(UUID().uuidString.prefix(8))",
            senderName: "Driver",
            channelId: channel.id.uuidString
        )
        
        message.imageData = imageData
        
        modelContext.insert(message)
        newMessage = ""
        imageData = nil
        selectedPhoto = nil
        
        triggerAI(for: message)
    }
    
    private func triggerAI(for userMessage: ChatMessage) {
        isAITyping = true
        aiStreamingText = ""
        suggestions = []
        
        let context = channelMessages
            .filter { !$0.content.isEmpty && $0.imageData == nil }
            .suffix(10)
            .map { $0.content }
        
        Task {
            do {
                for try await chunk in ai.streamResponse(to: userMessage.content, context: context) {
                    aiStreamingText.append(chunk)
                }
                
                let aiMessage = ChatMessage(
                    content: aiStreamingText,
                    senderId: "assistant",
                    senderName: "Easy AI",
                    channelId: channel.id.uuidString
                )
                modelContext.insert(aiMessage)
                
                isAITyping = false
                
                suggestions = await ai.suggestedReplies(for: userMessage.content, context: context)
            } catch {
                let fallbackMessage = ChatMessage(
                    content: "AI unavailable right now. Check connection/API key and try again.",
                    senderId: "assistant",
                    senderName: "Easy AI",
                    channelId: channel.id.uuidString
                )
                modelContext.insert(fallbackMessage)
                isAITyping = false
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var isCurrentUser: Bool {
        message.senderId != "assistant"
    }
    
    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 6) {
                if !isCurrentUser {
                    HStack(spacing: 4) {
                        Image(systemName: "robot")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(message.senderName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .hidden()
                        .accessibility(hidden: true)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.body)
                    }
                    
                    if let imageData = message.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200)
                            .cornerRadius(8)
                    }
                }
                .padding(12)
                .background(isCurrentUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(isCurrentUser ? .white : .primary)
                .cornerRadius(16)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 280, alignment: isCurrentUser ? .trailing : .leading)
            
            if !isCurrentUser {
                Spacer()
            }
        }
    }
}

struct AIResponseBubble: View {
    let text: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "robot")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Easy AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .center, spacing: 8) {
                    ChatTypingIndicator()
                    Text(text)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .opacity(0.7)
                    Spacer()
                }
                .padding(12)
                .background(Color(.systemGray5))
                .cornerRadius(16)
            }
            .frame(maxWidth: 280, alignment: .leading)
            
            Spacer()
        }
    }
}

struct ChatTypingIndicator: View {
    @State private var phase: Int = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

struct NewChannelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var category = "general"

    private let categoryOptions: [(String, String, String)] = [
        ("general",  "bubble.left.and.bubble.right.fill", "Geral"),
        ("routes",   "road.lanes",                        "Rotas"),
        ("safety",   "shield.fill",                       "Segurança"),
        ("regional", "map.fill",                          "Regional"),
        ("help",     "questionmark.circle.fill",          "Ajuda")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0d1117").ignoresSafeArea()
                VStack(spacing: 24) {

                    // Room name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOME DA SALA")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.4))
                            .kerning(1.2)
                        TextField("Ex: I-10 Texas Drivers", text: $name)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESCRIÇÃO (OPCIONAL)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.4))
                            .kerning(1.2)
                        TextField("Do que trata essa sala?", text: $description)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }

                    // Category picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CATEGORIA")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.4))
                            .kerning(1.2)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(categoryOptions, id: \.0) { id, icon, label in
                                Button(action: { category = id }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: icon)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(category == id ? .white : Color.white.opacity(0.4))
                                        Text(label)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(category == id ? .white : Color.white.opacity(0.35))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(category == id ? Color(hex: "#c9a84c").opacity(0.25) : Color.white.opacity(0.06))
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(category == id ? Color(hex: "#c9a84c").opacity(0.6) : Color.clear, lineWidth: 1.5))
                                }
                            }
                        }
                    }

                    Spacer()

                    Button(action: saveChannel) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Criar Sala")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(name.isEmpty ? Color.white.opacity(0.12) : Color(hex: "#c9a84c"))
                        .cornerRadius(14)
                    }
                    .disabled(name.isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("Nova Sala de Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "#0d1117"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .foregroundColor(Color.white.opacity(0.5))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveChannel() {
        guard !name.isEmpty else { return }
        let channel = ChatChannel(name: name, description: description, category: category)
        modelContext.insert(channel)
        dismiss()
    }
}

#Preview {
    ChatView()
        .modelContainer(for: [ChatChannel.self, ChatMessage.self], inMemory: true)
}
