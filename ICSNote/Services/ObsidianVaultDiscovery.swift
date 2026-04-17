import Foundation
import os

/// Discovers Obsidian vaults from Obsidian's own configuration file.
enum ObsidianVaultDiscovery {

    private static let logger = Logger(subsystem: "com.icsnote.app", category: "VaultDiscovery")

    /// Path to Obsidian's vault registry.
    static var obsidianConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
    }

    /// A discovered vault from Obsidian's registry.
    struct DiscoveredVault: Equatable {
        let path: String
        let name: String         // Last path component
        let lastOpened: Date     // Converted from Obsidian's `ts` (ms since epoch)
    }

    /// Parse Obsidian's config file and return all registered vaults.
    /// Returns empty array if Obsidian isn't installed or the file can't be read.
    static func discover() -> [DiscoveredVault] {
        let url = obsidianConfigURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.info("Obsidian config not found at \(url.path, privacy: .public)")
            return []
        }

        guard let data = try? Data(contentsOf: url) else {
            logger.error("Could not read Obsidian config")
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = json["vaults"] as? [String: [String: Any]] else {
            logger.error("Could not parse Obsidian config")
            return []
        }

        var result: [DiscoveredVault] = []
        for (_, vaultInfo) in vaults {
            guard let path = vaultInfo["path"] as? String else { continue }
            // Skip vaults whose path no longer exists on disk
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let name = (path as NSString).lastPathComponent
            let tsMillis = (vaultInfo["ts"] as? Double) ?? 0
            let lastOpened = Date(timeIntervalSince1970: tsMillis / 1000)

            result.append(DiscoveredVault(path: path, name: name, lastOpened: lastOpened))
        }

        // Sort by most recently opened first
        result.sort { $0.lastOpened > $1.lastOpened }
        return result
    }
}
