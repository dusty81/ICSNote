import XCTest
@testable import ICSNote

final class MarkdownGeneratorTests: XCTestCase {

    private var sampleEvent: CalendarEvent!

    override func setUp() {
        super.setUp()
        let start = makeDate(year: 2026, month: 2, day: 19, hour: 10, minute: 0)
        let end = makeDate(year: 2026, month: 2, day: 19, hour: 10, minute: 30)
        sampleEvent = CalendarEvent(
            title: "Project Alpha (PA) Strategy Meeting",
            startDate: start, endDate: end,
            organizer: Organizer(name: "Alex User", email: "DUser@example.com"),
            attendees: [
                Attendee(name: "Alice Example", email: "aexample@example.com", status: .accepted),
                Attendee(name: "Robert D. Example", email: "RExample@example.com", status: .declined),
                Attendee(name: "Neal Example", email: "HExample@example.com", status: .tentative),
                Attendee(name: "David Example", email: "aexample@example.com", status: .needsAction),
            ],
            description: "Session to discuss the high level tasks.",
            location: "https://example.zoom.us/j/123456",
            categories: ["Projects"],
            status: "CONFIRMED"
        )
    }

    func testGeneratesFrontmatter() {
        let markdown = MarkdownGenerator.generate(event: sampleEvent)
        XCTAssertTrue(markdown.hasPrefix("---\n"))
        XCTAssertTrue(markdown.contains("title: \"Project Alpha (PA) Strategy Meeting\""))
        XCTAssertTrue(markdown.contains("date: 2026-02-19"))
        XCTAssertTrue(markdown.contains("organizer: \"Alex User\""))
        XCTAssertTrue(markdown.contains("status: \"Confirmed\""))
        XCTAssertTrue(markdown.contains("type: meeting"))
    }

    func testFrontmatterContainsAttendeesWithStatus() {
        let markdown = MarkdownGenerator.generate(event: sampleEvent)
        XCTAssertTrue(markdown.contains("  - name: \"Alice Example\""))
        XCTAssertTrue(markdown.contains("    status: accepted"))
        XCTAssertTrue(markdown.contains("  - name: \"Robert D. Example\""))
        XCTAssertTrue(markdown.contains("    status: declined"))
    }

    func testFrontmatterContainsCategories() {
        let markdown = MarkdownGenerator.generate(event: sampleEvent)
        XCTAssertTrue(markdown.contains("categories:\n  - \"Projects\""))
    }

    func testGeneratesMetadataTable() {
        let markdown = MarkdownGenerator.generate(event: sampleEvent)
        XCTAssertTrue(markdown.contains("## Meeting Details"))
        XCTAssertTrue(markdown.contains("| **Subject** | Project Alpha (PA) Strategy Meeting |"))
        XCTAssertTrue(markdown.contains("| **Organizer** | Alex User (DUser@example.com) |"))
        XCTAssertTrue(markdown.contains("| **Status** | Confirmed |"))
    }

    func testGeneratesAttendeesWithEmoji() {
        let markdown = MarkdownGenerator.generate(event: sampleEvent)
        XCTAssertTrue(markdown.contains("## Attendees"))
        XCTAssertTrue(markdown.contains("- ✅ Alice Example (aexample@example.com)"))
        XCTAssertTrue(markdown.contains("- ❌ Robert D. Example (RExample@example.com)"))
        XCTAssertTrue(markdown.contains("- ❓ Neal Example (HExample@example.com)"))
        XCTAssertTrue(markdown.contains("- ➖ David Example (aexample@example.com)"))
    }

    func testGeneratesDescriptionSection() {
        let markdown = MarkdownGenerator.generate(event: sampleEvent)
        XCTAssertTrue(markdown.contains("## Description"))
        XCTAssertTrue(markdown.contains("Session to discuss the high level tasks."))
    }

    func testGeneratesNotesSection() {
        let markdown = MarkdownGenerator.generate(event: sampleEvent)
        XCTAssertTrue(markdown.contains("## Notes"))
    }

    func testUsesCustomNotesTemplate() {
        let template = "### Action Items\n\n- \n\n### Decisions\n\n- "
        let markdown = MarkdownGenerator.generate(event: sampleEvent, notesTemplate: template)
        XCTAssertTrue(markdown.contains("### Action Items"))
        XCTAssertTrue(markdown.contains("### Decisions"))
    }

    func testStripsZoomInfo() {
        let event = CalendarEvent(
            title: "Test", startDate: Date(), endDate: Date(), organizer: nil, attendees: [],
            description: "Agenda items here.\n\nHi there,\nAlex User is inviting you to a scheduled Zoom meeting.\nJoin Zoom Meeting\nhttps://example.zoom.us/j/123\nMeeting ID: 123 456\nPasscode: abc\nDial:\n+1 301 715 8592 US\nInternational numbers\n\nFooter text.",
            location: "", categories: [], status: ""
        )
        let markdown = MarkdownGenerator.generate(event: event, stripZoom: true)
        XCTAssertTrue(markdown.contains("Agenda items here."))
        XCTAssertTrue(markdown.contains("*Zoom meeting information removed.*"))
        XCTAssertFalse(markdown.contains("Join Zoom Meeting"))
        XCTAssertFalse(markdown.contains("Meeting ID"))
    }

    func testDoesNotStripZoomWhenDisabled() {
        let event = CalendarEvent(
            title: "Test", startDate: Date(), endDate: Date(), organizer: nil, attendees: [],
            description: "Join Zoom Meeting\nhttps://example.zoom.us/j/123\nMeeting ID: 123\nInternational numbers",
            location: "", categories: [], status: ""
        )
        let markdown = MarkdownGenerator.generate(event: event, stripZoom: false)
        XCTAssertTrue(markdown.contains("Join Zoom Meeting"))
        XCTAssertFalse(markdown.contains("*Zoom meeting information removed.*"))
    }

    func testStripsTeamsInfo() {
        let event = CalendarEvent(
            title: "Test", startDate: Date(), endDate: Date(), organizer: nil, attendees: [],
            description: "Agenda items here.\n\nJoin Microsoft Teams Meeting\nhttps://teams.microsoft.com/l/meetup-join/abc\nLearn more about Teams",
            location: "", categories: [], status: ""
        )
        let markdown = MarkdownGenerator.generate(event: event, stripTeams: true)
        XCTAssertTrue(markdown.contains("Agenda items here."))
        XCTAssertTrue(markdown.contains("*Microsoft Teams meeting information removed.*"))
        XCTAssertFalse(markdown.contains("Join Microsoft Teams Meeting"))
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}
