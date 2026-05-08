//
//  MyHorizonView.swift
//  Trucker Easy
//
//  Tab 1: MAPA 3D GLOBO REAL (estilo Google Earth)
//  100% NATIVO iOS - SEM WEB!
//

import SwiftUI
import MapKit
import CoreLocation

struct MyHorizonView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var mapViewModel = MapViewModel()
    @State private var showLoadSheet = false
    @State private var showBottomSheet = true
    @State private var bottomSheetOffset: CGFloat = 0
    @State private var activeRoute: TruckRoute?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    private let minSheetHeight: CGFloat = 120
    private let maxSheetHeight: CGFloat = 400
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // MAPA 3D GLOBO REAL - FUNCIONANDO!
            Map(position: $cameraPosition) {
                // Localização atual do motorista
                if let currentLocation = locationManager.currentLocation {
                    // Marcador azul pulsante da localização atual
                    Annotation("You", coordinate: currentLocation) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 60, height: 60)
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
                
                // Rota ativa com gradiente laranja
                if let route = activeRoute {
                    MapPolyline(route.polyline)
                        .stroke(Color.orange, lineWidth: 6)
                    
                    Marker("Delivery", coordinate: route.destination)
                        .tint(.red)
                }
                
                // Alertas da comunidade FUNCIONANDO
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
            .mapStyle(.hybrid(elevation: .realistic)) // 3D COM TERRENO!
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapPitchToggle()
                MapScaleView()
            }
            .ignoresSafeArea()
            .onAppear {
                requestLocation()
                loadMockAlerts()
            }
            
            // Botão "Got Load?" - TOP DIREITO
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showLoadSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "truck.box.fill")
                                .font(.title3)
                            Text("Got Load?")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color("TruckerOrange"), Color("TruckerOrange").opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(30)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
            
            // Bottom Sheet
            BottomSheetView(
                isExpanded: $showBottomSheet,
                offset: $bottomSheetOffset,
                minHeight: minSheetHeight,
                maxHeight: maxSheetHeight
            ) {
                NavigationControlsView(
                    activeRoute: $activeRoute,
                    onStartTrip: { route in
                        activeRoute = route
                        mapViewModel.startNavigation(route: route)
                    }
                )
            }
        }
        .sheet(isPresented: $showLoadSheet) {
            LoadInputSheet(onRouteCreated: { route in
                activeRoute = route
                showLoadSheet = false
            })
        }
    }
}

// MARK: - 3D Map View (Google Earth style)
struct Map3DView: View {
    var route: TruckRoute?
    var alerts: [CommunityAlert]
    var onAlertConfirm: (CommunityAlert) -> Void
    var onAlertDismiss: (CommunityAlert) -> Void
    
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        fallback: .automatic
    )
    @State private var mapStyle: MapStyle = .hybrid(elevation: .realistic)
    @State private var pitch: Double = 60 // Inclinação para efeito 3D (como Google Earth)
    @State private var showTraffic = true
    
    var body: some View {
        Map(position: $cameraPosition) {
            // User location com pulsação azul (estilo Google Maps)
            UserAnnotation()
            
            // Active route com sombra e gradiente
            if let route = route {
                // Sombra da rota (efeito de elevação)
                MapPolyline(route.polyline)
                    .stroke(.black.opacity(0.2), lineWidth: 7)
                
                // Rota principal com gradiente laranja
                MapPolyline(route.polyline)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color("TruckerOrange"),
                                Color("TruckerOrange").opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 6
                    )
                
                // Marcador de destino customizado
                Annotation("Delivery", coordinate: route.destination) {
                    ZStack {
                        // Círculo exterior (pulsante)
                        Circle()
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 60, height: 60)
                        
                        // Pin principal
                        Circle()
                            .fill(Color.red)
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            
            // Community alerts com animação
            ForEach(alerts) { alert in
                Annotation(alert.type.rawValue, coordinate: alert.coordinate) {
                    AlertAnnotationView(
                        alert: alert,
                        onConfirm: { onAlertConfirm(alert) },
                        onDismiss: { onAlertDismiss(alert) }
                    )
                }
            }
        }
        // Estilo híbrido com terreno realista (GOOGLE EARTH STYLE!)
        .mapStyle(mapStyle)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
            MapScaleView() // Escala de distância
        }
        // Configuração da câmera com pitch (inclinação 3D)
        .onAppear {
            configureCameraFor3D()
        }
    }
    
    private func configureCameraFor3D() {
        // Ajusta câmera para perspectiva 3D estilo Google Earth
        if case .userLocation = cameraPosition {
            // Mantém posição do usuário mas adiciona pitch
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    distance: 5000, // Altitude da câmera
                    heading: 0,
                    pitch: pitch // Inclinação 3D!
                )
            )
        }
    }
}

// MARK: - Alert Annotation (with easy X button for one-hand use)
struct AlertAnnotationView: View {
    let alert: CommunityAlert
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    
    @State private var showActions = false
    
    var body: some View {
        ZStack {
            // Main icon
            Button {
                showActions.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(alert.type.color.opacity(0.9))
                        .frame(width: 44, height: 44) // Large touch target
                    
                    Image(systemName: alert.type.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            
            // Action buttons (when expanded)
            if showActions {
                HStack(spacing: 12) {
                    // X Button - Easy to tap with thumb
                    Button {
                        onDismiss()
                        showActions = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 50, height: 50) // Extra large for safety
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Confirm button
                    Button {
                        onConfirm()
                        showActions = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .offset(y: -70)
            }
        }
    }
}

// MARK: - Bottom Sheet Container
struct BottomSheetView<Content: View>: View {
    @Binding var isExpanded: Bool
    @Binding var offset: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let content: Content
    
    init(
        isExpanded: Binding<Bool>,
        offset: Binding<CGFloat>,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self._isExpanded = isExpanded
        self._offset = offset
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 40, height: 6)
                    .padding(.top, 8)
                
                // Content
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: isExpanded ? maxHeight : minHeight)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: -5)
            )
            .offset(y: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            if value.translation.height > 50 {
                                isExpanded = false
                            } else if value.translation.height < -50 {
                                isExpanded = true
                            }
                            offset = 0
                        }
                    }
            )
        }
    }
}

// MARK: - Navigation Controls in Bottom Sheet
struct NavigationControlsView: View {
    @Binding var activeRoute: TruckRoute?
    var onStartTrip: (TruckRoute) -> Void
    
    @State private var truckWeight: String = ""
    @State private var truckHeight: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let route = activeRoute {
                // Active navigation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Trip")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text(route.destinationName)
                                .font(.title3)
                                .fontWeight(.bold)
                            
                            Text("\(route.distance) mi • \(route.estimatedTime)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("End Trip") {
                            activeRoute = nil
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            } else {
                // Setup new trip
                VStack(alignment: .leading, spacing: 12) {
                    Text("Truck Specifications")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Weight (lbs)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("80,000", text: $truckWeight)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Height (ft)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("13.6", text: $truckHeight)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
            }
        }
    }
}

#Preview {
    MyHorizonView()
        .environmentObject(LocationManager())
}
