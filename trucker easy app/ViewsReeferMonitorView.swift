//
//  ViewsReeferMonitorView.swift
//  trucker easy app
//
//  Monitoramento de temperatura do baú frigorífico (reefer):
//    • Sensor Bluetooth LE real (GATT Environmental Sensing / Health Thermometer)
//    • Leitura manual do painel do reefer (motorista digita — registro FSMA)
//    • Faixa alvo com alerta visual quando fora da faixa
//  HONESTO: sem sensor e sem leitura manual = mostra "—", nunca um número inventado.
//

import SwiftUI
import SwiftData

struct ReeferMonitorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReeferTempLog.timestamp, order: .reverse) private var logs: [ReeferTempLog]

    @State private var monitor = ReeferMonitorService.shared
    @State private var manualTempF: String = ""
    @State private var showingManualEntry = false
    /// Auto-log BLE: no máximo 1 registro a cada 15 min (senão o notify inunda o banco).
    @State private var lastAutoLogAt: Date = .distantPast

    private var displayTempF: Double? {
        if let c = monitor.currentTempCelsius { return c * 9 / 5 + 32 }
        // Fallback honesto: última leitura MANUAL de hoje (é dado real, só não é ao vivo)
        if let last = logs.first, last.timestamp.timeIntervalSinceNow > -4 * 3600 {
            return last.tempFahrenheit
        }
        return nil
    }

    private var isLive: Bool { monitor.currentTempCelsius != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                temperatureCard
                if monitor.isOutOfRange { outOfRangeBanner }
                setpointCard
                sensorCard
                logCard
            }
            .padding(AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Reefer Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            monitor.onReading = { celsius, sensorName in
                // Registro FSMA automático, com throttle de 15 min.
                guard Date().timeIntervalSince(lastAutoLogAt) >= 900 else { return }
                lastAutoLogAt = Date()
                modelContext.insert(ReeferTempLog(
                    tempCelsius: celsius, source: "bluetooth", sensorName: sensorName))
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showingManualEntry) { manualEntrySheet }
    }

    // MARK: - Temperatura atual

    private var temperatureCard: some View {
        VStack(spacing: 8) {
            Text(isLive ? "SENSOR AO VIVO" : "ÚLTIMA LEITURA")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(AppTheme.Colors.textSecondary)
            if let f = displayTempF {
                Text(String(format: "%.1f°F", f))
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundColor(monitor.isOutOfRange ? Color(hex: "#ef4444") : Color(hex: "#22d474"))
                Text(String(format: "%.1f°C", (f - 32) * 5 / 9))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            } else {
                Text("—")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                Text("Sem leitura — conecte um sensor ou registre manualmente")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let at = monitor.lastReadingAt {
                Text(at.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.lg)
    }

    private var outOfRangeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "thermometer.snowflake")
                .font(.system(size: 20, weight: .bold))
            Text("TEMPERATURA FORA DA FAIXA — verifique o reefer")
                .font(.system(size: 13, weight: .black))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(hex: "#dc2626"))
        .cornerRadius(AppTheme.Radius.md)
    }

    // MARK: - Faixa alvo

    private var setpointCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Faixa alvo da carga")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            HStack(spacing: 16) {
                setpointField(label: "Mín", celsius: $monitor.setpointMinCelsius)
                setpointField(label: "Máx", celsius: $monitor.setpointMaxCelsius)
            }
            HStack(spacing: 8) {
                presetButton("Congelado", minF: -10, maxF: 10)
                presetButton("Resfriado", minF: 34, maxF: 39)
                presetButton("Produce", minF: 40, maxF: 55)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.lg)
    }

    private func setpointField(label: String, celsius: Binding<Double>) -> some View {
        let fBinding = Binding<Double>(
            get: { celsius.wrappedValue * 9 / 5 + 32 },
            set: { celsius.wrappedValue = ($0 - 32) * 5 / 9 }
        )
        return HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
            TextField("°F", value: fBinding, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numbersAndPunctuation)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
            Text("°F")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }

    private func presetButton(_ label: String, minF: Double, maxF: Double) -> some View {
        Button {
            monitor.setpointMinCelsius = (minF - 32) * 5 / 9
            monitor.setpointMaxCelsius = (maxF - 32) * 5 / 9
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "#5aa9e6"))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(hex: "#5aa9e6").opacity(0.12))
                .cornerRadius(8)
        }
    }

    // MARK: - Sensor Bluetooth

    private var sensorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sensor Bluetooth")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                statusChip
            }
            Text("Compatível com sensores BLE padrão (Environmental Sensing / Health Thermometer) instalados no baú.")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.Colors.textSecondary)

            switch monitor.status {
            case .connected:
                Button(role: .destructive) { monitor.disconnect() } label: {
                    Label("Desconectar", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 13, weight: .bold))
                }
            case .scanning:
                HStack(spacing: 8) {
                    ProgressView().tint(AppTheme.Colors.accent)
                    Text("Procurando sensores…").font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Spacer()
                    Button("Parar") { monitor.stopScan() }
                        .font(.system(size: 12, weight: .bold))
                }
                sensorList
            case .bluetoothOff:
                Label("Bluetooth desligado — ligue em Ajustes", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#f59e0b"))
            case .unauthorized:
                Label("Permissão de Bluetooth negada — habilite em Ajustes › Trucker Easy", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#f59e0b"))
            default:
                Button { monitor.startScan() } label: {
                    Label("Procurar sensor", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.Colors.accent.opacity(0.15))
                        .cornerRadius(10)
                }
                sensorList
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.lg)
    }

    @ViewBuilder private var sensorList: some View {
        ForEach(monitor.discoveredSensors) { sensor in
            Button { monitor.connect(sensor) } label: {
                HStack {
                    Image(systemName: "sensor.fill")
                        .foregroundColor(Color(hex: "#5aa9e6"))
                    Text(sensor.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(sensor.rssi) dBm")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    private var statusChip: some View {
        let (text, color): (String, Color) = {
            switch monitor.status {
            case .connected(let n): return (n, Color(hex: "#22d474"))
            case .connecting: return ("conectando…", Color(hex: "#f59e0b"))
            case .scanning: return ("buscando", Color(hex: "#5aa9e6"))
            case .bluetoothOff: return ("BT off", Color(hex: "#ef4444"))
            case .unauthorized: return ("sem permissão", Color(hex: "#ef4444"))
            case .idle: return ("sem sensor", AppTheme.Colors.textSecondary)
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12))
            .cornerRadius(6)
    }

    // MARK: - Registro FSMA

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Registro de temperatura")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button { showingManualEntry = true } label: {
                    Label("Registrar", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            Text("FSMA (21 CFR 1.908) exige registros de controle de temperatura no transporte de alimentos.")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.Colors.textSecondary)

            if logs.isEmpty {
                Text("Nenhum registro ainda.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(logs.prefix(20)) { log in
                    HStack {
                        Image(systemName: log.source == "bluetooth" ? "antenna.radiowaves.left.and.right" : "hand.point.up.left.fill")
                            .font(.system(size: 12))
                            .foregroundColor(log.source == "bluetooth" ? Color(hex: "#5aa9e6") : Color(hex: "#c9a84c"))
                            .frame(width: 18)
                        Text(String(format: "%.1f°F", log.tempFahrenheit))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        if let note = log.note, !note.isEmpty {
                            Text(note).font(.system(size: 11))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(AppTheme.Radius.lg)
    }

    private var manualEntrySheet: some View {
        NavigationView {
            Form {
                Section("Leitura do painel do reefer") {
                    HStack {
                        TextField("Ex: 36.5", text: $manualTempF)
                            .keyboardType(.numbersAndPunctuation)
                        Text("°F")
                    }
                }
                Section {
                    Button("Salvar registro") {
                        guard let f = Double(manualTempF.replacingOccurrences(of: ",", with: ".")) else { return }
                        modelContext.insert(ReeferTempLog(
                            tempCelsius: (f - 32) * 5 / 9, source: "manual"))
                        try? modelContext.save()
                        manualTempF = ""
                        showingManualEntry = false
                    }
                    .disabled(Double(manualTempF.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
            .navigationTitle("Registro manual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showingManualEntry = false }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }
}
