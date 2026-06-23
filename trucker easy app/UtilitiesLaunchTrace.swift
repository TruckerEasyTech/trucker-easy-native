//
//  UtilitiesLaunchTrace.swift
//  Diagnóstico de launch: grava marcos com timestamp em Documents/launch_trace.txt.
//  Escrita numa fila de background → captura o ÚLTIMO marco antes de um eventual freeze
//  da main thread. Puxável do device via `devicectl device copy from` (sem root).
//  TEMPORÁRIO p/ diagnosticar a tela preta no device — remover depois.
//

import Foundation

enum LaunchTrace {
    private static let queue = DispatchQueue(label: "com.truckereasy.launchtrace")
    private static var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("launch_trace.txt")
    }

    static func reset() {
        queue.async {
            guard let url = fileURL else { return }
            let header = "=== launch @ \(Date()) ===\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func mark(_ label: String) {
        let t = Date().timeIntervalSince1970
        queue.async {
            guard let url = fileURL else { return }
            let line = String(format: "%.3f  %@\n", t, label)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                if let d = line.data(using: .utf8) { h.write(d) }
                try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
