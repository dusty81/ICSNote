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

    func testRecurringEventMarkedAsRecurring() throws {
        let ics = try loadFixture("recurring-meeting")
        let event = try ICSParser.parse(ics)
        // selectNextOccurrence picks the Jan 20 VEVENT which has RECURRENCE-ID
        // (a modified instance of a recurring series) — should be marked recurring
        XCTAssertTrue(event.isRecurring)
    }

    func testRecurrenceIDOnlyVEventIsRecurring() throws {
        // When a series has multiple VEVENTs and the selected one has
        // RECURRENCE-ID but no RRULE, it should still be marked recurring
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        SUMMARY:1:1 - Alec / Dusty
        DTSTART:20260114T153000Z
        DTEND:20260114T160000Z
        RRULE:FREQ=WEEKLY;UNTIL=20270101T153000Z;INTERVAL=2;BYDAY=WE;WKST=SU
        STATUS:CONFIRMED
        END:VEVENT
        BEGIN:VEVENT
        RECURRENCE-ID:20260325T143000Z
        SUMMARY:1:1 - Alec / Dusty
        DTSTART:20260324T143000Z
        DTEND:20260324T150000Z
        STATUS:CONFIRMED
        END:VEVENT
        END:VCALENDAR
        """
        let event = try ICSParser.parse(ics)
        // Both VEVENTs are in the past; selectNextOccurrence picks Mar 24
        // That VEVENT has RECURRENCE-ID → isRecurring should be true
        XCTAssertTrue(event.isRecurring)
    }

    func testSingleVEventWithRRuleIsRecurring() throws {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        SUMMARY:Weekly Standup
        DTSTART:20260101T100000Z
        DTEND:20260101T103000Z
        RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=TH
        STATUS:CONFIRMED
        END:VEVENT
        END:VCALENDAR
        """
        let event = try ICSParser.parse(ics)
        XCTAssertTrue(event.isRecurring)
    }

    func testSimpleMeetingNotRecurring() throws {
        let ics = try loadFixture("simple-meeting")
        let event = try ICSParser.parse(ics)
        XCTAssertFalse(event.isRecurring)
    }

    func testWithDatePreservesTimeAndShiftsDate() {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 8
        c.hour = 16; c.minute = 0; c.second = 0
        c.timeZone = TimeZone.current
        let calendar = Calendar.current
        let start = calendar.date(from: c)!
        let end = start.addingTimeInterval(45 * 60) // 45 min

        let event = CalendarEvent(
            title: "Test", startDate: start, endDate: end, organizer: nil,
            attendees: [], description: "", location: "", categories: [], status: ""
        )

        // Shift to April 3, 2026
        var target = DateComponents()
        target.year = 2026; target.month = 4; target.day = 3
        target.hour = 12; target.minute = 0
        target.timeZone = TimeZone.current
        let targetDate = calendar.date(from: target)!

        let shifted = event.withDate(targetDate)
        let shiftedComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: shifted.startDate)
        XCTAssertEqual(shiftedComponents.year, 2026)
        XCTAssertEqual(shiftedComponents.month, 4)
        XCTAssertEqual(shiftedComponents.day, 3)
        XCTAssertEqual(shiftedComponents.hour, 16) // original time preserved
        XCTAssertEqual(shiftedComponents.minute, 0)

        // Duration preserved (45 min)
        let duration = shifted.endDate.timeIntervalSince(shifted.startDate)
        XCTAssertEqual(duration, 45 * 60, accuracy: 1)
    }

    // MARK: - Text Unescaping

    func testUnescapesDescriptionText() throws {
        let ics = try loadFixture("recurring-meeting")
        let event = try ICSParser.parse(ics)

        XCTAssertTrue(event.description.contains("Session to discuss high level tasks."))
        XCTAssertTrue(event.description.contains("\n"))
        XCTAssertFalse(event.description.contains("\\,"))
    }

    // MARK: - RRULE Occurrence Calculation

    func testNextOccurrenceWeekly() {
        // A weekly event starting 3 weeks ago should advance to the next future occurrence
        let pastStart = Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date())!
        let rrule = "FREQ=WEEKLY;INTERVAL=1;BYDAY=TH"
        let next = ICSParser.nextOccurrence(from: pastStart, rrule: rrule)
        XCTAssertNotNil(next)
        XCTAssertTrue(next! >= Date())
        // Should be within the next 7 days
        XCTAssertTrue(next! < Calendar.current.date(byAdding: .day, value: 8, to: Date())!)
    }

    func testNextOccurrenceRespectsUntil() {
        // A weekly event that ended in the past should return nil
        let pastStart = Calendar.current.date(byAdding: .month, value: -6, to: Date())!
        let pastEnd = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let untilStr = formatter.string(from: pastEnd)
        let rrule = "FREQ=WEEKLY;INTERVAL=1;UNTIL=\(untilStr)"
        let next = ICSParser.nextOccurrence(from: pastStart, rrule: rrule)
        XCTAssertNil(next)
    }

    func testNextOccurrenceBiWeekly() {
        let pastStart = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date())!
        let rrule = "FREQ=WEEKLY;INTERVAL=2"
        let next = ICSParser.nextOccurrence(from: pastStart, rrule: rrule)
        XCTAssertNotNil(next)
        XCTAssertTrue(next! >= Date())
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

    // MARK: - Real-World Recurring Fixtures

    func testAlecDustyRecurringIsMarkedRecurring() throws {
        let ics = try loadFixture("1-1-alec-dusty")
        let event = try ICSParser.parse(ics)
        XCTAssertTrue(event.isRecurring, "Modified occurrence with RECURRENCE-ID should be marked recurring")
        XCTAssertEqual(event.title, "1:1 - Alec / Dusty")
    }

    func testNealDustyRecurringIsMarkedRecurring() throws {
        let ics = try loadFixture("1-1-neal-dusty")
        let event = try ICSParser.parse(ics)
        XCTAssertTrue(event.isRecurring, "Modified occurrence with RECURRENCE-ID should be marked recurring")
        XCTAssertEqual(event.title, "1:1 - Neal / Dusty")
    }

    func testBiWeeklyHuddleRecurringIsMarkedRecurring() throws {
        let ics = try loadFixture("biweekly-infosec-huddle")
        let event = try ICSParser.parse(ics)
        XCTAssertTrue(event.isRecurring, "Modified occurrence with RECURRENCE-ID should be marked recurring")
        XCTAssertEqual(event.title, "Biweekly Team Huddle")
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
