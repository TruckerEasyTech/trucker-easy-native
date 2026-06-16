import Foundation
import UIKit
import CoreLocation

// MARK: - Supabase Configuration
// Project ref default: usowafvqawbunyhmfscx (override via SupabaseURL / $(SUPABASE_URL))
// Values from Info.plist; SUPABASE_URL in .xcconfig must use https:||host (// starts a comment in xcconfig).

enum SupabaseConfig {
    private static let defaultProjectRef = "usowafvqawbunyhmfscx"
    private static let defaultProjectURL = "https://usowafvqawbunyhmfscx.supabase.co"
    private static let placeholderAnonKey = "YOUR_SUPABASE_ANON_KEY"

    private static func plistSupabaseURLString() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "||", with: "//")
        guard !t.isEmpty, !t.contains("$(") else { return nil }
        return t
    }

    static var projectRef: String {
        guard let configuredURL = plistSupabaseURLString(),
              let host = URL(string: configuredURL)?.host,
              let ref = host.split(separator: ".").first,
              !ref.isEmpty else {
            return defaultProjectRef
        }
        return String(ref)
    }

    static var projectURL: String {
        if let configured = plistSupabaseURLString() {
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
        static let fuelPriceReports  = "fuel_price_reports"
        static let fuelReceipts      = "fuel_receipts"
        static let truckStopParkingReports = "truck_stop_parking_reports"
        static let truckStopReviews  = "truck_stop_reviews"
        static let shipperFacilityReviews = "shipper_facility_reviews"
        static let driverWellnessCheckins = "driver_wellness_checkins"
        static let driverWellnessInsights = "driver_wellness_insights"
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
        self.baseURL = URL(string: SupabaseConfig.projectURL) ?? URL(string: "https://placeholder.supabase.co")!
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

    // MARK: - Storage (upload de documentos)

    /// Faz upload REAL de um documento pro Storage privado (bucket `driver-documents`) e devolve o
    /// path salvo. O path começa com o uid do motorista (exigido pela RLS). Requer login.
    @discardableResult
    func uploadDriverDocument(data: Data, fileName: String, contentType: String) async throws -> String {
        try validateConfiguration()
        guard let uid = currentDriverId, accessToken != nil else {
            throw SupabaseError.missingConfiguration("Faça login para fazer backup dos documentos na nuvem.")
        }
        let path = "\(uid)/\(fileName)"
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/storage/v1/object/driver-documents/\(path)") else {
            throw SupabaseError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        commonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")   // sobrescreve o application/json
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = data
        let (respData, response) = try await session.data(for: req)
        try validateResponse(response, data: respData)
        return path
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

    // MARK: - PostgREST RPC

    /// Calls a Postgres function exposed through Supabase PostgREST, e.g. `places_near`.
    func rpc<Payload: Encodable, Response: Decodable>(
        _ function: String,
        params: Payload,
        responseType: Response.Type = Response.self
    ) async throws -> [Response] {
        try validateConfiguration()
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/rpc/\(function)") else {
            throw SupabaseError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        var headers = commonHeaders
        headers["Prefer"] = "return=representation"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONEncoder().encode(params)

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode([Response].self, from: data)
    }

    // MARK: - Generic INSERT

    @discardableResult
    func insert<T: Encodable & Decodable>(into table: String, value: T) async throws -> T {
        try validateConfiguration()
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)") else { throw SupabaseError.invalidURL }
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
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)") else { throw SupabaseError.invalidURL }
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

    func insertPayload<Payload: Encodable>(into table: String, value: Payload) async throws {
        try validateConfiguration()
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)") else { throw SupabaseError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        var headers = commonHeaders
        headers["Prefer"] = "return=minimal"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONEncoder().encode(value)

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
    }

    // MARK: - Generic UPSERT

    func upsert<T: Encodable>(into table: String, value: T) async throws {
        try await upsert(into: table, value: value, onConflict: nil)
    }

    func upsert<T: Encodable>(into table: String, value: T, onConflict: String?) async throws {
        try validateConfiguration()
        var urlString = "\(SupabaseConfig.projectURL)/rest/v1/\(table)"
        if let onConflict, !onConflict.isEmpty {
            urlString += "?on_conflict=\(onConflict)"
        }
        guard let url = URL(string: urlString) else { throw SupabaseError.invalidURL }
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
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)?id=eq.\(id)") else { throw SupabaseError.invalidURL }
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
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/\(table)?id=eq.\(id)") else { throw SupabaseError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        commonHeaders.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        let (_, response) = try await session.data(for: req)
        try validateResponse(response, data: nil)
    }

    // MARK: - Auth: Sign Up

    func signUp(email: String, password: String) async throws -> AuthResponse {
        try validateConfiguration()
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/auth/v1/signup") else { throw SupabaseError.invalidURL }
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
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/auth/v1/token?grant_type=password") else { throw SupabaseError.invalidURL }
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
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/auth/v1/logout") else { throw SupabaseError.invalidURL }
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
            #if DEBUG
            print("SupabaseClient: Failed to register device token — \(error)")
            #endif
        }
    }

    // MARK: - Road Reports

    func submitRoadReport(_ report: RoadReportPayload) async throws {
        try await upsert(into: SupabaseConfig.Tables.roadReports, value: report)
    }

    func submitTruckStopParkingReport(_ report: TruckStopParkingReportPayload) async throws {
        try await upsert(into: SupabaseConfig.Tables.truckStopParkingReports, value: report)
    }

    func submitTruckStopReview(_ review: TruckStopReviewPayload) async throws {
        try await upsert(into: SupabaseConfig.Tables.truckStopReviews, value: review)
    }

    func submitShipperFacilityReview(_ review: ShipperFacilityReviewPayload) async throws {
        try await upsert(into: SupabaseConfig.Tables.shipperFacilityReviews, value: review)
    }

    func submitDriverWellnessCheckin(_ checkin: DriverWellnessCheckinPayload) async throws {
        try await upsert(
            into: SupabaseConfig.Tables.driverWellnessCheckins,
            value: checkin,
            onConflict: "driver_id,checkin_date"
        )
    }

    func submitDriverWellnessInsight(_ insight: DriverWellnessInsightPayload) async throws {
        try await insertPayload(into: SupabaseConfig.Tables.driverWellnessInsights, value: insight)
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
        try await insertPayload(into: SupabaseConfig.Tables.weighStations, value: report)
    }

    func fetchWeighStationReports(limit: Int = 500) async throws -> [WeighStationReportRecord] {
        return try await select(
            from: SupabaseConfig.Tables.weighStations,
            orderBy: "created_at.desc",
            limit: limit
        )
    }

    func fetchWeighStationReportsNear(
        latitude: Double,
        longitude: Double,
        radiusKm: Double = 150
    ) async throws -> [WeighStationReportRecord] {
        let records = try await fetchWeighStationReports()
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let radiusMeters = radiusKm * 1000
        return records.filter { record in
            guard let lat = record.latitude, let lon = record.longitude else { return false }
            let dist = here.distance(from: CLLocation(latitude: lat, longitude: lon))
            return dist <= radiusMeters
        }
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
                "Set SUPABASE_ANON_KEY in Config/TruckerEasy.secrets.xcconfig (Info.plist key SupabaseAnonKey) for project \(SupabaseConfig.projectRef)."
            )
        }
        let key = SupabaseConfig.anonKey
        if key.hasPrefix("sb_publishable_") {
            throw SupabaseError.missingConfiguration(
                "SUPABASE_ANON_KEY must be the JWT anon key (starts with eyJ…), not sb_publishable_…. Supabase → Project Settings → API → Project API keys (anon public)."
            )
        }
    }

    private func persistAuth(_ auth: AuthResponse) {
        accessToken = auth.access_token
        currentDriverId = auth.user?.id
        if let mail = auth.user?.email {
            UserDefaults.standard.set(mail, forKey: "supabase_driver_email")
        }
    }

    private func clearAuth() {
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_driver_id")
        UserDefaults.standard.removeObject(forKey: "supabase_driver_email")
    }

    // MARK: - Driver profile row (fleet portal + app share `drivers` table)

    func ensureDriverProfile(email: String, fullName: String?) async throws {
        guard let id = currentDriverId else { return }
        let payload = DriverProfilePayload(
            id: id,
            email: email,
            full_name: fullName
        )
        try await upsert(into: SupabaseConfig.Tables.drivers, value: payload)
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

struct DriverProfilePayload: Encodable {
    let id: String
    let email: String?
    let full_name: String?
}

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

struct TruckStopParkingReportPayload: Encodable {
    let poi_place_id: UUID?
    let driver_id: String?
    let location_name: String
    let latitude: Double
    let longitude: Double
    let status: String          // "many", "some", "full"
    let available_slots: Int?
    let total_slots: Int?
}

struct TruckStopReviewPayload: Encodable {
    let poi_place_id: UUID?
    let driver_id: String?
    let location_name: String
    let latitude: Double
    let longitude: Double
    let easy_access_rating: Int?
    let cleanliness_rating: Int?
    let restaurants_rating: Int?
    let friendly_service_rating: Int?
    let price_rating: Int?
    let overall_rating: Double
    let restaurant_names: [String]
    let has_healthy_options: Bool?
    let comments: String?
}

struct ShipperFacilityReviewPayload: Encodable {
    let driver_id: String?
    let load_number: String
    let company_id: String?
    let company_name: String?
    let review_type: String
    let latitude: Double
    let longitude: Double
    let treatment_rating: Int?
    let bathroom_rating: Int?
    let food_access_rating: Int?
    let access_rating: Int?
    let wait_minutes: Int?
    let overall_rating: Double
    let notes: String?
}

struct DriverWellnessCheckinPayload: Encodable {
    let driver_id: String
    let checkin_date: String
    let mood_stars: Int?
    let stress_level: Int?
    let sleep_hours: Double?
    let had_meal: Bool?
    let felt_rested: Bool?
    let source: String
}

struct DriverWellnessInsightPayload: Encodable {
    let driver_id: String
    let visit_kind: String
    let place_name: String
    let mood_stars: Int?
    let visit_avg_stars: Double?
    let service_rating: Int?
    let shower_rating: Int?
    let food_rating: Int?
    let treatment_rating: Int?
    let bathroom_rating: Int?
    let food_access_rating: Int?
    let access_rating: Int?
    let correlation_note: String?
    let latitude: Double?
    let longitude: Double?
    let load_number: String?
    let company_name: String?
}

struct WeighStationReportDetailsPayload: Encodable {
    let outcome: String?
    let source: String
    /// Whether the driver's PrePass/bypass transponder was on when passing — crowdsourced hint for
    /// other drivers. Stored inside the `details` jsonb, so no schema migration is needed.
    var prepass: Bool? = nil
}

struct WeighStationReportPayload: Encodable {
    let station_name: String
    let driver_id: String?
    let status: String           // "open", "closed", "monitoring"
    let latitude: Double?
    let longitude: Double?
    let poi_place_id: String?
    let details: WeighStationReportDetailsPayload?
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

struct WeighStationReportDetailsRecord: Decodable {
    let outcome: String?
    let confirmations: Int?
    let source: String?
    let prepass: Bool?
}

struct WeighStationReportRecord: Decodable, Identifiable {
    let id: String
    let station_name: String
    let driver_id: String?
    let status: String
    let latitude: Double?
    let longitude: Double?
    let created_at: String
    let details: WeighStationReportDetailsRecord?

    var outcome: String? { details?.outcome }
    var confirmations: Int? { details?.confirmations }
    var reported_at: String { created_at }
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
