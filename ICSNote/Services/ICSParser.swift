import Foundation

enum ICSParseError: LocalizedError {
    case noEventFound
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .noEventFound:
            "No calendar events found in file"
        case .invalidFormat(let detail):
            "Could not parse calendar file: \(detail)"
        }
    }
}

enum ICSParser {

    // MARK: - Public API

    static func parse(_ text: String) throws -> CalendarEvent {
        let unfolded = unfoldLines(text)
        let vevents = extractVEvents(from: unfolded)

        guard !vevents.isEmpty else {
            throw ICSParseError.noEventFound
        }

        let selected = selectNextOccurrence(from: vevents)
        return parseVEvent(selected)
    }

    // MARK: - Line Unfolding

    static func unfoldLines(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n ", with: "")
        result = result.replacingOccurrences(of: "\r\n\t", with: "")
        result = result.replacingOccurrences(of: "\n ", with: "")
        result = result.replacingOccurrences(of: "\n\t", with: "")
        return result
    }

    // MARK: - VEVENT Extraction

    private static func extractVEvents(from text: String) -> [String] {
        var events: [String] = []
        var current: String?

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("BEGIN:VEVENT") {
                current = ""
            } else if line.hasPrefix("END:VEVENT") {
                if let event = current {
                    events.append(event)
                }
                current = nil
            } else if current != nil {
                current! += line + "\n"
            }
        }

        return events
    }

    // MARK: - Occurrence Selection

    private static func selectNextOccurrence(from vevents: [String]) -> String {
        let now = Date()
        var futureEvents: [(event: String, date: Date)] = []
        var pastEvents: [(event: String, date: Date)] = []

        for vevent in vevents {
            if let date = extractDate(property: "DTSTART", from: vevent) {
                if date >= now {
                    futureEvents.append((vevent, date))
                } else {
                    pastEvents.append((vevent, date))
                }
            }
        }

        if let nearest = futureEvents.min(by: { $0.date < $1.date }) {
            return nearest.event
        }

        if let mostRecent = pastEvents.max(by: { $0.date < $1.date }) {
            return mostRecent.event
        }

        return vevents[0]
    }

    // MARK: - VEVENT Parsing

    private static func parseVEvent(_ vevent: String) -> CalendarEvent {
        let title = extractProperty("SUMMARY", from: vevent) ?? "Untitled Event"
        let startDate = extractDate(property: "DTSTART", from: vevent) ?? Date()
        let endDate = extractDate(property: "DTEND", from: vevent) ?? startDate
        let organizer = extractOrganizer(from: vevent)
        let attendees = extractAttendees(from: vevent)
        let description = unescapeICSText(extractProperty("DESCRIPTION", from: vevent) ?? "")
        let location = extractProperty("LOCATION", from: vevent) ?? ""
        let categoriesRaw = extractProperty("CATEGORIES", from: vevent) ?? ""
        let categories = categoriesRaw.isEmpty ? [] : categoriesRaw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let status = extractProperty("STATUS", from: vevent) ?? ""

        return CalendarEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            organizer: organizer,
            attendees: attendees,
            description: description,
            location: location,
            categories: categories,
            status: status
        )
    }

    // MARK: - Property Extraction

    private static func extractProperty(_ name: String, from vevent: String) -> String? {
        for line in vevent.components(separatedBy: "\n") {
            if line.hasPrefix("\(name):") {
                return String(line.dropFirst(name.count + 1))
            }
            if line.hasPrefix("\(name);") {
                if let colonIndex = line.firstIndex(of: ":") {
                    return String(line[line.index(after: colonIndex)...])
                }
            }
        }
        return nil
    }

    // MARK: - Date Parsing

    private static func extractDate(property: String, from vevent: String) -> Date? {
        guard let value = extractProperty(property, from: vevent) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: value)
        }

        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: value)
    }

    // MARK: - Organizer

    private static func extractOrganizer(from vevent: String) -> Organizer? {
        for line in vevent.components(separatedBy: "\n") {
            if line.hasPrefix("ORGANIZER") {
                let name = extractParameter("CN", from: line) ?? ""
                let email = extractMailto(from: line) ?? ""
                if !name.isEmpty || !email.isEmpty {
                    return Organizer(name: name, email: email)
                }
            }
        }
        return nil
    }

    // MARK: - Attendees

    private static func extractAttendees(from vevent: String) -> [Attendee] {
        var attendees: [Attendee] = []

        for line in vevent.components(separatedBy: "\n") {
            if line.hasPrefix("ATTENDEE") {
                let name = extractParameter("CN", from: line) ?? ""
                let email = extractMailto(from: line) ?? ""
                let partstat = extractParameter("PARTSTAT", from: line) ?? "NEEDS-ACTION"
                let status = AttendeeStatus(rawValue: partstat) ?? .needsAction

                if !name.isEmpty || !email.isEmpty {
                    attendees.append(Attendee(name: name, email: email, status: status))
                }
            }
        }

        return attendees
    }

    // MARK: - Parameter Helpers

    private static func extractParameter(_ param: String, from line: String) -> String? {
        let pattern = "\(param)=([^;:]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }

    private static func extractMailto(from line: String) -> String? {
        guard let range = line.range(of: "mailto:", options: .caseInsensitive) else { return nil }
        let email = String(line[range.upperBound...])
        return email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Text Unescaping

    private static func unescapeICSText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        result = result.replacingOccurrences(of: "\\,", with: ",")
        result = result.replacingOccurrences(of: "\\\\", with: "\\")
        result = result.replacingOccurrences(of: "\\;", with: ";")
        return result
    }
}
