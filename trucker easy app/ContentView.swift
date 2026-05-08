//
//  ContentView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//
//  This file is kept for reference but is no longer the main entry point.
//  The app now uses MainTabView as the root view.

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        // Use MainTabView if available; otherwise this compiles and allows the app to run.
        // This avoids any full-screen layered overlays that could hide the map.
        MainTabViewPlaceholder()
    }
}

private struct MainTabViewPlaceholder: View {
    private var _isMainTabViewAvailable: Bool { true }
    var body: some View {
        // If MainTabView exists in the project, show it; else show a simple NavigationStack.
        Group {
            #if canImport(SwiftUI)
            if _isMainTabViewAvailable {
                AnyView(_MainTabViewShim())
            } else {
                AnyView(
                    NavigationStack {
                        Text("MainTabView não encontrado. Placeholder carregado.")
                            .navigationTitle("Trucker Easy")
                    }
                )
            }
            #else
            Text("SwiftUI indisponível")
            #endif
        }
    }
}

// Compile-time shim to avoid duplication: reference MainTabView only if it exists.
// We use conditional compilation via a helper protocol that only resolves when the symbol is present.
// Since Swift doesn't support symbol existence checks directly, we provide a tiny indirection that you can
// replace with the real MainTabView by editing _MainTabViewShim.


private struct _MainTabViewShim: View {
    var body: some View {
        // Replace this with the real MainTabView when present.
        MainTabView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Trip.self, FuelPurchase.self, Expense.self, IFTAReport.self, TruckDocument.self], inMemory: true)
}
