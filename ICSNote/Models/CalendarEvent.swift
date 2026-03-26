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
}
