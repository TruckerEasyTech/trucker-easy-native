//
//  IFTAReport.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import Foundation
import SwiftData

@Model
final class IFTAReport {
    var id: UUID
    var quarterStartDate: Date
    var quarterEndDate: Date
    var generatedDate: Date
    var totalMiles: Double
    var totalGallons: Double
    var totalFuelCost: Double
    var stateBreakdownData: Data? // JSON data for state-by-state breakdown
    
    var averageMPG: Double {
        guard totalGallons > 0 else { return 0 }
        return totalMiles / totalGallons
    }
    
    init(quarterStartDate: Date,
         quarterEndDate: Date,
         totalMiles: Double = 0,
         totalGallons: Double = 0,
         totalFuelCost: Double = 0) {
        self.id = UUID()
        self.quarterStartDate = quarterStartDate
        self.quarterEndDate = quarterEndDate
        self.generatedDate = Date()
        self.totalMiles = totalMiles
        self.totalGallons = totalGallons
        self.totalFuelCost = totalFuelCost
    }
}

struct StateBreakdown: Codable, Identifiable {
    var id = UUID()
    let state: String
    let miles: Double
    let gallons: Double
    let fuelCost: Double
    
    var averageMPG: Double {
        guard gallons > 0 else { return 0 }
        return miles / gallons
    }
}
