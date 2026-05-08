//
//  CommunityPost.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 3/1/26.
//

import Foundation
import SwiftData

enum PostCategory: String, Codable, CaseIterable {
    case general = "General"
    case advice = "Advice"
    case routes = "Routes"
    case safety = "Safety"
    case mechanical = "Mechanical"
    case regulations = "Regulations"
    case social = "Social"
}

@Model
final class CommunityPost {
    var id: UUID
    var remoteID: String?
    var title: String
    var content: String
    var authorId: String
    var authorName: String
    var createdDate: Date
    var categoryRaw: String
    var likeCount: Int
    var commentCount: Int
    var imageData: Data?
    var location: String?
    
    var category: PostCategory {
        get { PostCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }
    
    init(title: String,
         content: String,
         authorId: String,
         authorName: String,
         category: PostCategory = .general,
         remoteID: String? = nil,
         location: String? = nil) {
        self.id = UUID()
        self.remoteID = remoteID
        self.title = title
        self.content = content
        self.authorId = authorId
        self.authorName = authorName
        self.categoryRaw = category.rawValue
        self.createdDate = Date()
        self.likeCount = 0
        self.commentCount = 0
        self.location = location
    }
}

@Model
final class PostComment {
    var id: UUID
    var remoteID: String?
    var postId: UUID
    var content: String
    var authorId: String
    var authorName: String
    var createdDate: Date
    
    init(postId: UUID,
         content: String,
         authorId: String,
         authorName: String,
         remoteID: String? = nil) {
        self.id = UUID()
        self.remoteID = remoteID
        self.postId = postId
        self.content = content
        self.authorId = authorId
        self.authorName = authorName
        self.createdDate = Date()
    }
}
