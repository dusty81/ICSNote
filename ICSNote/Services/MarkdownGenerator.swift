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

    // MARK: - Stripping Helpers

    static func stripZoomInfo(from text: String) -> String {
        let patterns = [
            "(?s)\\[?https?://[^\\]]*zoom\\.[^\\]]*\\.png[^\\n]*\\n.*?International numbers[^\\n]*",
            "(?s)Join Zoom Meeting\\n.*?International numbers[^\\n]*",
            "(?s)Hi there,\\n.*? is inviting you to a scheduled Zoom meeting\\.\\n.*?International numbers[^\\n]*",
        ]
        var result = text
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        return result
    }

    static func stripTeamsInfo(from text: String) -> String {
        let patterns = [
            "(?s)Join Microsoft Teams Meeting.*?Learn more about Teams[^\\n]*",
            "(?s)Microsoft Teams meeting.*?Learn more about Teams[^\\n]*",
            "(?s)________________\\n.*?Microsoft Teams.*?Learn more about Teams[^\\n]*",
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
