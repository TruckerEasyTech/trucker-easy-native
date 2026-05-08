import Foundation

enum DeveloperDebugLog {
    static func appendNDJSONLine(_ line: String) {
        #if DEBUG
        let path = NSHomeDirectory() + "/Desktop/trucker easy app/.cursor/developer-debug.log"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    return
                }
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        #endif
    }
}
