//
//  NavigationArrowView.swift
//  trucker easy app
//
//  3D NAVIGATION ARROW - FIXED VERSION

import SwiftUI
import MapKit
import CoreLocation

struct NavigationArrowAnnotation: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
    var heading: CLLocationDirection
    var speed: CLLocationSpeed
}

struct NavigationArrowView: View {
    let annotation: NavigationArrowAnnotation
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(0.4),
                            Color.cyan.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 15,
                        endRadius: 30
                    )
                )
                .frame(width: 60, height: 60)
            
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, Color.cyan],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .rotationEffect(.degrees(annotation.heading))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: annotation.heading)
            
            if annotation.speed > 1 {
                Circle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: 35, height: 35)
                    .te_uniformScale(annotation.speed > 5 ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: annotation.speed)
            }
        }
    }
}

struct NavigationArrowMapAnnotationView: View {
    let annotation: NavigationArrowAnnotation
    
    var body: some View {
        NavigationArrowView(annotation: annotation)
            .frame(width: 60, height: 60)
    }
}

@Observable
@MainActor
class MapCameraController {
    var position: MapCameraPosition = .automatic
    var followsUserWithHeading: Bool = true
    var pitch: Double = 60
    var distance: CLLocationDistance = 500
    
    func updateCamera(location: CLLocation, heading: CLLocationDirection) {
        guard followsUserWithHeading else {
            position = .automatic
            return
        }
        
        let speed = location.speed
        if speed > 0 {
            if speed > 25 {
                distance = 1000
            } else if speed > 15 {
                distance = 700
            } else if speed > 8 {
                distance = 500
            } else {
                distance = 300
            }
        }
        
        position = .camera(
            MapCamera(
                centerCoordinate: location.coordinate,
                distance: distance,
                heading: heading,
                pitch: pitch
            )
        )
    }
    
    func resetToAutomatic() {
        followsUserWithHeading = false
        position = .automatic
    }
    
    func startFollowing() {
        followsUserWithHeading = true
    }
}

