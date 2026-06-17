//
//  ViewsFuelPriceReportSheet.swift
//  Crowdsourcing de diesel — o motorista digita o preço que VIU no posto.
//
//  Só dado real digitado por ele (evidence_type "manual"). Vai pra fuel_price_reports; outros
//  motoristas veem o agregado via RPC fuel_prices_near. Nunca um número inventado.
//

import SwiftUI
import CoreLocation

struct FuelPriceReportSheet: View {
    let stationName: String
    let coordinate: CLLocationCoordinate2D
    let poiPlaceID: String?
    let network: String?
    var lang: AppLanguage = .english
    var onSubmitted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var submitting = false
    @State private var errorText: String?
    @FocusState private var priceFocused: Bool

    private var price: Double? {
        Double(priceText.replacingOccurrences(of: ",", with: "."))
    }
    private var isValid: Bool {
        guard let p = price else { return false }
        return p > 0.5 && p < 12   // sanidade: $0.50–$12/gal (evita digito errado virar dado falso)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "fuelpump.fill").foregroundColor(Color(hex: "#f59e0b"))
                Text(stationName).font(.system(size: 16, weight: .bold)).foregroundColor(.white).lineLimit(2)
                Spacer()
            }

            Text("Qual o preço do diesel que você viu aqui? (US$/galão)")
                .font(.system(size: 13)).foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text("$").font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                TextField("0.00", text: $priceText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .focused($priceFocused)
                Text("/gal").font(.system(size: 14)).foregroundColor(.gray)
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let errorText {
                Text(errorText).font(.system(size: 12)).foregroundColor(.red)
            }

            Button(action: submit) {
                HStack {
                    if submitting { ProgressView().tint(.black) }
                    Text(submitting ? "Enviando…" : "Enviar preço")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(isValid ? Color(hex: "#f59e0b") : Color.gray.opacity(0.4))
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!isValid || submitting)

            Text("Seu report ajuda outros caminhoneiros. Só preço real — nada inventado.")
                .font(.system(size: 11)).foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0a0906"))
        .preferredColorScheme(.dark)
        .onAppear { priceFocused = true }
    }

    private func submit() {
        guard let p = price, isValid else { return }
        submitting = true
        errorText = nil
        let payload = FuelPriceReportPayload(
            poi_place_id: poiPlaceID,
            driver_id: SupabaseClient.shared.currentDriverId,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            station_name: stationName,
            network: network,
            diesel_price_usd: p,
            evidence_type: "manual",
            reported_at: ISO8601DateFormatter().string(from: Date())
        )
        Task { @MainActor in
            do {
                try await SupabaseClient.shared.submitFuelPriceReport(payload)
                submitting = false
                onSubmitted()
                dismiss()
            } catch {
                submitting = false
                // Honesto: se exige login (RLS authenticated) ou falhou, diz o porquê.
                errorText = "Não enviou: \(error.localizedDescription). (Pode exigir login.)"
            }
        }
    }
}
