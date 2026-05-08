//
//  LoadInputSheet.swift
//  Trucker Easy
//
//  "Got Load?" - Quick clipboard parsing with Regex
//

import SwiftUI

struct LoadInputSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = LoadInputViewModel()
    var onRouteCreated: (TruckRoute) -> Void
    
    @State private var pastedText = ""
    @State private var extractedAddress = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "truck.box.badge.clock.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color("TruckerOrange"))
                    
                    Text("Got Load?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Paste your load info and we'll extract the address")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                // Quick paste button
                Button {
                    pasteFromClipboard()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("Paste from Clipboard")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("TruckerOrange"))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                // Or manual input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Or type/paste here:")
                        .font(.headline)
                    
                    TextEditor(text: $pastedText)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                        .onChange(of: pastedText) { _, newValue in
                            extractAddress(from: newValue)
                        }
                }
                .padding(.horizontal)
                
                // Extracted address preview
                if !extractedAddress.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.green)
                            Text("Address Found!")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        
                        Text(extractedAddress)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        
                        Button {
                            createRoute()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                Text("Start Navigation")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let clipboardContent = UIPasteboard.general.string {
            pastedText = clipboardContent
            extractAddress(from: clipboardContent)
        }
    }
    
    private func extractAddress(from text: String) {
        extractedAddress = viewModel.extractAddress(from: text)
    }
    
    private func createRoute() {
        Task {
            if let route = await viewModel.createRoute(to: extractedAddress) {
                onRouteCreated(route)
                dismiss()
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
class LoadInputViewModel: ObservableObject {
    @Published var isLoading = false
    
    /// Extract address using comprehensive Regex patterns
    func extractAddress(from text: String) -> String {
        // Pattern 1: Full US address with zip code
        let pattern1 = #"(\d+\s+[A-Za-z0-9\s,\.]+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Lane|Ln|Way|Court|Ct|Circle|Cir|Parkway|Pkwy)[A-Za-z\s,\.]*(?:,\s*[A-Za-z\s]+,\s*[A-Z]{2}\s*\d{5}(?:-\d{4})?))"#
        
        // Pattern 2: City, State ZIP
        let pattern2 = #"([A-Za-z\s]+,\s*[A-Z]{2}\s*\d{5}(?:-\d{4})?)"#
        
        // Pattern 3: Street address with city/state
        let pattern3 = #"(\d+\s+[A-Za-z0-9\s\.]+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Lane|Ln)[A-Za-z\s,\.]*)"#
        
        let patterns = [pattern1, pattern2, pattern3]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let address = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                return address
            }
        }
        
        return ""
    }
    
    /// Create route with HERE API (with offline caching)
    func createRoute(to address: String) async -> TruckRoute? {
        isLoading = true
        defer { isLoading = false }
        
        // Check cache first
        if let cachedRoute = RouteCache.shared.getRoute(for: address) {
            print("📦 Using cached route - Saving API costs!")
            return cachedRoute
        }
        
        // Call HERE Maps API for truck routing
        let route = await HEREMapsService.shared.calculateTruckRoute(to: address)
        
        // Cache the route
        if let route = route {
            RouteCache.shared.saveRoute(route, for: address)
        }
        
        return route
    }
}

#Preview {
    LoadInputSheet { route in
        print("Route created: \(route.destinationName)")
    }
}
