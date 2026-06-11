//
//  ServicesQuantumRouteOptimizationClient.swift
//  trucker easy app
//
//  Cliente HTTP para o middleware de otimização (Python / D-Wave no servidor).
//  O token Leap da D-Wave fica só no backend; aqui pode existir opcionalmente X-API-Key do teu API Gateway.

import Foundation
import OSLog

enum QuantumRouteOptimizationError: Error, LocalizedError {
    case notConfigured
    case invalidBaseURL
    case http(Int, String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Route optimization API URL is not configured (set ROUTE_OPTIMIZATION_API_BASE_URL in xcconfig)."
        case .invalidBaseURL:
            return "Route optimization base URL is invalid."
        case let .http(code, body):
            return "Optimization HTTP \(code): \(body ?? "")"
        case let .decoding(err):
            return "Optimization response decode failed: \(err.localizedDescription)"
        }
    }
}

final class QuantumRouteOptimizationClient: @unchecked Sendable {
    static let shared = QuantumRouteOptimizationClient()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruckerEasy", category: "RouteOptimize")
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 45
        c.timeoutIntervalForResource = 90
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    private init() {}

    private var baseURLString: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "RouteOptimizationAPIBaseURL") as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
    }

    private var apiKey: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "RouteOptimizationAPIKey") as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
    }

    /// `true` quando a URL foi substituída no build (não contém `$(...)` literal).
    var isConfigured: Bool {
        guard let url = Bundle.main.infoDictionary?["RouteOptimizationAPIBaseURL"] as? String,
              !url.isEmpty,
              !url.contains("$(") else {
            return false
        }
        return URL(string: baseURLString) != nil
    }

    func optimize(_ request: RouteOptimizeRequestDTO) async throws -> RouteOptimizeResponseDTO {
        guard isConfigured else { throw QuantumRouteOptimizationError.notConfigured }
        let trimmed = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/v1/optimize") else {
            throw QuantumRouteOptimizationError.invalidBaseURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if isSupabaseEdgeFunction(url) {
            req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            if let token = SupabaseClient.shared.accessToken, !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
            }
        }
        let key = apiKey
        if !key.isEmpty, !key.contains("$(") {
            req.setValue(key, forHTTPHeaderField: "X-API-Key")
        }

        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        req.httpBody = try enc.encode(request)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw QuantumRouteOptimizationError.http(-1, nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            logger.warning("optimize HTTP \(http.statusCode): \(body ?? "", privacy: .public)")
            throw QuantumRouteOptimizationError.http(http.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(RouteOptimizeResponseDTO.self, from: data)
        } catch {
            throw QuantumRouteOptimizationError.decoding(error)
        }
    }

    private func isSupabaseEdgeFunction(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.hasSuffix(".supabase.co") && url.path.contains("/functions/v1/")
    }
}
