import Foundation
import os

enum NoteHistoryStore {
    private static let logger = Logger(subsystem: "com.icsnote.app", category: "NoteHistoryStore")

    static var historyFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("ICSNote", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    static func load() -> [RecentConversion] {
        load(from: historyFileURL)
    }

    static func load(from url: URL) -> [RecentConversion] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([RecentConversion].self, from: data)
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func save(_ entries: [RecentConversion]) {
        save(entries, to: historyFileURL)
    }

    static func save(_ entries: [RecentConversion], to url: URL) {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
