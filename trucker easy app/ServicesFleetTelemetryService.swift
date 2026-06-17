import Foundation
import CoreLocation
import CoreBluetooth
import Observation

struct FleetTelemetrySnapshot: Equatable {
    let timestamp: Date
    let speedMph: Double?
    let engineRpm: Double?
    let engineHours: Double?
    let odometerMiles: Double?
    let fuelLevelPercent: Double?
    let vin: String?
    let dtcCodes: [String]
    let source: String
}

protocol FleetTelemetryProvider {
    var providerName: String { get }
    func fetchSnapshot() async throws -> FleetTelemetrySnapshot
}

enum FleetTelemetryConfig {
    static var obdDeviceName: String {
        Bundle.main.object(forInfoDictionaryKey: "OBD2BLEDeviceName") as? String ?? ""
    }

    static var hasOBDDevice: Bool {
        !obdDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var eldProviderBaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "ELDProviderBaseURL") as? String ?? ""
    }

    static var eldProviderAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "ELDProviderAPIKey") as? String ?? ""
    }

    static var eldVehicleID: String {
        Bundle.main.object(forInfoDictionaryKey: "ELDVehicleID") as? String ?? ""
    }

    static var hasELDProvider: Bool {
        !eldProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !eldVehicleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct RealtimeTelemetryRecord: Decodable {
    let speed_mph: Double?
    let engine_rpm: Double?
    let engine_hours: Double?
    let odometer_miles: Double?
    let fuel_level_percent: Double?
    let vin: String?
    let dtc_codes: [String]?
    let created_at: String?
}

final class SupabaseRealtimeTelemetryProvider: FleetTelemetryProvider {
    let providerName = "trucker_easy_realtime"

    func fetchSnapshot() async throws -> FleetTelemetrySnapshot {
        let endpoint = "\(SupabaseConfig.projectURL)/rest/v1/fleet_telemetry_stream?select=*&order=created_at.desc&limit=1"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = SupabaseClient.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let records = try JSONDecoder().decode([RealtimeTelemetryRecord].self, from: data)
        guard let dto = records.first else { throw URLError(.resourceUnavailable) }
        let timestamp = dto.created_at.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

        return FleetTelemetrySnapshot(
            timestamp: timestamp,
            speedMph: dto.speed_mph,
            engineRpm: dto.engine_rpm,
            engineHours: dto.engine_hours,
            odometerMiles: dto.odometer_miles,
            fuelLevelPercent: dto.fuel_level_percent,
            vin: dto.vin,
            dtcCodes: dto.dtc_codes ?? [],
            source: providerName
        )
    }
}

private struct ELDProviderTelemetryRecord: Decodable {
    let speed_mph: Double?
    let engine_rpm: Double?
    let engine_hours: Double?
    let odometer_miles: Double?
    let fuel_level_percent: Double?
    let vin: String?
    let dtc_codes: [String]?
    let timestamp: String?
}

final class ELDHTTPTelemetryProvider: FleetTelemetryProvider {
    let providerName = "eld_http_provider"

    func fetchSnapshot() async throws -> FleetTelemetrySnapshot {
        let base = FleetTelemetryConfig.eldProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let vehicleID = FleetTelemetryConfig.eldVehicleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !vehicleID.isEmpty else {
            throw URLError(.resourceUnavailable)
        }

        var components = URLComponents(string: "\(base)/v1/telemetry/latest")
        components?.queryItems = [
            URLQueryItem(name: "vehicle_id", value: vehicleID)
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = FleetTelemetryConfig.eldProviderAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let dto = try JSONDecoder().decode(ELDProviderTelemetryRecord.self, from: data)
        let timestamp = dto.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

        return FleetTelemetrySnapshot(
            timestamp: timestamp,
            speedMph: dto.speed_mph,
            engineRpm: dto.engine_rpm,
            engineHours: dto.engine_hours,
            odometerMiles: dto.odometer_miles,
            fuelLevelPercent: dto.fuel_level_percent,
            vin: dto.vin,
            dtcCodes: dto.dtc_codes ?? [],
            source: providerName
        )
    }
}

@MainActor
@Observable
final class OBD2BluetoothProvider: NSObject, FleetTelemetryProvider {
    let providerName = "obd2_ble"

    private var central: CBCentralManager?
    private var connected = false
    private var latestSpeedMph: Double?
    private var latestRPM: Double?
    private var latestDTCs: [String] = []
    private var latestTimestamp: Date = .distantPast

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func fetchSnapshot() async throws -> FleetTelemetrySnapshot {
        if !connected {
            scanIfNeeded()
        }

        return FleetTelemetrySnapshot(
            timestamp: latestTimestamp == .distantPast ? Date() : latestTimestamp,
            speedMph: latestSpeedMph,
            engineRpm: latestRPM,
            engineHours: nil,
            odometerMiles: nil,
            fuelLevelPercent: nil,
            vin: nil,
            dtcCodes: latestDTCs,
            source: providerName
        )
    }

    private func scanIfNeeded() {
        guard central?.state == .poweredOn, !FleetTelemetryConfig.obdDeviceName.isEmpty else { return }
        central?.scanForPeripherals(withServices: nil)
    }
}

extension OBD2BluetoothProvider: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scanIfNeeded()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let target = FleetTelemetryConfig.obdDeviceName.lowercased()
        let name = (peripheral.name ?? "").lowercased()
        if !target.isEmpty && name.contains(target) {
            self.connected = true
            self.latestTimestamp = Date()
            central.stopScan()
        }
    }
}

@MainActor
@Observable
final class FleetTelemetryService {
    static let shared = FleetTelemetryService()

    private(set) var currentSnapshot: FleetTelemetrySnapshot?
    private(set) var isConnected = false
    private(set) var lastError: String?
    private(set) var lastSuccessfulProvider: String?
    private(set) var lastSuccessfulAt: Date?

    private var providers: [FleetTelemetryProvider] = []
    private var lastRefreshDate: Date = .distantPast
    private let refreshInterval: TimeInterval = 10

    private init() {
        if FleetTelemetryConfig.hasELDProvider {
            providers.append(ELDHTTPTelemetryProvider())
        }
        providers.append(SupabaseRealtimeTelemetryProvider())
        if FleetTelemetryConfig.hasOBDDevice {
            providers.append(OBD2BluetoothProvider())
        }
    }

    func refreshIfNeeded() async {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshDate) >= refreshInterval else { return }
        lastRefreshDate = now

        for provider in providers {
            do {
                let snapshot = try await provider.fetchSnapshot()
                currentSnapshot = snapshot
                isConnected = snapshot.speedMph != nil || snapshot.engineRpm != nil || snapshot.engineHours != nil
                lastError = nil
                lastSuccessfulProvider = provider.providerName
                lastSuccessfulAt = Date()
                return
            } catch {
                lastError = "\(provider.providerName): \(error.localizedDescription)"
            }
        }

        isConnected = false
    }

    func preferredSpeedMph(gpsSpeedMph: Double) -> Double {
        guard let snapshot = currentSnapshot else { return gpsSpeedMph }
        guard Date().timeIntervalSince(snapshot.timestamp) <= 30 else { return gpsSpeedMph }
        return snapshot.speedMph ?? gpsSpeedMph
    }
}
