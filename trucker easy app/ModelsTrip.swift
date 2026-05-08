//
//  Trip.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import Foundation
import SwiftData

@Model
final class Trip {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var startLocation: String
    var endLocation: String?
    var startOdometer: Double
    var endOdometer: Double?
    var truckNumber: String
    var notes: String
    var isActive: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \FuelPurchase.trip)
    var fuelPurchases: [FuelPurchase]
    
    @Relationship(deleteRule: .cascade, inverse: \Expense.trip)
    var expenses: [Expense]
    
    var totalMiles: Double {
        guard let endOdometer = endOdometer else { return 0 }
        return endOdometer - startOdometer
    }
    
    var totalFuelCost: Double {
        fuelPurchases.reduce(0) { $0 + $1.totalCost }
    }
    
    var totalExpenses: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }
    
    init(startDate: Date = Date(),
         startLocation: String = "",
         startOdometer: Double = 0,
         truckNumber: String = "",
         notes: String = "") {
        self.id = UUID()
        self.startDate = startDate
        self.startLocation = startLocation
        self.startOdometer = startOdometer
        self.truckNumber = truckNumber
        self.notes = notes
        self.isActive = true
        self.fuelPurchases = []
        self.expenses = []
    }
}
