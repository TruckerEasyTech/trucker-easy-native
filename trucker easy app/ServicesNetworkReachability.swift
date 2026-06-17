//
//  ServicesNetworkReachability.swift
//  Monitor leve de conectividade — base da Fase 1 do roteamento offline.
//
//  Por quê: hoje o app só descobre que está sem rede DEPOIS de um timeout (22s no Valhalla).
//  Para o reroute offline do corredor, precisamos de um sinal RÁPIDO de online/offline pra
//  escolher o caminho certo (recalcular no servidor vs. resumir no corredor em cache) sem
//  travar o motorista. Não substitui a tentativa real de rede — é um gatilho de decisão.
//

import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkReachability {
    static let shared = NetworkReachability()

    /// Otimista no boot (true) até o primeiro path chegar — evita falso "offline" na abertura.
    private(set) var isOnline: Bool = true
    /// Conexão cara (celular/hotspot) — útil pra adiar downloads grandes de tiles.
    private(set) var isExpensive: Bool = false
    private(set) var lastChange: Date = .distantPast

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.truckereasy.netpath", qos: .utility)
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                guard let self else { return }
                if self.isOnline != online { self.lastChange = Date() }
                self.isOnline = online
                self.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }
}
