//
//  Expense.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import Foundation
import SwiftData

enum ExpenseCategory: String, Codable, CaseIterable {
    case fuel = "Fuel"
    case maintenance = "Maintenance"
    case tolls = "Tolls"
    case parking = "Parking"
    case food = "Food"
    case lodging = "Lodging"
    case insurance = "Insurance"
    case permits = "Permits"
    case other = "Other"
}

@Model
final class Expense {
    var id: UUID
    var date: Date
    var categoryRaw: String
    var amount: Double
    var vendorName: String
    var notes: String
    var receiptImageData: Data?
    var location: String
    
    var trip: Trip?
    
    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    
    init(date: Date = Date(),
         category: ExpenseCategory = .other,
         amount: Double = 0,
         vendorName: String = "",
         notes: String = "",
         location: String = "") {
        self.id = UUID()
        self.date = date
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.vendorName = vendorName
        self.notes = notes
        self.location = location
    }
}
