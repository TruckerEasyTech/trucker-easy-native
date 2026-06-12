//
//  UtilitiesMainThreadWatchdog.swift
//  trucker easy app
//
//  DEBUG-ONLY: vigia a main thread. Se ela ficar bloqueada por > 5s (tela congelada),
//  imprime automaticamente o backtrace da main thread no console — equivalente ao `bt`
//  do lldb, sem precisar pausar manualmente. Remover antes do release final se quiser
//  (já é totalmente compilado fora em builds Release via #if DEBUG).
//

#if DEBUG && arch(arm64)
import Foundation
import Darwin

enum MainThreadWatchdog {
    private static var started = false
    private static let lock = NSLock()
    private static var lastPong = Date()
    private static var mainThreadPort: thread_act_t = 0

    /// Chamar UMA vez, na main thread, no início do app.
    static func start() {
        assert(Thread.isMainThread, "MainThreadWatchdog.start() deve rodar na main thread")
        guard !started else { return }
        started = true
        mainThreadPort = mach_thread_self()

        Thread.detachNewThread {
            Thread.current.name = "MainThreadWatchdog"
            while true {
                DispatchQueue.main.async {
                    lock.lock(); lastPong = Date(); lock.unlock()
                }
                Thread.sleep(forTimeInterval: 1.0)
                lock.lock(); let silence = Date().timeIntervalSince(lastPong); lock.unlock()
                if silence > 5 {
                    print("🚨 [Watchdog] MAIN THREAD BLOQUEADA há \(Int(silence))s — backtrace dela:")
                    dumpMainThreadBacktrace()
                    // Evita spam: espera antes de imprimir de novo se continuar travada.
                    Thread.sleep(forTimeInterval: 15)
                }
            }
        }
        print("[Watchdog] ativo — congelamentos da UI > 5s serão reportados com backtrace")
    }

    /// Lê pc/fp da main thread via Mach e caminha a cadeia de frame pointers (arm64).
    /// Seguro aqui: a thread está parada (bloqueada), então a pilha não muda sob nós.
    private static func dumpMainThreadBacktrace() {
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &state) { statePtr in
            statePtr.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(mainThreadPort, ARM_THREAD_STATE64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            print("  [Watchdog] thread_get_state falhou (\(kr)) — sem backtrace")
            return
        }

        var addresses: [UInt64] = [state.__pc, state.__lr]
        var fp = state.__fp
        var iterations = 0
        while fp != 0, fp % 8 == 0, iterations < 64 {
            iterations += 1
            guard let frame = UnsafeRawPointer(bitPattern: UInt(fp)) else { break }
            let nextFp = frame.load(fromByteOffset: 0, as: UInt64.self)
            let lr = frame.load(fromByteOffset: 8, as: UInt64.self)
            if lr == 0 { break }
            addresses.append(lr)
            // fp deve crescer (pilha desce em endereços) — protege contra loop corrompido.
            if nextFp <= fp { break }
            fp = nextFp
        }

        for (index, rawAddress) in addresses.enumerated() {
            // Strip de pointer authentication (PAC) — bits altos não são endereço real.
            let address = rawAddress & 0x0000_000F_FFFF_FFFF
            var info = Dl_info()
            if dladdr(UnsafeRawPointer(bitPattern: UInt(address)), &info) != 0 {
                let symbol = info.dli_sname.map { String(cString: $0) }
                let image = info.dli_fname.map {
                    (String(cString: $0) as NSString).lastPathComponent
                } ?? "?"
                if let symbol {
                    let offset = address &- UInt64(UInt(bitPattern: info.dli_saddr))
                    print(String(format: "  [Watchdog] %2d %@ %@ + %llu", index, image, symbol, offset))
                } else {
                    print(String(format: "  [Watchdog] %2d %@ 0x%llx", index, image, address))
                }
            } else {
                print(String(format: "  [Watchdog] %2d 0x%llx", index, address))
            }
        }
    }
}
#endif
