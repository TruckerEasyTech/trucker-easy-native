// ServicesIntegrationsHealthCheck.swift — ping configured APIs (xcconfig → Info.plist).

import Foundation

struct IntegrationHealthResult: Identifiable, Sendable {
    let name: String
    let ok: Bool
    let detail: String
    var id: String { name }
}

enum IntegrationsHealthCheck {

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 12
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func runAll() async -> [IntegrationHealthResult] {
        await withTaskGroup(of: IntegrationHealthResult.self) { group in
            group.addTask { await checkValhalla() }
            group.addTask { await checkQuantumOptimize() }
            group.addTask { await checkSupabase() }
            group.addTask { await checkPlacesNear() }
            group.addTask { await checkOpsFeed() }
            group.addTask { await checkOpenRouter() }
            group.addTask { await checkMapboxToken() }
            group.addTask { await checkOpenWeather() }
            var out: [IntegrationHealthResult] = []
            for await r in group { out.append(r) }
            let order = ["Valhalla", "Quantum", "Supabase", "POI", "OpsFeed", "OpenRouter", "Mapbox", "OpenWeather"]
            return out.sorted {
                (order.firstIndex(of: $0.name) ?? 99) < (order.firstIndex(of: $1.name) ?? 99)
            }
        }
    }

    static func checkValhalla() async -> IntegrationHealthResult {
        let bases = await MainActor.run { ValhallaRoutingService.shared.prioritizedServerBaseURLs }
        guard let first = bases.first, let baseURL = URL(string: first.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            return IntegrationHealthResult(name: "Valhalla", ok: false, detail: "No URL in xcconfig")
        }
        let statusURL = baseURL.appendingPathComponent("status")
        do {
            let (_, resp) = try await session.data(from: statusURL)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code) {
                return IntegrationHealthResult(name: "Valhalla", ok: true, detail: "HTTP \(code) · \(hostLabel(statusURL))")
            }
            return IntegrationHealthResult(name: "Valhalla", ok: false, detail: "HTTP \(code) · \(hostLabel(statusURL))")
        } catch {
            return IntegrationHealthResult(name: "Valhalla", ok: false, detail: "\(hostLabel(statusURL)) · \(error.localizedDescription)")
        }
    }

    static func checkQuantumOptimize() async -> IntegrationHealthResult {
        let raw = Bundle.main.object(forInfoDictionaryKey: "RouteOptimizationAPIBaseURL") as? String ?? ""
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
        guard !base.isEmpty, !base.contains("$("), let root = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            return IntegrationHealthResult(name: "Quantum", ok: false, detail: "ROUTE_OPTIMIZATION_API_BASE_URL empty")
        }
        for path in ["/health", "/docs", "/"] {
            let url = root.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                let (_, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (200...399).contains(code) {
                    return IntegrationHealthResult(name: "Quantum", ok: true, detail: "HTTP \(code) \(path.isEmpty ? "/" : path)")
                }
            } catch {
                continue
            }
        }
        return IntegrationHealthResult(name: "Quantum", ok: false, detail: "No response · \(hostLabel(root))")
    }

    static func checkSupabase() async -> IntegrationHealthResult {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        let urlStr = raw.replacingOccurrences(of: "||", with: "//").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlStr.isEmpty, !urlStr.contains("$("), let base = URL(string: urlStr) else {
            return IntegrationHealthResult(name: "Supabase", ok: false, detail: "SUPABASE_URL missing")
        }
        guard !key.isEmpty, !key.contains("$(") else {
            return IntegrationHealthResult(name: "Supabase", ok: false, detail: "SUPABASE_ANON_KEY missing")
        }
        var components = URLComponents(
            url: base.appendingPathComponent("rest/v1/usage_metrics"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else {
            return IntegrationHealthResult(name: "Supabase", ok: false, detail: "Invalid REST URL")
        }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200...299).contains(code)
            return IntegrationHealthResult(
                name: "Supabase",
                ok: ok,
                detail: ok ? "REST OK (HTTP \(code))" : "HTTP \(code) — check anon JWT key"
            )
        } catch {
            return IntegrationHealthResult(name: "Supabase", ok: false, detail: error.localizedDescription)
        }
    }

    static func checkOpenWeather() async -> IntegrationHealthResult {
        let key = Bundle.main.object(forInfoDictionaryKey: "OpenWeatherMapAPIKey") as? String ?? ""
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return IntegrationHealthResult(name: "OpenWeather", ok: false, detail: "OpenWeatherMapAPIKey empty")
        }
        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: "45.5"),
            URLQueryItem(name: "lon", value: "-122.6"),
            URLQueryItem(name: "appid", value: trimmed),
        ]
        guard let url = components.url else {
            return IntegrationHealthResult(name: "OpenWeather", ok: false, detail: "Bad URL")
        }
        do {
            let (_, resp) = try await session.data(from: url)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200...299).contains(code)
            return IntegrationHealthResult(
                name: "OpenWeather",
                ok: ok,
                detail: ok ? "API key OK (HTTP \(code))" : "HTTP \(code) — check key"
            )
        } catch {
            return IntegrationHealthResult(name: "OpenWeather", ok: false, detail: error.localizedDescription)
        }
    }

    static func checkOpenRouter() async -> IntegrationHealthResult {
        let key = Bundle.main.object(forInfoDictionaryKey: "OpenRouterAPIKey") as? String ?? ""
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return IntegrationHealthResult(name: "OpenRouter", ok: false, detail: "OpenRouterAPIKey empty")
        }
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            return IntegrationHealthResult(name: "OpenRouter", ok: false, detail: "Bad URL")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200...299).contains(code)
            return IntegrationHealthResult(
                name: "OpenRouter",
                ok: ok,
                detail: ok ? "API key OK (HTTP \(code))" : "HTTP \(code) — check key"
            )
        } catch {
            return IntegrationHealthResult(name: "OpenRouter", ok: false, detail: error.localizedDescription)
        }
    }

    static func checkPlacesNear() async -> IntegrationHealthResult {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        let urlStr = raw.replacingOccurrences(of: "||", with: "//").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlStr.isEmpty, !urlStr.contains("$("), let base = URL(string: urlStr) else {
            return IntegrationHealthResult(name: "POI", ok: false, detail: "SUPABASE_URL missing")
        }
        guard !key.isEmpty, !key.contains("$(") else {
            return IntegrationHealthResult(name: "POI", ok: false, detail: "SUPABASE_ANON_KEY missing")
        }
        var components = URLComponents(url: base.appendingPathComponent("rest/v1/rpc/places_near"), resolvingAgainstBaseURL: false)
        components?.queryItems = []
        guard let url = components?.url else {
            return IntegrationHealthResult(name: "POI", ok: false, detail: "Invalid RPC URL")
        }
        let body: [String: Any] = [
            "p_lat": 40.76,
            "p_lon": -111.89,
            "p_radius_m": 25_000,
            "p_poi_types": ["truck_stop", "weigh_station"],
            "p_limit": 5
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return IntegrationHealthResult(name: "POI", ok: false, detail: "Bad request body")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return IntegrationHealthResult(name: "POI", ok: true, detail: "places_near OK · \(arr.count) rows")
            }
            let snippet = String(data: data.prefix(120), encoding: .utf8) ?? "HTTP \(code)"
            return IntegrationHealthResult(name: "POI", ok: false, detail: snippet)
        } catch {
            return IntegrationHealthResult(name: "POI", ok: false, detail: error.localizedDescription)
        }
    }

    static func checkOpsFeed() async -> IntegrationHealthResult {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        let urlStr = raw.replacingOccurrences(of: "||", with: "//").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlStr.isEmpty, !urlStr.contains("$("), let base = URL(string: urlStr) else {
            return IntegrationHealthResult(name: "OpsFeed", ok: false, detail: "SUPABASE_URL missing")
        }
        guard !key.isEmpty, !key.contains("$(") else {
            return IntegrationHealthResult(name: "OpsFeed", ok: false, detail: "SUPABASE_ANON_KEY missing")
        }
        var components = URLComponents(url: base.appendingPathComponent("functions/v1/ops-feed"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lat", value: "40.76"),
            URLQueryItem(name: "lon", value: "-111.89"),
            URLQueryItem(name: "radius_km", value: "80")
        ]
        guard let url = components?.url else {
            return IntegrationHealthResult(name: "OpsFeed", ok: false, detail: "Invalid ops-feed URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let weigh = (json["weigh_signals"] as? [Any])?.count ?? 0
                let parking = (json["parking_signals"] as? [Any])?.count ?? 0
                return IntegrationHealthResult(
                    name: "OpsFeed",
                    ok: true,
                    detail: "HTTP \(code) · weigh=\(weigh) parking=\(parking)"
                )
            }
            return IntegrationHealthResult(name: "OpsFeed", ok: false, detail: "HTTP \(code)")
        } catch {
            return IntegrationHealthResult(name: "OpsFeed", ok: false, detail: error.localizedDescription)
        }
    }

    static func checkMapboxToken() async -> IntegrationHealthResult {
        let key = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
        let t = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains("$(") else {
            return IntegrationHealthResult(name: "Mapbox", ok: false, detail: "MBXAccessToken empty")
        }
        let looksValid = t.hasPrefix("pk.")
        return IntegrationHealthResult(
            name: "Mapbox",
            ok: looksValid,
            detail: looksValid ? "Token present (map render)" : "Token format unexpected"
        )
    }

    private static func hostLabel(_ url: URL) -> String {
        url.host ?? url.absoluteString
    }
}
