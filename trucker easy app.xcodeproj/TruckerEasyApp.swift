//
//  TruckerEasyApp.swift
//  Trucker Easy - Driver to Driver
//
//  Super App for Truck Drivers
//  Focus: Heavy Load Navigation, Wellness & Document Management
//

import SwiftUI

@main
struct TruckerEasyApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var supabaseManager = SupabaseManager()
    
    var body: some Scene {
        WindowGroup {
            if appState.isSubscribed || appState.isInTrial {
                MainTabView()
                    .environmentObject(appState)
                    .environmentObject(locationManager)
                    .environmentObject(supabaseManager)
            } else {
                CheckoutView()
                    .environmentObject(appState)
                    .environmentObject(supabaseManager)
            }
        }
    }
}
