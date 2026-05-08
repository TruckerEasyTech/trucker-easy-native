//
//  TruckDocument.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import Foundation
import SwiftData

enum DocumentType: String, Codable, CaseIterable {
    case registration = "Registration"
    case insurance = "Insurance"
    case permit = "Permit"
    case inspection = "Inspection"
    case license = "License"
    case medical = "Medical Card"
    case other = "Other"
}

@Model
final class TruckDocument {
    var id: UUID
    var name: String
    var documentTypeRaw: String
    var issueDate: Date
    var expirationDate: Date?
    var documentData: Data?
    var notes: String
    var reminderEnabled: Bool
    var reminderDaysBefore: Int
    
    var documentType: DocumentType {
        get { DocumentType(rawValue: documentTypeRaw) ?? .other }
        set { documentTypeRaw = newValue.rawValue }
    }
    
    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return expirationDate < Date()
    }
    
    var daysUntilExpiration: Int? {
        guard let expirationDate = expirationDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
        return components.day
    }
    
    init(name: String = "",
         documentType: DocumentType = .other,
         issueDate: Date = Date(),
         expirationDate: Date? = nil,
         notes: String = "",
         reminderEnabled: Bool = false,
         reminderDaysBefore: Int = 30) {
        self.id = UUID()
        self.name = name
        self.documentTypeRaw = documentType.rawValue
        self.issueDate = issueDate
        self.expirationDate = expirationDate
        self.notes = notes
        self.reminderEnabled = reminderEnabled
        self.reminderDaysBefore = reminderDaysBefore
    }
}
