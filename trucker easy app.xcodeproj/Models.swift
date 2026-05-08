//
//  Models.swift
//  Trucker Easy
//
//  Core data models
//

import Foundation
import MapKit

// MARK: - Truck Route
struct TruckRoute: Identifiable, Codable {
    let id: UUID
    let destinationName: String
    let destination: CLLocationCoordinate2D
    let distance: String
    let estimatedTime: String
    let polyline: MKPolyline
    let truckRestrictions: TruckRestrictions
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        destinationName: String,
        destination: CLLocationCoordinate2D,
        distance: String,
        estimatedTime: String,
        polyline: MKPolyline,
        truckRestrictions: TruckRestrictions,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.destinationName = destinationName
        self.destination = destination
        self.distance = distance
        self.estimatedTime = estimatedTime
        self.polyline = polyline
        self.truckRestrictions = truckRestrictions
        self.createdAt = createdAt
    }
}

struct TruckRestrictions: Codable {
    var weight: Double // in pounds
    var height: Double // in feet
    var width: Double? // in feet
    var length: Double? // in feet
    var hazmat: Bool
    
    init(
        weight: Double = 80000,
        height: Double = 13.6,
        width: Double? = nil,
        length: Double? = nil,
        hazmat: Bool = false
    ) {
        self.weight = weight
        self.height = height
        self.width = width
        self.length = length
        self.hazmat = hazmat
    }
}

// MARK: - Community Alert
struct CommunityAlert: Identifiable, Codable {
    let id: UUID
    let type: AlertType
    let coordinate: CLLocationCoordinate2D
    let reportedBy: String
    let reportedAt: Date
    var confirmations: Int
    
    enum AlertType: String, Codable, CaseIterable {
        case weigh = "Weigh Station"
        case police = "Police"
        case accident = "Accident"
        case construction = "Construction"
        case hazard = "Hazard"
        
        var icon: String {
            switch self {
            case .weigh: return "scalemass.fill"
            case .police: return "exclamationmark.shield.fill"
            case .accident: return "car.2.fill"
            case .construction: return "cone.fill"
            case .hazard: return "exclamationmark.triangle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .weigh: return .blue
            case .police: return .red
            case .accident: return .orange
            case .construction: return .yellow
            case .hazard: return .purple
            }
        }
    }
}

// MARK: - Medication
struct Medication: Identifiable, Codable {
    let id: UUID
    var name: String
    var time: Date
    var repeatDaily: Bool
    var lastTaken: Date?
    
    init(
        id: UUID = UUID(),
        name: String,
        time: Date,
        repeatDaily: Bool = true,
        lastTaken: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.time = time
        self.repeatDaily = repeatDaily
        self.lastTaken = lastTaken
    }
    
    var timeFormatted: String {
        time.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Food Suggestion
struct FoodSuggestion: Identifiable, Codable {
    let id: UUID
    let locationName: String
    let coordinate: CLLocationCoordinate2D
    let recommendation: String
    let avoidItems: [String]
    let healthProfile: String
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        locationName: String,
        coordinate: CLLocationCoordinate2D,
        recommendation: String,
        avoidItems: [String] = [],
        healthProfile: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.locationName = locationName
        self.coordinate = coordinate
        self.recommendation = recommendation
        self.avoidItems = avoidItems
        self.healthProfile = healthProfile
        self.createdAt = createdAt
    }
}

// MARK: - Document
struct Document: Identifiable, Codable {
    let id: UUID
    var type: DocumentType
    var expirationDate: Date?
    var imageData: Data?
    var uploadedAt: Date
    
    init(
        id: UUID = UUID(),
        type: DocumentType,
        expirationDate: Date? = nil,
        imageData: Data? = nil,
        uploadedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.expirationDate = expirationDate
        self.imageData = imageData
        self.uploadedAt = uploadedAt
    }
    
    var statusColor: Color {
        guard let expirationDate = expirationDate else {
            return .orange
        }
        
        let daysUntilExpiration = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
        
        if daysUntilExpiration < 0 {
            return .red // Expired
        } else if daysUntilExpiration <= 30 {
            return .orange // Expiring soon
        } else {
            return .green // Valid
        }
    }
    
    var statusIcon: String {
        guard let expirationDate = expirationDate else {
            return "exclamationmark.triangle.fill"
        }
        
        let daysUntilExpiration = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
        
        if daysUntilExpiration < 0 {
            return "xmark.circle.fill"
        } else if daysUntilExpiration <= 30 {
            return "exclamationmark.circle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    var statusMessage: String {
        guard let expirationDate = expirationDate else {
            return "No expiration set"
        }
        
        let daysUntilExpiration = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
        
        if daysUntilExpiration < 0 {
            return "EXPIRED - Renew immediately"
        } else if daysUntilExpiration == 0 {
            return "Expires TODAY"
        } else if daysUntilExpiration <= 7 {
            return "Expires in \(daysUntilExpiration) days"
        } else if daysUntilExpiration <= 30 {
            return "Expiring soon (\(daysUntilExpiration) days)"
        } else {
            return "Valid for \(daysUntilExpiration) days"
        }
    }
}

enum DocumentType: String, Codable, CaseIterable, Identifiable {
    case cdl = "Commercial Driver's License"
    case medicalCard = "Medical Card"
    case dotPhysical = "DOT Physical"
    case truckInsurance = "Truck Insurance"
    case trailerInsurance = "Trailer Insurance"
    case registration = "Vehicle Registration"
    
    var id: String { rawValue }
}

// MARK: - News Article
struct NewsArticle: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String?
    let url: URL
    let imageURL: URL?
    let source: String
    let publishedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        url: URL,
        imageURL: URL? = nil,
        source: String,
        publishedAt: Date
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.imageURL = imageURL
        self.source = source
        self.publishedAt = publishedAt
    }
}

// MARK: - Chat Message
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var text: String
    var isUser: Bool
    var timestamp: Date
    
    init(
        id: UUID = UUID(),
        text: String,
        isUser: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

// MARK: - Codable Extensions for CoreLocation
extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
        let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
        self.init(latitude: latitude, longitude: longitude)
    }
}

extension MKPolyline: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case coordinates
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let coordinates = self.coordinates()
        try container.encode(coordinates, forKey: .coordinates)
    }
    
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coordinates = try container.decode([CLLocationCoordinate2D].self, forKey: .coordinates)
        self.init(coordinates: coordinates, count: coordinates.count)
    }
    
    func coordinates() -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

import SwiftUI
extension Color {
    init(_ name: String) {
        self.init(name)
    }
}
