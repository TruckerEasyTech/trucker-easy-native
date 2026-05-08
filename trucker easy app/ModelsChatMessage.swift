//
//  ChatMessage.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 3/1/26.
//

import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID
    var content: String
    var senderId: String
    var senderName: String
    var timestamp: Date
    var channelId: String
    var isRead: Bool
    var imageData: Data?
    
    init(content: String,
         senderId: String,
         senderName: String,
         channelId: String) {
        self.id = UUID()
        self.content = content
        self.senderId = senderId
        self.senderName = senderName
        self.timestamp = Date()
        self.channelId = channelId
        self.isRead = false
    }
}

@Model
final class ChatChannel {
    var id: UUID
    var name: String
    var channelDescription: String
    var createdDate: Date
    var category: String // general, help, regional, etc.
    var memberCount: Int
    var isActive: Bool
    
    init(name: String,
         description: String,
         category: String = "general") {
        self.id = UUID()
        self.name = name
        self.channelDescription = description
        self.category = category
        self.createdDate = Date()
        self.memberCount = 0
        self.isActive = true
    }
}
