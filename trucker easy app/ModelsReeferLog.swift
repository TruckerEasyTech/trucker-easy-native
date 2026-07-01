//
//  ModelsReeferLog.swift
//  trucker easy app
//
//  Registro de temperatura do baú frigorífico. A FSMA (Sanitary Transportation of
//  Human and Animal Food, 21 CFR 1.908) exige demonstração de controle de temperatura
//  durante o transporte — este log é o registro auditável do motorista.
//  Cada linha é uma leitura REAL: sensor Bluetooth (GATT padrão) ou leitura manual
//  do painel do reefer digitada pelo motorista. Nada é gerado automaticamente.
//

import Foundation
import SwiftData

@Model
final class ReeferTempLog {
    var id: UUID
    var timestamp: Date
    var tempCelsius: Double
    /// "manual" = motorista digitou do painel do reefer · "bluetooth" = sensor BLE real
    var source: String
    var sensorName: String?
    var note: String?

    init(timestamp: Date = Date(),
         tempCelsius: Double,
         source: String,
         sensorName: String? = nil,
         note: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.tempCelsius = tempCelsius
        self.source = source
        self.sensorName = sensorName
        self.note = note
    }

    var tempFahrenheit: Double { tempCelsius * 9 / 5 + 32 }
}
