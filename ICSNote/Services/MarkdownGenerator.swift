import Foundation

enum MarkdownGenerator {

    static func generate(
        event: CalendarEvent,
        stripZoom: Bool = false,
        stripTeams: Bool = false,
        textReplacements: [(find: String, replace: String)] = [],
        notesTemplate: String = ""
    ) -> String {
        var sections: [String] = []
        sections.append(generateFrontmatter(event: event))
        sections.append(generateMetadataTable(event: event))
        sections.append(generateAttendeesSection(event: event))
        sections.append(generateDescriptionSection(event: event, stripZoom: stripZoom, stripTeams: stripTeams))
        sections.append(generateNotesSection(template: notesTemplate))
        return sections.joined(separator: "\n")
    }

    static func generateFilename(
        event: CalendarEvent,
        textReplacements: [(find: String, replace: String)] = []
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let dateString = dateFormatter.string(from: event.startDate)
        var title = event.title
        for replacement in textReplacements {
            title = title.replacingOccurrences(of: replacement.find, with: replacement.replace)
        }
        title = sanitizeFilename(title)
        return "\(dateString) \(title).md"
    }

    private static func generateFrontmatter(event: CalendarEvent) -> String {
        var lines: [String] = ["---"]
        lines.append("title: \"\(escapeFrontmatter(event.title))\"")
        lines.append("date: \(formatDateOnly(event.startDate))")
        lines.append("time: \"\(formatTimeRange(start: event.startDate, end: event.endDate))\"")
        if let organizer = event.organizer {
            lines.append("organizer: \"\(escapeFrontmatter(organizer.name))\"")
        }
        if !event.attendees.isEmpty {
            lines.append("attendees:")
            for attendee in event.attendees {
                lines.append("  - name: \"\(escapeFrontmatter(attendee.name))\"")
                lines.append("    status: \(attendee.status.label)")
            }
        }
        if !event.location.isEmpty {
            lines.append("location: \"\(escapeFrontmatter(event.location))\"")
        }
        if !event.categories.isEmpty {
            lines.append("categories:")
            for category in event.categories {
                lines.append("  - \"\(escapeFrontmatter(category))\"")
            }
        }
        if !event.status.isEmpty {
            lines.append("status: \"\(event.status.capitalized)\"")
        }
        lines.append("type: meeting")
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func generateMetadataTable(event: CalendarEvent) -> String {
        var lines: [String] = []
        lines.append("## Meeting Details")
        lines.append("")
        lines.append("| Field | Value |")
        lines.append("|-------|-------|")
        lines.append("| **Subject** | \(event.title) |")
        if let organizer = event.organizer {
            lines.append("| **Organizer** | \(organizer.name) (\(organizer.email)) |")
        }
        lines.append("| **Date** | \(formatFullDate(event.startDate)) |")
        lines.append("| **Time** | \(formatTimeRange(start: event.startDate, end: event.endDate)) |")
        if !event.location.isEmpty {
            lines.append("| **Location** | \(formatLocationDisplay(event.location)) |")
        }
        if !event.status.isEmpty {
            lines.append("| **Status** | \(event.status.capitalized) |")
        }
        if !event.categories.isEmpty {
            lines.append("| **Categories** | \(event.categories.joined(separator: ", ")) |")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func generateAttendeesSection(event: CalendarEvent) -> String {
        guard !event.attendees.isEmpty else { return "" }
        var lines: [String] = ["## Attendees", ""]
        for attendee in event.attendees {
            let emailPart = attendee.email.isEmpty ? "" : " (\(attendee.email))"
            lines.append("- \(attendee.status.emoji) \(attendee.name)\(emailPart)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func generateDescriptionSection(
        event: CalendarEvent,
        stripZoom: Bool,
        stripTeams: Bool
    ) -> String {
        guard !event.description.isEmpty else { return "" }
        var description = event.description
        var strippedNotes: [String] = []
        if stripZoom {
            let cleaned = stripZoomInfo(from: description)
            if cleaned != description {
                description = cleaned
                strippedNotes.append("*Zoom meeting information removed.*")
            }
        }
        if stripTeams {
            let cleaned = stripTeamsInfo(from: description)
            if cleaned != description {
                description = cleaned
                strippedNotes.append("*Microsoft Teams meeting information removed.*")
            }
        }
        description = description
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = ["## Description", "", description]
        if !strippedNotes.isEmpty {
            lines.append("")
            lines.append(contentsOf: strippedNotes)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func generateNotesSection(template: String) -> String {
        var lines: [String] = ["## Notes", ""]
        if !template.isEmpty {
            lines.append(template)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Email Generation

    static func generate(
        email: EmailMessage,
        textReplacements: [(find: String, replace: String)] = [],
        notesTemplate: String = "",
        attachmentFilenames: [String]? = nil
    ) -> String {
        var sections: [String] = []
        sections.append(generateEmailFrontmatter(email: email, attachmentFilenames: attachmentFilenames))
        sections.append(generateEmailMetadataTable(email: email))
        sections.append(generateBodySection(body: email.body))
        // Use explicit filename list if provided (includes converted PDFs);
        // otherwise fall back to the email's real attachments.
        let filenames: [String]
        if let attachmentFilenames {
            filenames = attachmentFilenames
        } else {
            filenames = email.attachments.filter { !$0.isInline }.map(\.filename)
        }
        if !filenames.isEmpty {
            sections.append(generateAttachmentsSection(filenames: filenames))
        }
        sections.append(generateNotesSection(template: notesTemplate))
        return sections.joined(separator: "\n")
    }

    static func generateFilename(
        email: EmailMessage,
        textReplacements: [(find: String, replace: String)] = []
    ) -> String {
        let dateString = formatDateOnly(email.date)
        var title = email.cleanSubject
        for replacement in textReplacements {
            title = title.replacingOccurrences(of: replacement.find, with: replacement.replace)
        }
        title = sanitizeFilename(title)
        return "\(dateString) \(title).md"
    }

    /// Update an existing email note with a new message, moving the old body
    /// into a collapsed "Previous Messages" section.
    static func updateNoteWithNewMessage(existingContent: String, newEmail: EmailMessage) -> String {
        var result = existingContent

        // 1. Update frontmatter date and from to newest message
        result = updateFrontmatterField(in: result, field: "date", value: formatDateOnly(newEmail.date))
        result = updateFrontmatterField(in: result, field: "time", value: "\"\(formatTime(newEmail.date))\"")
        result = updateFrontmatterField(in: result, field: "from", value: "\"\(escapeFrontmatter(newEmail.from.name))\"")

        // 2. Extract the current ## Body content
        let oldBody = extractSection(named: "Body", from: result)
        let oldFrom = extractFrontmatterField(named: "from", from: existingContent)
            .replacingOccurrences(of: "\"", with: "")
        let oldDate = extractFrontmatterField(named: "date", from: existingContent)
        let oldTime = extractFrontmatterField(named: "time", from: existingContent)
            .replacingOccurrences(of: "\"", with: "")

        // 3. Build the callout block for the old message
        let senderLabel = oldFrom.isEmpty ? "Previous sender" : oldFrom
        let dateLabel = oldDate.isEmpty ? "" : " — \(oldDate)"
        let timeLabel = oldTime.isEmpty ? "" : " \(oldTime)"
        let calloutHeader = "> [!quote]- \(senderLabel)\(dateLabel)\(timeLabel)"
        let calloutBody = oldBody.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
        let newCallout = "\(calloutHeader)\n\(calloutBody)"

        // 4. Extract existing Previous Messages section (if any)
        let existingPrevious = extractSection(named: "Previous Messages", from: result)

        // 5. Replace ## Body with new email body
        result = replaceSection(named: "Body", in: result, with: newEmail.body.trimmingCharacters(in: .whitespacesAndNewlines))

        // 6. Insert/update ## Previous Messages before ## Notes
        let previousContent = existingPrevious.isEmpty
            ? newCallout
            : "\(newCallout)\n\n\(existingPrevious)"

        if result.contains("## Previous Messages") {
            result = replaceSection(named: "Previous Messages", in: result, with: previousContent)
        } else {
            // Insert before ## Notes
            result = result.replacingOccurrences(of: "## Notes", with: "## Previous Messages\n\n\(previousContent)\n\n## Notes")
        }

        return result
    }

    // MARK: - Email Frontmatter

    private static func generateEmailFrontmatter(email: EmailMessage, attachmentFilenames: [String]? = nil) -> String {
        var lines: [String] = ["---"]
        lines.append("title: \"\(escapeFrontmatter(email.cleanSubject))\"")
        lines.append("date: \(formatDateOnly(email.date))")
        lines.append("time: \"\(formatTime(email.date))\"")
        lines.append("from: \"\(escapeFrontmatter(email.from.name))\"")
        if !email.to.isEmpty {
            lines.append("to:")
            for contact in email.to {
                let display = contact.name.isEmpty ? contact.email : contact.name
                lines.append("  - \"\(escapeFrontmatter(display))\"")
            }
        }
        if !email.cc.isEmpty {
            lines.append("cc:")
            for contact in email.cc {
                let display = contact.name.isEmpty ? contact.email : contact.name
                lines.append("  - \"\(escapeFrontmatter(display))\"")
            }
        }
        lines.append("subject: \"\(escapeFrontmatter(email.subject))\"")
        let filenames: [String]
        if let attachmentFilenames {
            filenames = attachmentFilenames
        } else {
            filenames = email.attachments.filter { !$0.isInline }.map { $0.filename }
        }
        if !filenames.isEmpty {
            lines.append("attachments:")
            for name in filenames {
                lines.append("  - \"\(escapeFrontmatter(name))\"")
            }
        }
        lines.append("type: email")
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func generateEmailMetadataTable(email: EmailMessage) -> String {
        var lines: [String] = []
        lines.append("## Email Details")
        lines.append("")
        lines.append("| Field | Value |")
        lines.append("|-------|-------|")
        let fromDisplay = email.from.email.isEmpty
            ? email.from.name
            : "\(email.from.name) (\(email.from.email))"
        lines.append("| **From** | \(fromDisplay) |")
        if !email.to.isEmpty {
            let toDisplay = email.to.map { $0.name.isEmpty ? $0.email : $0.name }.joined(separator: ", ")
            lines.append("| **To** | \(toDisplay) |")
        }
        if !email.cc.isEmpty {
            let ccDisplay = email.cc.map { $0.name.isEmpty ? $0.email : $0.name }.joined(separator: ", ")
            lines.append("| **CC** | \(ccDisplay) |")
        }
        lines.append("| **Date** | \(formatFullDate(email.date)) |")
        lines.append("| **Time** | \(formatTime(email.date)) |")
        lines.append("| **Subject** | \(email.subject) |")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func generateAttachmentsSection(filenames: [String]) -> String {
        var lines: [String] = ["## Attachments", ""]
        for filename in filenames {
            // Embed PDFs inline with ![[...]], link other files with [[...]]
            if filename.lowercased().hasSuffix(".pdf") {
                lines.append("- ![[\(filename)]]")
            } else {
                lines.append("- [[\(filename)]]")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func generateBodySection(body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "## Body\n\n\(trimmed)\n"
    }

    // MARK: - Section Manipulation (for thread merging)

    /// Extract the content between ## SectionName and the next ## heading (or end of file).
    private static func extractSection(named name: String, from content: String) -> String {
        let header = "## \(name)"
        guard let headerRange = content.range(of: header) else { return "" }
        let afterHeader = content[headerRange.upperBound...]
        // Find the next ## heading
        if let nextHeading = afterHeader.range(of: "\n## ", range: afterHeader.startIndex..<afterHeader.endIndex) {
            return String(afterHeader[afterHeader.startIndex..<nextHeading.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(afterHeader).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replace the content of a section (between ## heading and next ## heading).
    private static func replaceSection(named name: String, in content: String, with newContent: String) -> String {
        let header = "## \(name)"
        guard let headerRange = content.range(of: header) else { return content }
        let afterHeader = content[headerRange.upperBound...]
        if let nextHeading = afterHeader.range(of: "\n## ", range: afterHeader.startIndex..<afterHeader.endIndex) {
            let before = String(content[content.startIndex..<headerRange.upperBound])
            let after = String(content[nextHeading.lowerBound...])
            return "\(before)\n\n\(newContent)\n\(after)"
        }
        // Section is at end of file
        let before = String(content[content.startIndex..<headerRange.upperBound])
        return "\(before)\n\n\(newContent)\n"
    }

    /// Extract a frontmatter field value.
    private static func extractFrontmatterField(named field: String, from content: String) -> String {
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("\(field):") {
                return String(line.dropFirst(field.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    /// Update a frontmatter field value in-place.
    private static func updateFrontmatterField(in content: String, field: String, value: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        for line in lines {
            if line.hasPrefix("\(field):") {
                result.append("\(field): \(value)")
            } else {
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Stripping Helpers

    static func stripZoomInfo(from text: String) -> String {
        // Zoom blocks from Outlook come in various formats:
        // 1. Plain: "Join Zoom Meeting\nhttps://...zoom.us/...\nMeeting ID: ...\nDial:...\nInternational numbers"
        // 2. SafeLinks: URLs wrapped in <https://nam11.safelinks.protection.outlook.com/?url=...>
        // 3. H.323/SIP: "Join from an H.323/SIP room system\nH.323:...\nSIP:...\nPasscode:"
        // 4. Zoom logo: "[https://...zoom...png]<safelink>"
        //
        // Strategy: find the START of the Zoom block, then consume everything through
        // the end markers (International numbers, SIP passcode, or last Zoom-related line)

        let startPatterns = [
            "~={3,}~\\nYou have been invited to a Zoom meeting",  // ~===~ delimited block
            "\\[https?://[^\\]]*zoom[^\\]]*\\.png\\]",            // Zoom logo image reference
            "Hi there,\\n.*? is inviting you to a scheduled Zoom meeting\\.",
            "You have been invited to a Zoom meeting",
            "Join Zoom Meeting",
        ]

        // Order matters: try the FURTHEST end markers first so lazy .*?
        // consumes the full Zoom block when both H.323/SIP and phone
        // dial-in sections are present.
        let endPatterns = [
            "\\d+@zoomcrc\\.com\\nPasscode:\\n\\d+",      // SIP ending with passcode
            "\\d+@zoomcrc\\.com",                         // SIP ending
            "~={3,}~",                                    // ~===~ delimited block end
            "Find your local number[^\\n]*",              // Alternative dial-in ending
            "International numbers[^\\n]*",               // Phone dial-in ending
        ]

        var result = text
        for startPattern in startPatterns {
            for endPattern in endPatterns {
                let pattern = "(?s)\(startPattern).*?\(endPattern)"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let newResult = regex.stringByReplacingMatches(
                        in: result,
                        range: NSRange(result.startIndex..., in: result),
                        withTemplate: ""
                    )
                    if newResult != result {
                        return newResult // Found and stripped — done
                    }
                }
            }
        }

        return result
    }

    static func stripTeamsInfo(from text: String) -> String {
        let patterns = [
            // Underscore-delimited block (external orgs, SafeLinks format).
            // Outer delimiters are ~80 chars, inner separator is ~32 chars,
            // so _{40,} skips the inner one and matches the closing delimiter.
            "(?s)_{40,}\\nMicrosoft Teams meeting.*?_{40,}",
            // Standard internal Teams format
            "(?s)Join Microsoft Teams Meeting.*?Learn more about Teams[^\\n]*",
            "(?s)Microsoft Teams meeting.*?Learn more about Teams[^\\n]*",
            "(?s)________________\\n.*?Microsoft Teams.*?Learn more about Teams[^\\n]*",
            // Fallback: Teams block ending with Reset dial-in PIN
            "(?s)Microsoft Teams meeting\\nJoin:.*?Reset dial-in PIN[^\\n]*",
            // Fallback: Teams block ending with Meeting options
            "(?s)Microsoft Teams meeting\\nJoin:.*?Meeting options[^\\n]*",
        ]
        var result = text
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        return result
    }

    // MARK: - Filename Helpers

    static func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/:\\*?\"<>|")
        let sanitized = name.unicodeScalars
            .filter { !invalidChars.contains($0) }
            .map { Character($0) }
        return String(sanitized).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Formatting Helpers

    private static func formatDateOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    private static func formatFullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    private static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone.current
        let tz = DateFormatter()
        tz.dateFormat = "zzz"
        tz.timeZone = TimeZone.current
        return "\(f.string(from: date)) (\(tz.string(from: date)))"
    }

    private static func formatTimeRange(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone.current
        let tz = DateFormatter()
        tz.dateFormat = "zzz"
        tz.timeZone = TimeZone.current
        return "\(f.string(from: start)) - \(f.string(from: end)) (\(tz.string(from: start)))"
    }

    private static func formatLocationDisplay(_ location: String) -> String {
        if location.lowercased().contains("zoom.us") {
            return "[Zoom Meeting](\(location))"
        }
        if location.lowercased().contains("teams.microsoft.com") {
            return "[Teams Meeting](\(location))"
        }
        return location
    }

    private static func escapeFrontmatter(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
