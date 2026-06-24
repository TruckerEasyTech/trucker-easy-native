//
//  UtilitiesLaunchTrace.swift
//  Diagnóstico de launch — NO-OP em Release (compilado fora do bundle de produção).
//  Em DEBUG grava marcos em Documents/launch_trace.txt para análise de freeze.
//

import Foundation

enum LaunchTrace {
#if DEBUG
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
#else
    @inline(__always) static func reset() {}
    @inline(__always) static func mark(_ label: String) {}
#endif
}
