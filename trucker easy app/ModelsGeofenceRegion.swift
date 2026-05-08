//
//  GeofenceRegion.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 3/1/26.
//

import Foundation
import CoreLocation
import SwiftData

@Model
final class GeofenceRegion {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double // in meters
    var isActive: Bool
    var notifyOnEntry: Bool
    var notifyOnExit: Bool
    var createdDate: Date
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var circularRegion: CLCircularRegion {
        let region = CLCircularRegion(
            center: coordinate,
            radius: radius,
            identifier: id.uuidString
        )
        region.notifyOnEntry = notifyOnEntry
        region.notifyOnExit = notifyOnExit
        return region
    }
    
    init(name: String,
         latitude: Double,
         longitude: Double,
         radius: Double = 1000,
         notifyOnEntry: Bool = true,
         notifyOnExit: Bool = true) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.isActive = true
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.createdDate = Date()
    }
}
