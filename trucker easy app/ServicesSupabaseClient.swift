import Foundation
import UIKit

// MARK: - Supabase Configuration
// Project Ref: qhwuwiiwdzqkjzjqgpvx
// Values also stored in Info.plist (SupabaseURL / SupabaseAnonKey)

enum SupabaseConfig {
    private static let defaultProjectRef = "qhwuwiiwdzqkjzjqgpvx"
    private static let defaultProjectURL = "https://qhwuwiiwdzqkjzjqgpvx.supabase.co"
    private static let placeholderAnonKey = "YOUR_SUPABASE_ANON_KEY"

    static var projectRef: String {
        if let configuredURL = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
           let host = URL(string: configuredURL)?.host,
           let ref = host.split(separator: ".").first,
           !ref.isEmpty {
            return String(ref)
        }
        return defaultProjectRef
    }

    static var projectURL: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }
        return defaultProjectURL
    }

    static var functionsURL: String {
        "\(projectURL)/functions/v1"
    }

    static var anonKey: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }
        return placeholderAnonKey
    }

    static var isConfigured: Bool {
        anonKey != placeholderAnonKey
    }

    // Table names
    enum Tables {
        static let roadReports       = "road_reports"
        static let weighStations     = "weigh_station_reports"
        static let deviceTokens      = "device_tokens"
        static let communityPosts    = "community_posts"
        static let postComments      = "post_comments"
        static let logisticsNews     = "logistics_news"
        static let drivers           = "drivers"
        static let dispatchedLoads   = "dispatched_loads"
        static let fuelReports       = "fuel_reports"
        static let routeOptimizations = "route_optimizations"
    }
}

// MARK: - Supabase REST Client

@Observable
final class SupabaseClient {
    static let shared = SupabaseClient()

    private let baseURL: URL
    private let anonKey: String
    private var session: URLSession

    private init() {
        self.baseURL = URL(string: SupabaseConfig.projectURL)!
        self.anonKey = SupabaseConfig.anonKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // Real-time operational data (road reports, dispatch) must never be served stale
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil  // No disk/memory cache for auth + live data
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth state (set after login)
    var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "supabase_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "supabase_access_token") }
    }
    var currentDriverId: String? {
        get { UserDefaults.standard.string(forKey: "supabase_driver_id") }
        set { UserDefaults.standard.set(newValue, forKey: "supabase_driver_id") }
    }
    var isAuthenticated: Bool { accessToken != nil }

    // MARK: - Headers

    private var commonHeaders: [String: String] {
        var h = [
            "apikey": anonKey,
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        ]
        if let token = accessToken {
            h["Authorization"] = "Bearer \(token)"
        } else {
            h["Authorization"] = "Bearer \(anonKey)"
        }
        return h
    }

    // MARK: - Generic GET

    func select<T: Decodable>(
        from table: String,
        query: String = "",
        orderBy: String? = nil,
        limit: Int? = nil
    ) async throws -> [T] {
        try validateConfiguration()
        var urlString = "\(SupabaseConfig.projectURL)/rest/v1/\(table)?select=*"
        if !query.isEmpty { urlString += "&\(query)" }
        if let o = orderBy { urlString += "&order=\(o)" }
        if let l = limit   { urlString += "&limit=\(l)" }

        guard let url = URL(string: urlString) else { throw SupabaseError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        commonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode([T].self, from: data)
    }

    // MARK: - Edge Functions

    func invokeFunction<Payload: Encodable, Response: Decodable>(
        name: String,
        payload: Payload,
        responseType: Response.Type
    ) async throws -> Response {
        try validateConfiguration()
        guard let url = URL(string: "\(SupabaseConfig.functionsURL)/\(name)") else {
            throw SupabaseError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    // MARK: - Generic INSERT

    @discardableResult
    func insert<T: Encodable & Decodable>(into table: String, value: T) async throws -> T {
        try validateConfiguration()
        let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        commonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONEncoder().encode(value)

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        let arr = try JSONDecoder().decode([T].self, from: data)
        guard let first = arr.first else { throw SupabaseError.emptyResponse }
        return first
    }

    @discardableResult
    func insert<Payload: Encodable, Response: Decodable>(
        into table: String,
        value: Payload,
        returning type: Response.Type
    ) async throws -> Response {
        try validateConfiguration()
        let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        commonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONEncoder().encode(value)

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        let arr = try JSONDecoder().decode([Response].self, from: data)
        guard let first = arr.first else { throw SupabaseError.emptyResponse }
        return first
    }

    // MARK: - Generic UPSERT

    func upsert<T: Encodable>(into table: String, value: T) async throws {
        try validateConfiguration()
        let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        var headers = commonHeaders
        headers["Prefer"] = "resolution=merge-duplicates,return=minimal"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONEncoder().encode(value)

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
    }

    // MARK: - Generic PATCH

    func update(table: String, id: String, body: [String: Any]) async throws {
        try validateConfiguration()
        let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)?id=eq.\(id)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        var headers = commonHeaders
        headers["Prefer"] = "return=minimal"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
    }

    // MARK: - DELETE

    func delete(from table: String, id: String) async throws {
        try validateConfiguration()
        let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)?id=eq.\(id)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        commonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let (_, response) = try await session.data(for: req)
        try validateResponse(response, data: nil)
    }

    // MARK: - Auth: Sign Up

    func signUp(email: String, password: String) async throws -> AuthResponse {
        try validateConfiguration()
        let url = URL(string: "\(SupabaseConfig.projectURL)/auth/v1/signup")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        persistAuth(auth)
        return auth
    }

    // MARK: - Auth: Sign In

    func signIn(email: String, password: String) async throws -> AuthResponse {
        try validateConfiguration()
        let url = URL(string: "\(SupabaseConfig.projectURL)/auth/v1/token?grant_type=password")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        persistAuth(auth)
        return auth
    }

    // MARK: - Auth: Sign Out

    func signOut() async throws {
        try validateConfiguration()
        let url = URL(string: "\(SupabaseConfig.projectURL)/auth/v1/logout")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, _) = try await session.data(for: req)
        clearAuth()
    }

    // MARK: - Register Device Token (APNs)

    func registerDeviceToken(_ apnsToken: String) async {
        guard let driverId = currentDriverId else { return }
        let payload = DeviceTokenPayload(
            driver_id: driverId,
            apns_token: apnsToken,
            device_model: UIDevice.current.model,
            os_version: UIDevice.current.systemVersion
        )
        do {
            try await upsert(into: SupabaseConfig.Tables.deviceTokens, value: payload)
        } catch {
            print("SupabaseClient: Failed to register device token — \(error)")
        }
    }

    // MARK: - Road Reports

    func submitRoadReport(_ report: RoadReportPayload) async throws {
        try await upsert(into: SupabaseConfig.Tables.roadReports, value: report)
    }

    func fetchRecentRoadReports(latitude: Double, longitude: Double, radiusKm: Double = 100) async throws -> [RoadReportRecord] {
        // PostgREST doesn't support spatial queries natively without PostGIS;
        // fetch latest 50 and filter client-side for now.
        let records: [RoadReportRecord] = try await select(
            from: SupabaseConfig.Tables.roadReports,
            orderBy: "reported_at.desc",
            limit: 50
        )
        return records
    }

    func fetchRoadReports(locationName: String) async throws -> [RoadReportRecord] {
        let encodedLocation = locationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? locationName
        return try await select(
            from: SupabaseConfig.Tables.roadReports,
            query: "location_name=eq.\(encodedLocation)",
            orderBy: "reported_at.desc",
            limit: 50
        )
    }

    // MARK: - Weigh Station Reports

    func submitWeighStationReport(_ report: WeighStationReportPayload) async throws {
        try await upsert(into: SupabaseConfig.Tables.weighStations, value: report)
    }

    func fetchWeighStationReports() async throws -> [WeighStationReportRecord] {
        return try await select(
            from: SupabaseConfig.Tables.weighStations,
            orderBy: "reported_at.desc",
            limit: 100
        )
    }

    // MARK: - Logistics News

    func fetchLogisticsNews(countryCode: String) async throws -> [LogisticsNewsRecord] {
        return try await select(
            from: SupabaseConfig.Tables.logisticsNews,
            query: "country_code=eq.\(countryCode)",
            orderBy: "published_at.desc",
            limit: 30
        )
    }

    // MARK: - Community Posts

    func fetchCommunityPosts(category: String? = nil) async throws -> [CommunityPostRecord] {
        let q = category.map { "category=eq.\($0)" } ?? ""
        return try await select(
            from: SupabaseConfig.Tables.communityPosts,
            query: q,
            orderBy: "created_at.desc",
            limit: 50
        )
    }

    func submitCommunityPost(_ post: CommunityPostPayload) async throws -> CommunityPostRecord {
        try await insert(into: SupabaseConfig.Tables.communityPosts, value: post, returning: CommunityPostRecord.self)
    }

    func fetchPostComments(postId: String) async throws -> [PostCommentRecord] {
        try await select(
            from: SupabaseConfig.Tables.postComments,
            query: "post_id=eq.\(postId)",
            orderBy: "created_at.desc",
            limit: 100
        )
    }

    func submitPostComment(_ comment: PostCommentPayload) async throws -> PostCommentRecord {
        try await insert(into: SupabaseConfig.Tables.postComments, value: comment, returning: PostCommentRecord.self)
    }

    // MARK: - Dispatched Loads

    func fetchPendingLoads() async throws -> [DispatchedLoadRecord] {
        let driverId = currentDriverId ?? ""
        return try await select(
            from: SupabaseConfig.Tables.dispatchedLoads,
            query: "driver_id=eq.\(driverId)&status=eq.pending",
            orderBy: "created_at.desc"
        )
    }

    func acknowledgeLoad(id: String) async throws {
        try await update(table: SupabaseConfig.Tables.dispatchedLoads, id: id,
                         body: ["status": "received", "received_at": ISO8601DateFormatter().string(from: Date())])
    }

    // Update load status (en_route, delivered, cancelled)
    func updateLoadStatus(id: String, status: DispatchedLoad.LoadStatus) async throws {
        var body: [String: Any] = ["status": status.rawValue]
        switch status {
        case .enRoute:
            body["started_at"] = ISO8601DateFormatter().string(from: Date())
        case .delivered:
            body["delivered_at"] = ISO8601DateFormatter().string(from: Date())
        default:
            break
        }
        try await update(table: SupabaseConfig.Tables.dispatchedLoads, id: id, body: body)
    }

    // Record a fuel stop — feeds into company profit dashboard
    func reportFuelPurchase(
        loadId: String,
        driverId: String,
        companyId: String?,
        gallons: Double,
        pricePerGallon: Double,
        eiaAverage: Double?,
        stationName: String?
    ) async throws {
        let savings = eiaAverage.map { ($0 - pricePerGallon) * gallons }
        let payload = FuelReportPayload(
            load_id: loadId,
            driver_id: driverId,
            company_id: companyId,
            gallons: gallons,
            price_per_gallon: pricePerGallon,
            eia_average: eiaAverage,
            savings_vs_eia: savings,
            station_name: stationName,
            reported_at: ISO8601DateFormatter().string(from: Date())
        )
        try await upsert(into: SupabaseConfig.Tables.fuelReports, value: payload)
    }

    // MARK: - Private helpers

    private func validateResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = data.flatMap { try? JSONDecoder().decode(SupabaseErrorBody.self, from: $0) }?.message
            throw SupabaseError.httpError(http.statusCode, message ?? "Unknown error")
        }
    }

    private func validateConfiguration() throws {
        guard SupabaseConfig.isConfigured else {
            throw SupabaseError.missingConfiguration(
                "Set Info.plist key SupabaseAnonKey for project \(SupabaseConfig.projectRef)."
            )
        }
    }

    private func persistAuth(_ auth: AuthResponse) {
        accessToken    = auth.access_token
        currentDriverId = auth.user?.id
    }

    private func clearAuth() {
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_driver_id")
    }
}

// MARK: - Error Types

enum SupabaseError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyResponse
    case httpError(Int, String)
    case missingConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid URL"
        case .invalidResponse:     return "Invalid server response"
        case .emptyResponse:       return "Empty response from server"
        case .httpError(let c, let m): return "HTTP \(c): \(m)"
        case .missingConfiguration(let message): return message
        }
    }
}

// MARK: - Auth Models

struct AuthResponse: Decodable {
    let access_token: String
    let token_type: String
    let expires_in: Int?
    let refresh_token: String?
    let user: AuthUser?
}

struct AuthUser: Decodable {
    let id: String
    let email: String?
}

// MARK: - Payload Models (Encodable → sent to Supabase)

struct DeviceTokenPayload: Encodable {
    let driver_id: String
    let apns_token: String
    let device_model: String
    let os_version: String
}

struct RoadReportPayload: Encodable {
    let driver_id: String?
    let report_type: String     // "parkingFull", "scaleOpen", "hazard", etc.
    let latitude: Double
    let longitude: Double
    let location_name: String?
}

struct WeighStationReportPayload: Encodable {
    let station_name: String
    let driver_id: String?
    let status: String           // "open", "closed", "monitoring"
    let outcome: String?         // "bypass", "rollingAcross", "inspection"
    let latitude: Double?
    let longitude: Double?
}

struct CommunityPostPayload: Encodable {
    let author_id: String?
    let title: String
    let content: String
    let category: String
    let location: String?
}

struct PostCommentPayload: Encodable {
    let post_id: String
    let author_id: String?
    let content: String
}

// MARK: - Record Models (Decodable ← received from Supabase)

struct RoadReportRecord: Decodable, Identifiable {
    let id: String
    let driver_id: String?
    let report_type: String
    let latitude: Double
    let longitude: Double
    let location_name: String?
    let confirmations: Int?
    let reported_at: String
}

struct WeighStationReportRecord: Decodable, Identifiable {
    let id: String
    let station_name: String
    let driver_id: String?
    let status: String
    let outcome: String?
    let latitude: Double?
    let longitude: Double?
    let confirmations: Int?
    let reported_at: String
}

struct LogisticsNewsRecord: Decodable, Identifiable {
    let id: String
    let headline: String
    let summary: String?
    let category: String?
    let country_code: String
    let source: String?
    let url: String?
    let published_at: String?
}

struct CommunityPostRecord: Decodable, Identifiable {
    let id: String
    let author_id: String?
    let title: String
    let content: String
    let category: String?
    let location: String?
    let like_count: Int?
    let comment_count: Int?
    let created_at: String
}

struct PostCommentRecord: Decodable, Identifiable {
    let id: String
    let post_id: String
    let author_id: String?
    let content: String
    let created_at: String
}

struct DispatchedLoadRecord: Decodable, Identifiable {
    let id: String
    let driver_id: String?
    let load_number: String
    let origin_address: String
    let destination_address: String
    let destination_lat: Double
    let destination_lng: Double
    let pickup_time: String?
    let delivery_time: String?
    let commodity: String?
    let weight_lbs: Double?
    let special_instructions: String?
    let status: String
    let created_at: String
    // B2B fields
    let company_id: String?
    let company_name: String?
    let valor_frete: Double?
    let preco_diesel_eia: Double?
}

struct FuelReportPayload: Encodable {
    let load_id: String
    let driver_id: String
    let company_id: String?
    let gallons: Double
    let price_per_gallon: Double
    let eia_average: Double?           // Government reference price for comparison
    let savings_vs_eia: Double?        // Computed: (eia_average - price_per_gallon) * gallons
    let station_name: String?
    let reported_at: String
}

private struct SupabaseErrorBody: Decodable {
    let message: String?
    let hint: String?
}
