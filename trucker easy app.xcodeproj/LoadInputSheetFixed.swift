//
//  LoadInputSheetFixed.swift
//  Trucker Easy
//
//  "Got Load?" FUNCIONANDO COM REGEX REAL
//

import SwiftUI
import MapKit

struct LoadInputSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var pastedText = ""
    @State private var extractedAddress = ""
    @State private var isProcessing = false
    var onRouteCreated: (TruckRoute) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "truck.box.badge.clock.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Got Load?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Paste your load info - I'll find the address!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                // Botão colar do clipboard
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
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                // Ou digitar manualmente
                VStack(alignment: .leading, spacing: 12) {
                    Text("Or type/paste here:")
                        .font(.headline)
                    
                    TextEditor(text: $pastedText)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                        .onChange(of: pastedText) { _, newValue in
                            extractAddressWithRegex(from: newValue)
                        }
                }
                .padding(.horizontal)
                
                // Endereço extraído
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
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
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
                        .disabled(isProcessing)
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
            extractAddressWithRegex(from: clipboardContent)
        }
    }
    
    private func extractAddressWithRegex(from text: String) {
        print("🔍 Extraindo endereço de: \(text)")
        
        // REGEX PATTERNS - VÁRIOS FORMATOS SUPORTADOS
        let patterns = [
            // Pattern 1: Endereço completo com ZIP
            #"(\d+\s+[A-Za-z0-9\s,\.]+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Lane|Ln|Way|Court|Ct|Circle|Cir|Parkway|Pkwy)[A-Za-z\s,\.]*(?:,\s*[A-Za-z\s]+,\s*[A-Z]{2}\s*\d{5}(?:-\d{4})?))"#,
            
            // Pattern 2: Cidade, Estado ZIP
            #"([A-Za-z\s]+,\s*[A-Z]{2}\s*\d{5}(?:-\d{4})?)"#,
            
            // Pattern 3: Endereço com número
            #"(\d+\s+[A-Za-z0-9\s\.]+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Lane|Ln)[A-Za-z\s,\.]*))"#,
            
            // Pattern 4: Qualquer endereço com estado de 2 letras
            #"([A-Za-z0-9\s,\.]+,\s*[A-Z]{2})"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                
                let address = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                extractedAddress = address
                print("✅ Endereço extraído: \(address)")
                return
            }
        }
        
        extractedAddress = ""
        print("❌ Nenhum endereço encontrado")
    }
    
    private func createRoute() {
        isProcessing = true
        
        // Geocodificar o endereço
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(extractedAddress) { placemarks, error in
            if let error = error {
                print("❌ Erro ao geocodificar: \(error.localizedDescription)")
                isProcessing = false
                return
            }
            
            guard let placemark = placemarks?.first,
                  let location = placemark.location else {
                print("❌ Localização não encontrada")
                isProcessing = false
                return
            }
            
            // Criar rota MOCK (depois você integra com HERE API)
            let mockPolyline = MKPolyline(
                coordinates: [
                    CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                    location.coordinate
                ],
                count: 2
            )
            
            let route = TruckRoute(
                destinationName: extractedAddress,
                destination: location.coordinate,
                distance: "250.5",
                estimatedTime: "4h 30m",
                polyline: mockPolyline,
                truckRestrictions: TruckRestrictions()
            )
            
            print("✅ Rota criada para: \(extractedAddress)")
            
            onRouteCreated(route)
            isProcessing = false
        }
    }
}

// EXEMPLOS DE TESTE:
/*
 Cole estes textos para testar:
 
 1. "Pick up at 123 Main Street, Columbus, OH 43215"
 2. "Deliver to 456 Industrial Blvd, Dallas, TX 75201"
 3. "Load #12345 - 789 Oak Ave, Miami, FL 33101 - Weight: 45,000 lbs"
 4. "Contact: John (555-1234) - Address: 321 Pine Road, Atlanta, GA 30303"
 */

#Preview {
    LoadInputSheet { route in
        print("Rota criada: \(route.destinationName)")
    }
}
