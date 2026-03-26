import Foundation
import SwiftUI

struct TextReplacement: Codable, Identifiable, Equatable {
    let id: UUID
    var find: String
    var replace: String

    init(id: UUID = UUID(), find: String = "", replace: String = "") {
        self.id = id
        self.find = find
        self.replace = replace
    }
}

@MainActor
@Observable
final class AppSettings {

    var vaultPath: String { didSet { save() } }
    var subfolder: String { didSet { save() } }
    var stripZoom: Bool { didSet { save() } }
    var stripTeams: Bool { didSet { save() } }
    var textReplacements: [TextReplacement] { didSet { save() } }
    var notesTemplate: String { didSet { save() } }

    var outputDirectoryURL: URL? {
        guard !vaultPath.isEmpty else { return nil }
        var url = URL(fileURLWithPath: vaultPath)
        if !subfolder.isEmpty { url = url.appendingPathComponent(subfolder) }
        return url
    }

    var isVaultConfigured: Bool { !vaultPath.isEmpty }

    var replacementTuples: [(find: String, replace: String)] {
        textReplacements.filter { !$0.find.isEmpty }.map { (find: $0.find, replace: $0.replace) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.vaultPath = defaults.string(forKey: "vaultPath") ?? ""
        self.subfolder = defaults.string(forKey: "subfolder") ?? ""
        self.stripZoom = defaults.object(forKey: "stripZoom") as? Bool ?? true
        self.stripTeams = defaults.object(forKey: "stripTeams") as? Bool ?? true
        self.notesTemplate = defaults.string(forKey: "notesTemplate") ?? "### Action Items\n\n- \n\n### Decisions\n\n- \n\n### Follow-ups\n\n- "
        if let data = defaults.data(forKey: "textReplacements"),
           let decoded = try? JSONDecoder().decode([TextReplacement].self, from: data) {
            self.textReplacements = decoded
        } else {
            self.textReplacements = [
                TextReplacement(find: "1:1", replace: "One on One"),
                TextReplacement(find: "Fwd: ", replace: ""),
                TextReplacement(find: "RE: ", replace: ""),
            ]
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(vaultPath, forKey: "vaultPath")
        defaults.set(subfolder, forKey: "subfolder")
        defaults.set(stripZoom, forKey: "stripZoom")
        defaults.set(stripTeams, forKey: "stripTeams")
        defaults.set(notesTemplate, forKey: "notesTemplate")
        if let data = try? JSONEncoder().encode(textReplacements) {
            defaults.set(data, forKey: "textReplacements")
        }
    }
}
