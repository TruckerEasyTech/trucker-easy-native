//
//  FuelPurchase.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import Foundation
import SwiftData

@Model
final class FuelPurchase {
    var id: UUID
    var date: Date
    var location: String
    var state: String
    var gallons: Double
    var pricePerGallon: Double
    var odometer: Double
    var receiptImageData: Data?
    
    var trip: Trip?
    
    var totalCost: Double {
        gallons * pricePerGallon
    }
    
    init(date: Date = Date(),
         location: String = "",
         state: String = "",
         gallons: Double = 0,
         pricePerGallon: Double = 0,
         odometer: Double = 0) {
        self.id = UUID()
        self.date = date
        self.location = location
        self.state = state
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.odometer = odometer
    }
}
