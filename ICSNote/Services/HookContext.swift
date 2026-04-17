import Foundation

/// Captures everything a hook needs to execute — the saved note's location,
/// vault, type, and metadata. Supports {{variable}} substitution in templates.
struct HookContext {
    let filePath: String
    let filename: String
    let vaultID: UUID
    let vaultName: String
    let vaultPath: String
    let noteType: HookTrigger      // .meeting or .email (never .any)
    let title: String
    let date: Date
    let organizer: String?          // meeting only
    let attendees: [String]         // meeting only
    let from: String?               // email only
    let recipients: [String]        // email only
    let attachmentPaths: [String]   // email only, absolute paths

    // MARK: - Factories

    static func meeting(event: CalendarEvent, vault: VaultConfig, outputURL: URL) -> HookContext {
        HookContext(
            filePath: outputURL.path,
            filename: outputURL.lastPathComponent,
            vaultID: vault.id,
            vaultName: vault.name,
            vaultPath: vault.path,
            noteType: .meeting,
            title: event.title,
            date: event.startDate,
            organizer: event.organizer?.name,
            attendees: event.attendees.map { $0.name },
            from: nil,
            recipients: [],
            attachmentPaths: []
        )
    }

    static func email(email: EmailMessage, vault: VaultConfig, outputURL: URL, attachmentPaths: [String]) -> HookContext {
        HookContext(
            filePath: outputURL.path,
            filename: outputURL.lastPathComponent,
            vaultID: vault.id,
            vaultName: vault.name,
            vaultPath: vault.path,
            noteType: .email,
            title: email.cleanSubject,
            date: email.date,
            organizer: nil,
            attendees: [],
            from: email.from.name,
            recipients: email.to.map { $0.name.isEmpty ? $0.email : $0.name },
            attachmentPaths: attachmentPaths
        )
    }

    // MARK: - Variable Substitution

    /// Replace `{{variable}}` tokens in a template. Unknown variables are left as-is.
    func substitute(in template: String) -> String {
        var result = template
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current

        let variables: [String: String] = [
            "file_path":    filePath,
            "filename":     filename,
            "vault_name":   vaultName,
            "vault_path":   vaultPath,
            "note_type":    noteType.rawValue,
            "title":        title,
            "date":         {
                dateFormatter.dateFormat = "yyyy-MM-dd"
                return dateFormatter.string(from: date)
            }(),
            "date_iso":     ISO8601DateFormatter().string(from: date),
            "organizer":    organizer ?? "",
            "attendees":    attendees.joined(separator: ", "),
            "from":         from ?? "",
            "recipients":   recipients.joined(separator: ", "),
            "attachments":  attachmentPaths.joined(separator: ", "),
        ]

        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    /// The human-readable list of supported variable names, for UI help text.
    /// Note: `skill_name`, `skill_path`, and `skill_content` are substituted
    /// by HookRunner (not HookContext) since they depend on skill discovery.
    static let availableVariables: [String] = [
        "file_path", "filename",
        "vault_name", "vault_path",
        "note_type", "title", "date", "date_iso",
        "organizer", "attendees",
        "from", "recipients", "attachments",
        "skill_name", "skill_path", "skill_content",
    ]
}
