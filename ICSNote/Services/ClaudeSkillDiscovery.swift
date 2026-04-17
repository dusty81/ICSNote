import Foundation
import os

/// Discovers Claude Code skills installed on the user's system.
/// Skills live as SKILL.md files inside directories named after each skill,
/// under either ~/.claude/skills/ (user skills) or ~/.claude/plugins/cache/<marketplace>/<plugin>/skills/<skill>/ (plugin skills).
enum ClaudeSkillDiscovery {

    private static let logger = Logger(subsystem: "com.icsnote.app", category: "SkillDiscovery")

    struct DiscoveredSkill: Identifiable, Equatable, Hashable {
        let id: String              // unique ID = source + name (e.g., "plugin:atlassian:triage-issue")
        let name: String            // bare skill name from frontmatter (e.g., "triage-issue")
        let description: String
        let source: String          // "user", "plugin:<plugin-name>", "project"
        let path: URL               // path to the SKILL.md file
    }

    /// Discover skills from:
    /// - ~/.claude/skills/ (user-level)
    /// - ~/.claude/plugins/cache/*/<plugin>/skills/<skill>/SKILL.md (plugin-level)
    /// - optionally, <projectPath>/.claude/skills/ (project-level)
    /// - optionally, user-configured custom paths (scanned recursively for any SKILL.md)
    static func discover(projectPath: String? = nil, customPaths: [String] = []) -> [DiscoveredSkill] {
        var skills: [DiscoveredSkill] = []

        let home = FileManager.default.homeDirectoryForCurrentUser
        let userSkillsDir = home.appendingPathComponent(".claude/skills")
        skills.append(contentsOf: scanSkillsDirectory(userSkillsDir, sourceLabel: "user"))

        let pluginCache = home.appendingPathComponent(".claude/plugins/cache")
        skills.append(contentsOf: scanPluginCache(pluginCache))

        if let projectPath {
            let projectSkillsDir = URL(fileURLWithPath: projectPath).appendingPathComponent(".claude/skills")
            skills.append(contentsOf: scanSkillsDirectory(projectSkillsDir, sourceLabel: "project"))
        }

        // Custom user-configured skill directories — scanned recursively so
        // nested category folders (e.g., Scheduled/daily-X/SKILL.md) are found.
        for path in customPaths {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let label = "custom:\(url.lastPathComponent)"
            skills.append(contentsOf: scanRecursively(at: url, sourceLabel: label))
        }

        // Deduplicate by id (e.g., if a custom path overlaps with a standard one)
        var seen: Set<String> = []
        skills = skills.filter { seen.insert($0.id).inserted }

        // Sort alphabetically by name for display
        skills.sort { $0.name.lowercased() < $1.name.lowercased() }
        return skills
    }

    /// Recursively enumerate a directory for any file named `SKILL.md`.
    /// Used for user-configured paths that may have arbitrary nesting.
    private static func scanRecursively(at root: URL, sourceLabel: String) -> [DiscoveredSkill] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var results: [DiscoveredSkill] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "SKILL.md" else { continue }
            if let skill = parseSkillFile(at: url, source: sourceLabel) {
                results.append(skill)
            }
        }
        return results
    }

    /// Walk a skills/ directory looking for child directories containing SKILL.md.
    private static func scanSkillsDirectory(_ dir: URL, sourceLabel: String) -> [DiscoveredSkill] {
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        var results: [DiscoveredSkill] = []

        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return results
        }

        for entry in entries {
            let skillMD = entry.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillMD.path),
               let skill = parseSkillFile(at: skillMD, source: sourceLabel) {
                results.append(skill)
            }
        }
        return results
    }

    /// Walk the plugin cache to find plugin-provided skills.
    /// Structure: ~/.claude/plugins/cache/<marketplace>/<plugin>/skills/<skill>/SKILL.md
    /// Some plugins may have a versioned intermediate dir, so we walk more permissively.
    private static func scanPluginCache(_ cacheRoot: URL) -> [DiscoveredSkill] {
        guard FileManager.default.fileExists(atPath: cacheRoot.path) else { return [] }
        var results: [DiscoveredSkill] = []

        // Recursively enumerate for any */skills/*/SKILL.md
        guard let enumerator = FileManager.default.enumerator(
            at: cacheRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "SKILL.md" else { continue }
            // Derive plugin label from path: .../cache/<marketplace>/<plugin>/<maybe version>/skills/<skill>/SKILL.md
            let pathComponents = url.pathComponents
            guard let cacheIdx = pathComponents.firstIndex(of: "cache"),
                  pathComponents.count > cacheIdx + 2 else { continue }
            let pluginName = pathComponents[cacheIdx + 2]
            if let skill = parseSkillFile(at: url, source: "plugin:\(pluginName)") {
                results.append(skill)
            }
        }
        return results
    }

    /// Parse a SKILL.md file's YAML frontmatter to extract name and description.
    private static func parseSkillFile(at url: URL, source: String) -> DiscoveredSkill? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        // Expect --- frontmatter block at the top
        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else { return nil }

        var name: String?
        var description: String?
        var i = 1
        while i < lines.count && lines[i] != "---" {
            let line = lines[i]
            if let parsed = parseFrontmatterLine(line) {
                switch parsed.key {
                case "name":        name = parsed.value
                case "description": description = parsed.value
                default: break
                }
            }
            i += 1
        }

        guard let name, !name.isEmpty else { return nil }
        return DiscoveredSkill(
            id: "\(source):\(name)",
            name: name,
            description: description ?? "",
            source: source,
            path: url
        )
    }

    private static func parseFrontmatterLine(_ line: String) -> (key: String, value: String)? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let key = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
        var value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
        // Strip surrounding quotes on string values
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return (key, value)
    }
}
