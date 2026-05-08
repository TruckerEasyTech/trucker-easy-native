//
//  CompetitiveFeatures.swift
//  Trucker Easy
//
//  Análise do Trucker Path e funcionalidades adicionais
//  Referência: truckerpath.com
//

import SwiftUI
import MapKit

// MARK: - Truck Stop Finder (inspirado no Trucker Path)
struct TruckStopFinder: View {
    @StateObject private var viewModel = TruckStopViewModel()
    @State private var searchRadius: Double = 50 // milhas
    @State private var showFilters = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Filtros rápidos
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FilterChip(title: "Fuel", icon: "fuelpump.fill", isSelected: viewModel.showFuel)
                    FilterChip(title: "Parking", icon: "parkingsign", isSelected: viewModel.showParking)
                    FilterChip(title: "Scales", icon: "scalemass.fill", isSelected: viewModel.showScales)
                    FilterChip(title: "Repair", icon: "wrench.fill", isSelected: viewModel.showRepair)
                    FilterChip(title: "WiFi", icon: "wifi", isSelected: viewModel.showWifi)
                    FilterChip(title: "Showers", icon: "shower.fill", isSelected: viewModel.showShowers)
                    FilterChip(title: "Restaurants", icon: "fork.knife", isSelected: viewModel.showFood)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
            
            // Lista de truck stops
            List {
                ForEach(viewModel.nearbyStops) { stop in
                    TruckStopCard(stop: stop)
                }
            }
            .listStyle(.plain)
        }
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color("TruckerOrange") : Color(UIColor.systemGray5))
        .foregroundColor(isSelected ? .white : .primary)
        .cornerRadius(20)
    }
}

struct TruckStopCard: View {
    let stop: TruckStop
    
    var body: some View {
        HStack(spacing: 12) {
            // Logo/Ícone
            ZStack {
                Circle()
                    .fill(Color("TruckerOrange").opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: stop.type.icon)
                    .font(.title3)
                    .foregroundColor(Color("TruckerOrange"))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    // Distância
                    Label("\(stop.distance) mi", systemImage: "location.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Rating
                    if let rating = stop.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Amenidades
                    if stop.hasParking {
                        Image(systemName: "parkingsign")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if stop.hasFuel {
                        Image(systemName: "fuelpump.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            // Navegação rápida
            Button {
                // Iniciar navegação para este truck stop
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color("TruckerOrange"))
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Fuel Price Comparison (como Trucker Path)
struct FuelPriceView: View {
    @StateObject private var viewModel = FuelPriceViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Lowest Fuel Price")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("$\(viewModel.lowestPrice, specifier: "%.2f")/gal")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Average")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(viewModel.averagePrice, specifier: "%.2f")")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 4)
            
            // Lista de postos por preço
            ForEach(viewModel.fuelStops) { station in
                FuelStationRow(station: station)
            }
        }
    }
}

struct FuelStationRow: View {
    let station: FuelStation
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.headline)
                
                Text("\(station.distance) mi away")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("$\(station.price, specifier: "%.2f")")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(station.isCheapest ? .green : .primary)
                
                Text(station.lastUpdated)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Weather Overlay (faltava!)
struct WeatherOverlay: View {
    @StateObject private var weatherViewModel = WeatherViewModel()
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Ícone do clima
                Image(systemName: weatherViewModel.weatherIcon)
                    .font(.title)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(weatherViewModel.temperature)°F")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(weatherViewModel.condition)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
                
                // Alertas meteorológicos
                if weatherViewModel.hasAlert {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Alert")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Parking Availability (real-time como Trucker Path)
struct ParkingAvailability: View {
    let truckStop: TruckStop
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parking Availability")
                .font(.headline)
            
            HStack(spacing: 16) {
                ParkingIndicator(
                    available: truckStop.spotsAvailable,
                    total: truckStop.totalSpots,
                    type: "Regular"
                )
                
                ParkingIndicator(
                    available: truckStop.reservedSpotsAvailable,
                    total: truckStop.totalReservedSpots,
                    type: "Reserved"
                )
            }
            
            // Última atualização
            Text("Updated \(truckStop.lastParkingUpdate)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
}

struct ParkingIndicator: View {
    let available: Int
    let total: Int
    let type: String
    
    var percentageFull: Double {
        1.0 - (Double(available) / Double(total))
    }
    
    var color: Color {
        if percentageFull < 0.5 { return .green }
        else if percentageFull < 0.8 { return .orange }
        else { return .red }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: percentageFull)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                Text("\(available)")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            Text(type)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(available) of \(total)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Trip Planner (inspirado no Trucker Path Pro)
struct TripPlanner: View {
    @StateObject private var viewModel = TripPlannerViewModel()
    @State private var showStopSelector = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Origem e Destino
                VStack(spacing: 12) {
                    TripLocationRow(
                        icon: "circle.fill",
                        title: "Origin",
                        location: viewModel.origin,
                        color: .green
                    )
                    
                    TripLocationRow(
                        icon: "mappin.circle.fill",
                        title: "Destination",
                        location: viewModel.destination,
                        color: .red
                    )
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8)
                
                // Resumo da viagem
                HStack(spacing: 20) {
                    TripStat(title: "Distance", value: "\(viewModel.totalDistance) mi")
                    TripStat(title: "Time", value: viewModel.estimatedTime)
                    TripStat(title: "Stops", value: "\(viewModel.plannedStops.count)")
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                .cornerRadius(16)
                
                // Paradas planejadas
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Planned Stops")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button {
                            showStopSelector = true
                        } label: {
                            Label("Add Stop", systemImage: "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(Color("TruckerOrange"))
                        }
                    }
                    
                    ForEach(viewModel.plannedStops) { stop in
                        PlannedStopRow(stop: stop)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                .cornerRadius(16)
                
                Spacer()
                
                // Botão começar viagem
                Button {
                    viewModel.startTrip()
                } label: {
                    Text("Start Trip")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color("TruckerOrange"), Color("TruckerOrange").opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color("TruckerOrange").opacity(0.3), radius: 8)
                }
            }
            .padding()
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Trip Planner")
        }
    }
}

struct TripLocationRow: View {
    let icon: String
    let title: String
    let location: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(location)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
    }
}

struct TripStat: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PlannedStopRow: View {
    let stop: PlannedStop
    
    var body: some View {
        HStack {
            Image(systemName: stop.icon)
                .font(.title3)
                .foregroundColor(Color("TruckerOrange"))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(stop.purpose)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(stop.eta)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Models para novas features

struct TruckStop: Identifiable, Codable {
    let id: UUID
    let name: String
    let type: TruckStopType
    let coordinate: CLLocationCoordinate2D
    let distance: Double // em milhas
    let rating: Double?
    let hasParking: Bool
    let hasFuel: Bool
    let hasShowers: Bool
    let hasWifi: Bool
    let hasFood: Bool
    let hasRepair: Bool
    let hasScales: Bool
    let spotsAvailable: Int
    let totalSpots: Int
    let reservedSpotsAvailable: Int
    let totalReservedSpots: Int
    let lastParkingUpdate: String
    
    enum TruckStopType: String, Codable {
        case truckStop = "Truck Stop"
        case restArea = "Rest Area"
        case fuelStation = "Fuel Station"
        case parkingLot = "Parking Lot"
        
        var icon: String {
            switch self {
            case .truckStop: return "building.2.fill"
            case .restArea: return "parkingsign"
            case .fuelStation: return "fuelpump.fill"
            case .parkingLot: return "parkingsign.circle.fill"
            }
        }
    }
}

struct FuelStation: Identifiable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distance: Double
    let price: Double
    let lastUpdated: String
    let isCheapest: Bool
}

struct PlannedStop: Identifiable {
    let id: UUID
    let name: String
    let purpose: String // "Fuel", "Rest", "Food", etc.
    let eta: String
    let icon: String
}

// MARK: - ViewModels para novas features

@MainActor
class TruckStopViewModel: ObservableObject {
    @Published var nearbyStops: [TruckStop] = []
    @Published var showFuel = true
    @Published var showParking = true
    @Published var showScales = false
    @Published var showRepair = false
    @Published var showWifi = false
    @Published var showShowers = false
    @Published var showFood = false
    
    func loadNearbyStops() {
        // Implementar busca de truck stops próximos
    }
}

@MainActor
class FuelPriceViewModel: ObservableObject {
    @Published var fuelStops: [FuelStation] = []
    @Published var lowestPrice: Double = 0.0
    @Published var averagePrice: Double = 0.0
    
    func loadFuelPrices() {
        // Implementar busca de preços de combustível
    }
}

@MainActor
class WeatherViewModel: ObservableObject {
    @Published var temperature: Int = 72
    @Published var condition: String = "Partly Cloudy"
    @Published var weatherIcon: String = "cloud.sun.fill"
    @Published var hasAlert: Bool = false
    
    func updateWeather(for coordinate: CLLocationCoordinate2D) {
        // Implementar API de clima
    }
}

@MainActor
class TripPlannerViewModel: ObservableObject {
    @Published var origin: String = "Current Location"
    @Published var destination: String = "Select Destination"
    @Published var totalDistance: Int = 0
    @Published var estimatedTime: String = "0h 0m"
    @Published var plannedStops: [PlannedStop] = []
    
    func startTrip() {
        // Iniciar navegação da viagem planejada
    }
}
