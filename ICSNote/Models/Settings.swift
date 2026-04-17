import Foundation
import SwiftUI

enum PDFConversionMode: String, CaseIterable, Identifiable {
    case never = "Never"
    case always = "Always"
    case ask = "Ask"

    var id: String { rawValue }
}

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

    // Multi-vault configuration
    var vaults: [VaultConfig] { didSet { save() } }
    var activeVaultID: UUID? { didSet { save() } }
    var dropZoneLayout: DropZoneLayout { didSet { save() } }

    // Global settings (apply to all vaults)
    var stripZoom: Bool { didSet { save() } }
    var stripTeams: Bool { didSet { save() } }
    var playSuccessSound: Bool { didSet { save() } }
    var textReplacements: [TextReplacement] { didSet { save() } }
    var notesTemplate: String { didSet { save() } }
    var saveAttachments: Bool { didSet { save() } }
    var mergeEmailThreads: Bool { didSet { save() } }
    var emailNotesTemplate: String { didSet { save() } }
    var pdfConversionMode: PDFConversionMode { didSet { save() } }
    var hooks: [PostSaveHook] { didSet { save() } }
    var customSkillPaths: [String] { didSet { save() } }

    // MARK: - Computed

    var enabledVaults: [VaultConfig] {
        vaults.filter { $0.enabled }
    }

    var isVaultConfigured: Bool {
        !enabledVaults.isEmpty
    }

    var activeVault: VaultConfig? {
        if let id = activeVaultID, let vault = vaults.first(where: { $0.id == id && $0.enabled }) {
            return vault
        }
        return enabledVaults.first
    }

    func vault(id: UUID) -> VaultConfig? {
        vaults.first { $0.id == id }
    }

    /// The layout to actually use, accounting for vault count caps.
    /// Falls back to `.dropdown` when the preferred layout can't fit all enabled vaults.
    var effectiveDropZoneLayout: DropZoneLayout {
        let count = enabledVaults.count
        if count <= dropZoneLayout.maxEnabledVaults {
            return dropZoneLayout
        }
        return .dropdown
    }

    var replacementTuples: [(find: String, replace: String)] {
        textReplacements.filter { !$0.find.isEmpty }.map { (find: $0.find, replace: $0.replace) }
    }

    // MARK: - Init + Migration

    init() {
        let defaults = UserDefaults.standard

        // Global settings
        self.stripZoom = defaults.object(forKey: "stripZoom") as? Bool ?? true
        self.stripTeams = defaults.object(forKey: "stripTeams") as? Bool ?? true
        self.playSuccessSound = defaults.object(forKey: "playSuccessSound") as? Bool ?? true
        self.notesTemplate = defaults.string(forKey: "notesTemplate") ?? "### Action Items\n\n- \n\n### Decisions\n\n- \n\n### Follow-ups\n\n- "
        self.saveAttachments = defaults.object(forKey: "saveAttachments") as? Bool ?? true
        self.mergeEmailThreads = defaults.object(forKey: "mergeEmailThreads") as? Bool ?? true
        self.emailNotesTemplate = defaults.string(forKey: "emailNotesTemplate") ?? ""

        let modeRaw = defaults.string(forKey: "pdfConversionMode") ?? PDFConversionMode.never.rawValue
        self.pdfConversionMode = PDFConversionMode(rawValue: modeRaw) ?? .never

        if let data = defaults.data(forKey: "hooks"),
           let decoded = try? JSONDecoder().decode([PostSaveHook].self, from: data) {
            self.hooks = decoded
        } else {
            self.hooks = []
        }
        self.customSkillPaths = defaults.stringArray(forKey: "customSkillPaths") ?? []

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

        // Drop zone layout
        let layoutRaw = defaults.string(forKey: "dropZoneLayout") ?? DropZoneLayout.dropdown.rawValue
        self.dropZoneLayout = DropZoneLayout(rawValue: layoutRaw) ?? .dropdown

        // Vaults — try new format first, fall back to migrating the old single-vault settings
        if let data = defaults.data(forKey: "vaults"),
           let decoded = try? JSONDecoder().decode([VaultConfig].self, from: data) {
            self.vaults = decoded
        } else {
            // Migrate from old single-vault settings if present
            let oldPath = defaults.string(forKey: "vaultPath") ?? ""
            if !oldPath.isEmpty {
                let oldSubfolder = defaults.string(forKey: "subfolder") ?? ""
                let oldEmailSub = defaults.string(forKey: "emailSubfolder") ?? "Emails"
                let oldAttachSub = defaults.string(forKey: "attachmentSubfolder") ?? "attachments"
                let name = (oldPath as NSString).lastPathComponent
                self.vaults = [VaultConfig(
                    name: name,
                    path: oldPath,
                    enabled: true,
                    subfolder: oldSubfolder,
                    emailSubfolder: oldEmailSub,
                    attachmentSubfolder: oldAttachSub
                )]
            } else {
                self.vaults = []
            }
        }

        // Active vault
        if let idString = defaults.string(forKey: "activeVaultID"),
           let uuid = UUID(uuidString: idString) {
            self.activeVaultID = uuid
        } else {
            self.activeVaultID = vaults.first(where: { $0.enabled })?.id
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(stripZoom, forKey: "stripZoom")
        defaults.set(stripTeams, forKey: "stripTeams")
        defaults.set(playSuccessSound, forKey: "playSuccessSound")
        defaults.set(notesTemplate, forKey: "notesTemplate")
        defaults.set(saveAttachments, forKey: "saveAttachments")
        defaults.set(mergeEmailThreads, forKey: "mergeEmailThreads")
        defaults.set(emailNotesTemplate, forKey: "emailNotesTemplate")
        defaults.set(pdfConversionMode.rawValue, forKey: "pdfConversionMode")
        defaults.set(dropZoneLayout.rawValue, forKey: "dropZoneLayout")
        defaults.set(activeVaultID?.uuidString, forKey: "activeVaultID")
        if let data = try? JSONEncoder().encode(textReplacements) {
            defaults.set(data, forKey: "textReplacements")
        }
        if let data = try? JSONEncoder().encode(vaults) {
            defaults.set(data, forKey: "vaults")
        }
        if let data = try? JSONEncoder().encode(hooks) {
            defaults.set(data, forKey: "hooks")
        }
        defaults.set(customSkillPaths, forKey: "customSkillPaths")
    }
}
