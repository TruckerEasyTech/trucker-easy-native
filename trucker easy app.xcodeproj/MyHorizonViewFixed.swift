//
//  MyHorizonView.swift
//  Trucker Easy
//
//  MAPA 3D GLOBO FUNCIONANDO - 100% NATIVO iOS
//

import SwiftUI
import MapKit
import CoreLocation

struct MyHorizonView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var mapViewModel = MapViewModel()
    @State private var showLoadSheet = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var activeRoute: TruckRoute?
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // MAPA 3D FUNCIONANDO!
            Map(position: $cameraPosition) {
                // Localização atual (ponto azul)
                if let location = locationManager.currentLocation {
                    Annotation("You", coordinate: location) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 50, height: 50)
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
                
                // Rota ativa
                if let route = activeRoute {
                    MapPolyline(route.polyline)
                        .stroke(Color.orange, lineWidth: 6)
                    
                    Marker("Delivery", coordinate: route.destination)
                        .tint(.red)
                }
                
                // Alertas da comunidade
                ForEach(mapViewModel.communityAlerts) { alert in
                    Annotation(alert.type.rawValue, coordinate: alert.coordinate) {
                        AlertMarker(
                            alert: alert,
                            onConfirm: { mapViewModel.confirmAlert(alert) },
                            onDismiss: { mapViewModel.dismissAlert(alert) }
                        )
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic)) // 3D TERRENO!
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapPitchToggle()
            }
            .ignoresSafeArea()
            .onAppear {
                locationManager.requestPermission()
                mapViewModel.loadMockAlerts()
                
                // Centralizar no usuário
                if let location = locationManager.currentLocation {
                    cameraPosition = .camera(MapCamera(
                        centerCoordinate: location,
                        distance: 5000,
                        heading: 0,
                        pitch: 60 // INCLINAÇÃO 3D!
                    ))
                }
            }
            
            // Botão "Got Load?"
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showLoadSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "truck.box.fill")
                            Text("Got Load?")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(30)
                        .shadow(radius: 8)
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
            
            // Bottom Sheet
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    // Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray)
                        .frame(width: 40, height: 6)
                        .padding(.top, 8)
                    
                    if let route = activeRoute {
                        ActiveRouteView(route: route)
                    } else {
                        ReadyToStartView()
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .shadow(radius: 10)
            }
        }
        .sheet(isPresented: $showLoadSheet) {
            LoadInputSheet { route in
                activeRoute = route
                showLoadSheet = false
            }
        }
    }
}

// Marcador de alerta com botão X grande
struct AlertMarker: View {
    let alert: CommunityAlert
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    @State private var showActions = false
    
    var body: some View {
        Button {
            showActions.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(alert.type.color.opacity(0.9))
                    .frame(width: 50, height: 50)
                
                Image(systemName: alert.type.icon)
                    .font(.title3)
                    .foregroundColor(.white)
            }
        }
        .popover(isPresented: $showActions) {
            VStack(spacing: 20) {
                Text(alert.type.rawValue)
                    .font(.headline)
                
                HStack(spacing: 20) {
                    // Botão X GRANDE para deletar
                    Button {
                        onDismiss()
                        showActions = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 60, height: 60)
                            Image(systemName: "xmark")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Botão confirmar
                    Button {
                        onConfirm()
                        showActions = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 60, height: 60)
                            Image(systemName: "checkmark")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct ActiveRouteView: View {
    let route: TruckRoute
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Trip")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                VStack(alignment: .leading) {
                    Text(route.destinationName)
                        .font(.headline)
                    Text("\(route.distance) mi • \(route.estimatedTime)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding()
    }
}

struct ReadyToStartView: View {
    var body: some View {
        VStack {
            Text("Ready to roll")
                .font(.headline)
            Text("Tap 'Got Load?' to start your trip")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// Extension para corner radius customizado
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    MyHorizonView()
}
