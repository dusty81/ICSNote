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
    var playSuccessSound: Bool { didSet { save() } }
    var textReplacements: [TextReplacement] { didSet { save() } }
    var notesTemplate: String { didSet { save() } }

    // Email settings
    var emailSubfolder: String { didSet { save() } }
    var saveAttachments: Bool { didSet { save() } }
    var attachmentSubfolder: String { didSet { save() } }
    var mergeEmailThreads: Bool { didSet { save() } }
    var emailNotesTemplate: String { didSet { save() } }

    var outputDirectoryURL: URL? {
        guard !vaultPath.isEmpty else { return nil }
        var url = URL(fileURLWithPath: vaultPath)
        if !subfolder.isEmpty { url = url.appendingPathComponent(subfolder) }
        return url
    }

    var emailOutputDirectoryURL: URL? {
        guard !vaultPath.isEmpty else { return nil }
        var url = URL(fileURLWithPath: vaultPath)
        if !emailSubfolder.isEmpty { url = url.appendingPathComponent(emailSubfolder) }
        return url
    }

    var attachmentDirectoryURL: URL? {
        guard !vaultPath.isEmpty else { return nil }
        var url = URL(fileURLWithPath: vaultPath)
        if !attachmentSubfolder.isEmpty { url = url.appendingPathComponent(attachmentSubfolder) }
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
        self.playSuccessSound = defaults.object(forKey: "playSuccessSound") as? Bool ?? true
        self.notesTemplate = defaults.string(forKey: "notesTemplate") ?? "### Action Items\n\n- \n\n### Decisions\n\n- \n\n### Follow-ups\n\n- "
        self.emailSubfolder = defaults.string(forKey: "emailSubfolder") ?? "Emails"
        self.saveAttachments = defaults.object(forKey: "saveAttachments") as? Bool ?? true
        self.attachmentSubfolder = defaults.string(forKey: "attachmentSubfolder") ?? "attachments"
        self.mergeEmailThreads = defaults.object(forKey: "mergeEmailThreads") as? Bool ?? true
        self.emailNotesTemplate = defaults.string(forKey: "emailNotesTemplate") ?? ""
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
        defaults.set(playSuccessSound, forKey: "playSuccessSound")
        defaults.set(notesTemplate, forKey: "notesTemplate")
        defaults.set(emailSubfolder, forKey: "emailSubfolder")
        defaults.set(saveAttachments, forKey: "saveAttachments")
        defaults.set(attachmentSubfolder, forKey: "attachmentSubfolder")
        defaults.set(mergeEmailThreads, forKey: "mergeEmailThreads")
        defaults.set(emailNotesTemplate, forKey: "emailNotesTemplate")
        if let data = try? JSONEncoder().encode(textReplacements) {
            defaults.set(data, forKey: "textReplacements")
        }
    }
}
