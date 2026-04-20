import Foundation

struct Attendee: Equatable {
    let name: String
    let email: String
    let status: AttendeeStatus
}

enum AttendeeStatus: String, Equatable {
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case tentative = "TENTATIVE"
    case needsAction = "NEEDS-ACTION"

    var emoji: String {
        switch self {
        case .accepted: "✅"
        case .declined: "❌"
        case .tentative: "❓"
        case .needsAction: "➖"
        }
    }

    var label: String {
        switch self {
        case .accepted: "accepted"
        case .declined: "declined"
        case .tentative: "tentative"
        case .needsAction: "needs-action"
        }
    }
}

struct Organizer: Equatable {
    let name: String
    let email: String
}

struct CalendarEvent: Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let organizer: Organizer?
    let attendees: [Attendee]
    let description: String
    let location: String
    let categories: [String]
    let status: String
    let isRecurring: Bool
    /// For recurring events, the parser's best guess at which occurrence the
    /// user intended to drag — used as the default for the date picker.
    /// Defaults to `startDate` when not explicitly set.
    let suggestedOccurrenceDate: Date

    init(title: String, startDate: Date, endDate: Date, organizer: Organizer?,
         attendees: [Attendee], description: String, location: String,
         categories: [String], status: String, isRecurring: Bool = false,
         suggestedOccurrenceDate: Date? = nil) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.organizer = organizer
        self.attendees = attendees
        self.description = description
        self.location = location
        self.categories = categories
        self.status = status
        self.isRecurring = isRecurring
        self.suggestedOccurrenceDate = suggestedOccurrenceDate ?? startDate
    }

    /// Returns a copy of this event with the date shifted to `date`,
    /// preserving the original time-of-day and duration.
    func withDate(_ date: Date) -> CalendarEvent {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)
        var newComponents = calendar.dateComponents([.year, .month, .day], from: date)
        newComponents.hour = timeComponents.hour
        newComponents.minute = timeComponents.minute
        newComponents.second = timeComponents.second

        let duration = endDate.timeIntervalSince(startDate)
        guard let newStart = calendar.date(from: newComponents) else { return self }
        let newEnd = newStart.addingTimeInterval(duration)

        return CalendarEvent(
            title: title, startDate: newStart, endDate: newEnd,
            organizer: organizer, attendees: attendees, description: description,
            location: location, categories: categories, status: status,
            isRecurring: isRecurring
        )
    }
}
