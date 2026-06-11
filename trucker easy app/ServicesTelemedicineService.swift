import Foundation

// MARK: - DoctorsHero Telemedicine Integration
// API docs: https://developers.doctorshero.com
// Base URL: https://api.doctorshero.com/api/v1

enum TelemedicineError: LocalizedError {
    case noAPIKey
    case invalidURL
    case networkError(String)
    case serverError(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:             return "Telemedicine API key not configured"
        case .invalidURL:           return "Invalid telemedicine URL"
        case .networkError(let m):  return "Network error: \(m)"
        case .serverError(let c, _): return "Server error (\(c))"
        case .decodingError:        return "Failed to parse response"
        }
    }
}

// MARK: - Response Models

struct TelemedicineAppointment: Codable, Identifiable {
    let id: Int
    let patientName: String?
    let date: String
    let status: String
    let doctorName: String?
    let specialty: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case patientName = "patient_name"
        case date
        case status
        case doctorName = "doctor_name"
        case specialty
        case notes
    }
}

struct TelemedicineDoctor: Codable, Identifiable {
    let id: Int
    let name: String
    let specialty: String
    let availableSlots: [String]?
    let rating: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, specialty, rating
        case availableSlots = "available_slots"
    }
}

struct TelemedicineSymptomCheck: Codable {
    let assessment: String
    let urgency: String        // "low", "medium", "high", "emergency"
    let recommendation: String
    let suggestedSpecialty: String?

    enum CodingKeys: String, CodingKey {
        case assessment, urgency, recommendation
        case suggestedSpecialty = "suggested_specialty"
    }
}

struct PaginatedResponse<T: Codable>: Codable {
    let success: Bool
    let data: [T]
}

// MARK: - Service

final class TelemedicineService {
    static let shared = TelemedicineService()

    private let baseURL = "https://api.doctorshero.com/api/v1"
    private let session: URLSession

    private var apiKey: String? {
        Bundle.main.infoDictionary?["DoctorsHeroAPIKey"] as? String
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    var isConfigured: Bool {
        guard let key = apiKey, !key.isEmpty, !key.contains("$(") else { return false }
        return true
    }

    // MARK: - Appointments

    func fetchAppointments() async throws -> [TelemedicineAppointment] {
        let data = try await request(endpoint: "/appointments")
        let response = try JSONDecoder().decode(PaginatedResponse<TelemedicineAppointment>.self, from: data)
        return response.data
    }

    func bookAppointment(doctorId: Int, date: String, symptoms: String) async throws -> TelemedicineAppointment {
        let body: [String: Any] = [
            "doctor_id": doctorId,
            "date": date,
            "symptoms": symptoms,
            "consultation_type": "telemedicine"
        ]
        let data = try await request(endpoint: "/appointments", method: "POST", body: body)
        let wrapper = try JSONDecoder().decode(SingleResponse<TelemedicineAppointment>.self, from: data)
        return wrapper.data
    }

    // MARK: - Doctors

    func fetchDoctors(specialty: String? = nil) async throws -> [TelemedicineDoctor] {
        var endpoint = "/doctors?consultation_type=telemedicine"
        if let spec = specialty {
            endpoint += "&specialty=\(spec.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? spec)"
        }
        let data = try await request(endpoint: endpoint)
        let response = try JSONDecoder().decode(PaginatedResponse<TelemedicineDoctor>.self, from: data)
        return response.data
    }

    // MARK: - AI Symptom Checker

    func checkSymptoms(_ description: String) async throws -> TelemedicineSymptomCheck {
        let body: [String: Any] = [
            "symptoms": description,
            "context": "truck_driver_occupational_health"
        ]
        let data = try await request(endpoint: "/ai/symptom-check", method: "POST", body: body)
        let wrapper = try JSONDecoder().decode(SingleResponse<TelemedicineSymptomCheck>.self, from: data)
        return wrapper.data
    }

    // MARK: - Networking

    private func request(endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let key = apiKey, !key.isEmpty, !key.contains("$(") else {
            throw TelemedicineError.noAPIKey
        }

        guard let url = URL(string: baseURL + endpoint) else {
            throw TelemedicineError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("TruckerEasy-iOS/1.0", forHTTPHeaderField: "User-Agent")

        if let body = body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = String(data: data, encoding: .utf8) ?? "Unknown"
            throw TelemedicineError.serverError(http.statusCode, detail)
        }

        return data
    }
}

private struct SingleResponse<T: Codable>: Codable {
    let success: Bool
    let data: T
}
