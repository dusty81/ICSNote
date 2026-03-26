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
        var startDate = extractDate(property: "DTSTART", from: vevent) ?? Date()
        var endDate = extractDate(property: "DTEND", from: vevent) ?? startDate

        // If this is a recurring event with a past start date, advance to
        // the next upcoming occurrence using the RRULE
        if let rrule = extractProperty("RRULE", from: vevent), startDate < Date() {
            let duration = endDate.timeIntervalSince(startDate)
            if let nextStart = nextOccurrence(from: startDate, rrule: rrule) {
                startDate = nextStart
                endDate = nextStart.addingTimeInterval(duration)
            }
        }
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

    // MARK: - RRULE Occurrence Calculation

    /// Given a start date and an RRULE string, compute the next occurrence >= now.
    /// Supports DAILY, WEEKLY, MONTHLY, YEARLY with INTERVAL and UNTIL/COUNT.
    static func nextOccurrence(from startDate: Date, rrule: String) -> Date? {
        let params = parseRRuleParams(rrule)
        guard let freq = params["FREQ"] else { return nil }

        let interval = Int(params["INTERVAL"] ?? "1") ?? 1
        let calendar = Calendar.current
        let now = Date()

        // Parse UNTIL if present
        var until: Date?
        if let untilStr = params["UNTIL"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            if untilStr.hasSuffix("Z") {
                formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            } else {
                formatter.dateFormat = "yyyyMMdd'T'HHmmss"
            }
            until = formatter.date(from: untilStr)
        }

        let component: Calendar.Component
        switch freq {
        case "DAILY": component = .day
        case "WEEKLY": component = .weekOfYear
        case "MONTHLY": component = .month
        case "YEARLY": component = .year
        default: return nil
        }

        // Step forward from startDate by interval until we find a date >= now
        var candidate = startDate
        // Safety limit to avoid infinite loops
        for _ in 0..<10000 {
            if candidate >= now {
                // Check UNTIL bound
                if let until, candidate > until {
                    return nil // Series has ended
                }
                return candidate
            }
            guard let next = calendar.date(byAdding: component, value: interval, to: candidate) else {
                return nil
            }
            candidate = next
        }

        return nil
    }

    /// Parse RRULE parameters like "FREQ=WEEKLY;INTERVAL=1;BYDAY=TH;UNTIL=20260531T150000Z"
    private static func parseRRuleParams(_ rrule: String) -> [String: String] {
        var params: [String: String] = [:]
        for part in rrule.components(separatedBy: ";") {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 {
                params[kv[0]] = kv[1]
            }
        }
        return params
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
