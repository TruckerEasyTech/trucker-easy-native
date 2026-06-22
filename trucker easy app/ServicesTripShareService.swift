//
//  ServicesTripShareService.swift
//  trucker easy app
//
//  Compartilhamento de viagem estilo Life360 — SOMENTE ACOMPANHAR (read-only).
//  O motorista gera um link e manda pra família; eles abrem no navegador e veem a
//  posição ao vivo do caminhão num mapa. NÃO é navegação: a família só observa, nunca
//  recebe rota nem instruções. Pensado pra trechos fechados / sem sinal, como proteção
//  extra. Tudo é opt-in: se o motorista não tocar em "Compartilhar", nada é enviado.
//
//  Fluxo:
//   • startSharing()  → cria a linha de compartilhamento (Edge Function pública) e
//                        devolve a URL pública pra abrir o iOS share sheet.
//   • pushIfSharing() → chamado a cada fix de GPS; faz throttle e envia lat/lng/rumo/vel.
//   • stopSharing()   → marca a viagem como inativa (o link para de mostrar posição).
//
//  Segurança: a escrita vai pela Edge Function (service role no servidor); a leitura
//  pública é só de viagens ATIVAS e não expiradas (RLS). O token é aleatório e
//  inadivinhável; sem ele, nada é acessível.

import Foundation
import CoreLocation

@MainActor
@Observable
final class TripShareService {
    static let shared = TripShareService()
    private init() {}

    private(set) var isSharing = false
    private(set) var shareURL: URL?
    private(set) var token: String?
    /// Mensagem de erro amigável da última tentativa de iniciar (nil = sem erro).
    private(set) var lastError: String?

    private var lastPushAt: Date = .distantPast
    /// Mínimo entre envios — segura banda/bateria sem perder a noção de "ao vivo".
    private let minPushInterval: TimeInterval = 8

    private var driverName: String {
        let n = (UserDefaults.standard.string(forKey: "driverName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Driver" : n
    }

    private var endpoint: URL? { URL(string: "\(SupabaseConfig.functionsURL)/trip-share") }

    private static func makeToken() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(raw.prefix(20))
    }

    /// Inicia (ou retoma) o compartilhamento. Devolve o link público, ou nil em falha.
    @discardableResult
    func startSharing(origin: String?, destination: String?) async -> URL? {
        guard SupabaseConfig.isConfigured, let endpoint else {
            lastError = "offline"
            return nil
        }
        let tok = token ?? Self.makeToken()
        var body: [String: Any] = [
            "action": "start",
            "token": tok,
            "driver_name": driverName,
        ]
        if let o = origin?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty { body["origin_name"] = o }
        if let d = destination?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { body["dest_name"] = d }

        guard await post(body, to: endpoint) else {
            lastError = "start_failed"
            return nil
        }
        token = tok
        isSharing = true
        lastError = nil
        let url = URL(string: "\(SupabaseConfig.functionsURL)/trip-share?t=\(tok)")
        shareURL = url
        return url
    }

    /// Chamado a cada fix de GPS pela HorizonView. Faz throttle e só envia se ativo.
    func pushIfSharing(location: CLLocation, headingDeg: Double) {
        guard isSharing, let token, let endpoint else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPushAt) >= minPushInterval else { return }
        lastPushAt = now

        let speedMph = max(0, location.speed) * 2.23694
        let heading: Double = {
            if headingDeg.isFinite, headingDeg >= 0 { return headingDeg }
            return location.course >= 0 ? location.course : 0
        }()
        let body: [String: Any] = [
            "action": "update",
            "token": token,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "heading": heading,
            "speed_mph": speedMph,
        ]
        Task { _ = await post(body, to: endpoint) }
    }

    /// Encerra o compartilhamento (a família para de ver a posição).
    func stopSharing() async {
        guard let token, let endpoint else { reset(); return }
        _ = await post(["action": "stop", "token": token], to: endpoint)
        reset()
    }

    private func reset() {
        isSharing = false
        shareURL = nil
        token = nil
        lastPushAt = .distantPast
    }

    private func post(_ body: [String: Any], to url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 12
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        req.httpBody = data
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
