import Foundation
import Darwin

final class MihomoPidStore {

    private let fileURL: URL

    init(bundleID: String = "com.aote.clashy") {
        let dir = URL(fileURLWithPath: "/var/run", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("\(bundleID).mihomo.pid")
    }

    struct Record: Codable {
        let pid: Int32
        let executablePath: String
        let startedAt: TimeInterval
    }

    func write(pid: Int32, executablePath: String) {
        let record = Record(
            pid: pid,
            executablePath: executablePath,
            startedAt: Date().timeIntervalSince1970
        )
        do {
            let data = try JSONEncoder().encode(record)
            // .atomic 会写临时文件再 rename，避免读到半截内容
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[pidstore] write failed: \(error)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func load() -> Record? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
}