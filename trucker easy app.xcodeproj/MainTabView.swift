//
//  MainTabView.swift
//  Trucker Easy
//
//  Main tab bar navigation with 4 tabs
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: My Horizon (Map & Navigation)
            MyHorizonView()
                .tabItem {
                    Label("My Horizon", systemImage: "map.fill")
                }
                .tag(0)
            
            // Tab 2: My Check-up (Health & Wellness)
            MyCheckupView()
                .tabItem {
                    Label("My Check-up", systemImage: "heart.fill")
                }
                .tag(1)
            
            // Tab 3: My Cabin (Documents & Insurance)
            MyCabinView()
                .tabItem {
                    Label("My Cabin", systemImage: "folder.fill")
                }
                .tag(2)
            
            // Tab 4: Road Talk (Community & News)
            RoadTalkView()
                .tabItem {
                    Label("Road Talk", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(3)
        }
        .tint(Color("TruckerOrange"))
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(LocationManager())
        .environmentObject(SupabaseManager())
}
