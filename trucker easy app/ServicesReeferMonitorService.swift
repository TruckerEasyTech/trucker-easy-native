//
//  ServicesReeferMonitorService.swift
//  trucker easy app
//
//  Monitor de temperatura do reefer via Bluetooth LE — serviços GATT PADRÃO:
//    • Environmental Sensing (0x181A) → característica Temperature (0x2A6E, sint16 ×0.01°C)
//    • Health Thermometer (0x1809) → característica Temperature Measurement (0x2A1C, IEEE-11073)
//  Funciona com qualquer sensor BLE que implemente o padrão (sensores de carga
//  refrigerada baratos anunciam ESS). HONESTO: sem sensor pareado = sem leitura;
//  temperatura NUNCA é inventada. Estado do Bluetooth exposto sem disfarce.
//

import Foundation
import CoreBluetooth
import Observation

/// UUIDs GATT padrão — escopo de arquivo (fora do ator) p/ uso nos delegates nonisolated.
private enum ReeferGATT {
    static let essService = CBUUID(string: "181A")          // Environmental Sensing
    static let htsService = CBUUID(string: "1809")          // Health Thermometer
    static let tempChar = CBUUID(string: "2A6E")            // Temperature (sint16 ×0.01°C)
    static let tempMeasurementChar = CBUUID(string: "2A1C") // Temperature Measurement (IEEE-11073)
}

@MainActor
@Observable
final class ReeferMonitorService: NSObject {
    static let shared = ReeferMonitorService()

    enum Status: Equatable {
        case idle                    // nunca escaneou
        case bluetoothOff            // rádio desligado
        case unauthorized            // permissão negada
        case scanning                // procurando sensores
        case connecting(String)      // conectando ao sensor
        case connected(String)       // recebendo leituras reais
    }

    struct DiscoveredSensor: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    private(set) var status: Status = .idle
    private(set) var discoveredSensors: [DiscoveredSensor] = []
    /// Última temperatura REAL lida do sensor. nil = sem leitura (nunca chuta).
    private(set) var currentTempCelsius: Double?
    private(set) var lastReadingAt: Date?
    /// Leitura nova desde o último consumo pela UI (para auto-log periódico).
    var onReading: ((Double, String) -> Void)?

    // Setpoints persistidos — faixa típica: congelado -12°C (10°F), resfriado 1-4°C (34-39°F)
    var setpointMinCelsius: Double {
        didSet { UserDefaults.standard.set(setpointMinCelsius, forKey: "reefer.setpointMinC") }
    }
    var setpointMaxCelsius: Double {
        didSet { UserDefaults.standard.set(setpointMaxCelsius, forKey: "reefer.setpointMaxC") }
    }

    var isOutOfRange: Bool {
        guard let t = currentTempCelsius else { return false }
        return t < setpointMinCelsius || t > setpointMaxCelsius
    }

    var connectedSensorName: String? {
        if case .connected(let name) = status { return name }
        return nil
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var wantScan = false

    private override init() {
        let min = UserDefaults.standard.object(forKey: "reefer.setpointMinC") as? Double
        let max = UserDefaults.standard.object(forKey: "reefer.setpointMaxC") as? Double
        setpointMinCelsius = min ?? 1.0    // resfriado padrão: 1°C…4°C (34…39°F)
        setpointMaxCelsius = max ?? 4.0
        super.init()
    }

    func startScan() {
        wantScan = true
        discoveredSensors = []
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            // o scan real começa no centralManagerDidUpdateState quando .poweredOn
        } else {
            beginScanIfPoweredOn()
        }
    }

    func stopScan() {
        wantScan = false
        central?.stopScan()
        if case .scanning = status { status = .idle }
    }

    func connect(_ sensor: DiscoveredSensor) {
        guard let central,
              let target = central.retrievePeripherals(withIdentifiers: [sensor.id]).first else { return }
        central.stopScan()
        wantScan = false
        peripheral = target
        target.delegate = self
        status = .connecting(sensor.name)
        central.connect(target, options: nil)
    }

    func disconnect() {
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        currentTempCelsius = nil
        lastReadingAt = nil
        status = .idle
    }

    private func beginScanIfPoweredOn() {
        guard let central, central.state == .poweredOn, wantScan else { return }
        status = .scanning
        central.scanForPeripherals(
            withServices: [ReeferGATT.essService, ReeferGATT.htsService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    // Parse 0x2A6E: sint16 little-endian, resolução 0.01°C
    private func parseESSTemperature(_ data: Data) -> Double? {
        guard data.count >= 2 else { return nil }
        let raw = Int16(littleEndian: data.withUnsafeBytes { $0.load(as: Int16.self) })
        guard raw != Int16(bitPattern: 0x8000) else { return nil }   // 0x8000 = "valor não conhecido" no spec
        return Double(raw) / 100.0
    }

    // Parse 0x2A1C: flags(1) + IEEE-11073 32-bit FLOAT (mantissa 24-bit + expoente 8-bit)
    private func parseHTSTemperature(_ data: Data) -> Double? {
        guard data.count >= 5 else { return nil }
        let flags = data[0]
        var mantissa = Int32(data[1]) | (Int32(data[2]) << 8) | (Int32(data[3]) << 16)
        if mantissa >= 0x800000 { mantissa -= 0x1000000 }   // sign-extend 24 bits
        let exponent = Int8(bitPattern: data[4])
        let value = Double(mantissa) * pow(10.0, Double(exponent))
        // flag bit0: 0 = Celsius, 1 = Fahrenheit
        return (flags & 0x01) == 0 ? value : (value - 32) * 5 / 9
    }

    fileprivate func handleTemperature(_ celsius: Double) {
        currentTempCelsius = celsius
        lastReadingAt = Date()
        if let name = connectedSensorName {
            onReading?(celsius, name)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ReeferMonitorService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            switch state {
            case .poweredOn:
                self.beginScanIfPoweredOn()
            case .poweredOff:
                self.status = .bluetoothOff
            case .unauthorized:
                self.status = .unauthorized
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? "Sensor BLE"
        let id = peripheral.identifier
        let rssi = RSSI.intValue
        Task { @MainActor in
            guard !self.discoveredSensors.contains(where: { $0.id == id }) else { return }
            self.discoveredSensors.append(DiscoveredSensor(id: id, name: name, rssi: rssi))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.status = .connected(peripheral.name ?? "Sensor BLE")
            peripheral.discoverServices([ReeferGATT.essService, ReeferGATT.htsService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            // Desconexão real (sensor fora de alcance / bateria) — estado honesto, sem leitura fantasma.
            self.peripheral = nil
            self.currentTempCelsius = nil
            self.status = .idle
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.peripheral = nil
            self.status = .idle
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ReeferMonitorService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(
                [ReeferGATT.tempChar, ReeferGATT.tempMeasurementChar], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == ReeferGATT.tempChar || char.uuid == ReeferGATT.tempMeasurementChar {
                // notify quando o sensor suporta; senão leitura única + re-read manual
                if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
                if char.properties.contains(.read) {
                    peripheral.readValue(for: char)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        let uuid = characteristic.uuid
        Task { @MainActor in
            let celsius: Double?
            if uuid == ReeferGATT.tempChar {
                celsius = self.parseESSTemperature(data)
            } else if uuid == ReeferGATT.tempMeasurementChar {
                celsius = self.parseHTSTemperature(data)
            } else {
                celsius = nil
            }
            // Sanidade física: reefer opera -35°C…+30°C; fora disso é leitura corrompida, descarta.
            if let c = celsius, c >= -40, c <= 50 {
                self.handleTemperature(c)
            }
        }
    }
}
