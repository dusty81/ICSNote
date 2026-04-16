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

    func testStripsZoomSafeLinksFormat() {
        // Outlook wraps URLs in SafeLinks and uses H.323/SIP instead of phone dial-in
        let event = CalendarEvent(
            title: "Test", startDate: Date(), endDate: Date(), organizer: nil, attendees: [],
            description: "[https://us06st2.zoom.us/static/6.3.54678/image/new/ZoomLogo_110_25.png]<https://nam11.safelinks.protection.outlook.com/?url=https%3A%2F%2Fzoom.com>\nHi there,\nDavid Example is inviting you to a scheduled Zoom meeting.\nJoin Zoom Meeting<https://nam11.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.zoom.us%2Fj%2F123>\nMeeting URL:\nhttps://example.zoom.us/j/123\nMeeting ID:\n860 7531 7442\nPasscode:\nabc123\nJoin from an H.323/SIP room system\nH.323:\n144.195.19.161 (US West)\nSIP:\n86075317442@zoomcrc.com\nPasscode:\n7321250",
            location: "", categories: [], status: ""
        )
        let markdown = MarkdownGenerator.generate(event: event, stripZoom: true)
        XCTAssertTrue(markdown.contains("*Zoom meeting information removed.*"))
        XCTAssertFalse(markdown.contains("Join Zoom Meeting"))
        XCTAssertFalse(markdown.contains("zoomcrc.com"))
        XCTAssertFalse(markdown.contains("H.323"))
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

    func testStripsZoomWithH323AfterInternationalNumbers() {
        // When H.323/SIP block comes AFTER "International numbers", both must be stripped
        let event = CalendarEvent(
            title: "Test", startDate: Date(), endDate: Date(), organizer: nil, attendees: [],
            description: "[https://us06st2.zoom.us/static/6.3.55369/image/new/ZoomLogo_110_25.png]<https://nam11.safelinks.protection.outlook.com/?url=https%3A%2F%2Fzoom.com>\nHi there,\nSarah is inviting you to a scheduled Zoom meeting.\nJoin Zoom Meeting<safelink>\nMeeting URL:\nhttps://example.zoom.us/j/123\nMeeting ID:\n880 0908 6727\nDial:\n+1 651 372 8299 US\nMeeting ID:\n880 0908 6727\nInternational numbers<safelink>\nJoin from an H.323/SIP room system\nH.323:\n144.195.19.161 (US West)\n206.247.11.121 (US East)\nMeeting ID:\n880 0908 6727\nSIP:\n88009086727@zoomcrc.com",
            location: "", categories: [], status: ""
        )
        let markdown = MarkdownGenerator.generate(event: event, stripZoom: true)
        XCTAssertTrue(markdown.contains("*Zoom meeting information removed.*"))
        XCTAssertFalse(markdown.contains("Join Zoom Meeting"), "Join Zoom Meeting should be stripped")
        XCTAssertFalse(markdown.contains("H.323"), "H.323 block should be stripped")
        XCTAssertFalse(markdown.contains("zoomcrc.com"), "SIP address should be stripped")
        XCTAssertFalse(markdown.contains("International numbers"), "International numbers should be stripped")
    }

    func testStripsZoomDelimitedBlock() {
        // Zoom block wrapped in ~===~ delimiters
        let event = CalendarEvent(
            title: "Test", startDate: Date(), endDate: Date(), organizer: nil, attendees: [],
            description: "~==========================~\nYou have been invited to a Zoom meeting:\n\nhttps://example.zoom.us/j/123\n\nMeeting ID: 123\nPassword: abc\n\nDial by your location:\n+1 470 250 9358 US\nFind your local number: https://zoom.us/zoomconference\n~==========================~",
            location: "", categories: [], status: ""
        )
        let markdown = MarkdownGenerator.generate(event: event, stripZoom: true)
        XCTAssertTrue(markdown.contains("*Zoom meeting information removed.*"))
        XCTAssertFalse(markdown.contains("You have been invited to a Zoom meeting"))
        XCTAssertFalse(markdown.contains("zoom.us/zoomconference"))
        XCTAssertFalse(markdown.contains("~==========================~"))
    }

    func testStripsTeamsUnderscoreDelimitedBlock() {
        // External-org Teams invite: underscore-delimited with SafeLinks, no "Learn more about Teams"
        let event = CalendarEvent(
            title: "Test", startDate: Date(), endDate: Date(), organizer: nil, attendees: [],
            description: "CAUTION: This email originated from outside.\n\n________________________________________________________________________________\nMicrosoft Teams meeting\nJoin: https://teams.microsoft.com/meet/123<https://nam11.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fmeet%2F123>\nMeeting ID: 264 183 392 744 150\nPasscode: Mt9xB2N6\n________________________________\nNeed help?<safelink> | System reference<safelink>\nDial in by phone\n+1 920-393-6201 United States\nFind a local number<safelink>\nPhone conference ID: 559 727 062#\nFor organizers: Meeting options<safelink> | Reset dial-in PIN<safelink>\n________________________________________________________________________________",
            location: "", categories: [], status: ""
        )
        let markdown = MarkdownGenerator.generate(event: event, stripTeams: true)
        XCTAssertTrue(markdown.contains("CAUTION"), "External email warning should be preserved")
        XCTAssertTrue(markdown.contains("*Microsoft Teams meeting information removed.*"))
        XCTAssertFalse(markdown.contains("Join: https://teams.microsoft.com"), "Teams join link should be stripped")
        XCTAssertFalse(markdown.contains("Meeting ID"), "Meeting ID should be stripped")
        XCTAssertFalse(markdown.contains("Dial in by phone"), "Dial-in info should be stripped")
        XCTAssertFalse(markdown.contains("Reset dial-in PIN"), "Reset PIN should be stripped")
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
