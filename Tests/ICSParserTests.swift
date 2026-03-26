import XCTest
@testable import ICSNote

final class ICSParserTests: XCTestCase {

    // MARK: - Line Unfolding

    func testUnfoldsContinuationLines() throws {
        let input = "ATTENDEE;CN=Robert D. \n Example:mailto:RExample@example.com"
        let unfolded = ICSParser.unfoldLines(input)
        XCTAssertEqual(unfolded, "ATTENDEE;CN=Robert D. Example:mailto:RExample@example.com")
    }

    func testUnfoldsMultipleContinuationLines() throws {
        let input = "DESCRIPTION:Line one\n continues here\n and here too"
        let unfolded = ICSParser.unfoldLines(input)
        XCTAssertEqual(unfolded, "DESCRIPTION:Line onecontinues hereand here too")
    }

    // MARK: - Simple Meeting Parsing

    func testParsesSimpleMeeting() throws {
        let ics = try loadFixture("simple-meeting")
        let event = try ICSParser.parse(ics)

        XCTAssertEqual(event.title, "1:1 - Dusty / Landon")
        XCTAssertEqual(event.organizer?.name, "Jane Smith")
        XCTAssertEqual(event.organizer?.email, "jane@example.com")
        XCTAssertEqual(event.description, "Quarterly review of project status.")
        XCTAssertEqual(event.status, "CONFIRMED")
        XCTAssertEqual(event.location, "Microsoft Teams Meeting")
    }

    func testParsesStartAndEndDates() throws {
        let ics = try loadFixture("simple-meeting")
        let event = try ICSParser.parse(ics)

        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: event.startDate)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 0)

        components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: event.endDate)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 30)
    }

    // MARK: - Attendee Parsing

    func testParsesAttendeesWithStatus() throws {
        let ics = try loadFixture("recurring-meeting")
        let event = try ICSParser.parse(ics)

        XCTAssertEqual(event.attendees.count, 4)

        let alec = event.attendees.first { $0.name == "Alice Example" }
        XCTAssertNotNil(alec)
        XCTAssertEqual(alec?.email, "aexample@example.com")
        XCTAssertEqual(alec?.status, .accepted)

        let robert = event.attendees.first { $0.name == "Robert D. Example" }
        XCTAssertNotNil(robert)
        XCTAssertEqual(robert?.status, .declined)

        let neal = event.attendees.first { $0.name == "Neal Example" }
        XCTAssertNotNil(neal)
        XCTAssertEqual(neal?.status, .tentative)

        let landon = event.attendees.first { $0.name == "David Example" }
        XCTAssertNotNil(landon)
        XCTAssertEqual(landon?.status, .needsAction)
    }

    func testParsesOrganizer() throws {
        let ics = try loadFixture("recurring-meeting")
        let event = try ICSParser.parse(ics)

        XCTAssertEqual(event.organizer?.name, "Alex User")
        XCTAssertEqual(event.organizer?.email, "DUser@example.com")
    }

    func testParsesCategories() throws {
        let ics = try loadFixture("recurring-meeting")
        let event = try ICSParser.parse(ics)
        XCTAssertEqual(event.categories, ["Projects"])
    }

    // MARK: - Recurring Event Selection

    func testSelectsFutureOccurrenceOverPast() throws {
        let ics = try loadFixture("recurring-meeting")
        let event = try ICSParser.parse(ics)

        // Both events are in the past, should pick most recent (Jan 20)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: event.startDate)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 20)
    }

    // MARK: - Text Unescaping

    func testUnescapesDescriptionText() throws {
        let ics = try loadFixture("recurring-meeting")
        let event = try ICSParser.parse(ics)

        XCTAssertTrue(event.description.contains("Session to discuss high level tasks."))
        XCTAssertTrue(event.description.contains("\n"))
        XCTAssertFalse(event.description.contains("\\,"))
    }

    // MARK: - Error Handling

    func testThrowsOnEmptyInput() {
        XCTAssertThrowsError(try ICSParser.parse("")) { error in
            XCTAssertTrue(error is ICSParseError)
        }
    }

    func testThrowsOnNoVEvent() {
        let ics = "BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR"
        XCTAssertThrowsError(try ICSParser.parse(ics)) { error in
            XCTAssertTrue(error is ICSParseError)
        }
    }

    // MARK: - Attendee Status Emoji

    func testAttendeeStatusEmoji() {
        XCTAssertEqual(AttendeeStatus.accepted.emoji, "✅")
        XCTAssertEqual(AttendeeStatus.declined.emoji, "❌")
        XCTAssertEqual(AttendeeStatus.tentative.emoji, "❓")
        XCTAssertEqual(AttendeeStatus.needsAction.emoji, "➖")
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "ics") else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture \(name).ics not found in test bundle"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
