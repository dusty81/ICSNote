import XCTest
@testable import ICSNote

final class FilenameGeneratorTests: XCTestCase {

    func testBasicFilename() {
        let event = makeEvent(title: "Strategy Meeting", year: 2026, month: 2, day: 19)
        let filename = MarkdownGenerator.generateFilename(event: event)
        XCTAssertEqual(filename, "2026-02-19 Strategy Meeting.md")
    }

    func testSanitizesInvalidCharacters() {
        XCTAssertEqual(MarkdownGenerator.sanitizeFilename("Meeting: Review"), "Meeting Review")
        XCTAssertEqual(MarkdownGenerator.sanitizeFilename("A/B Test"), "AB Test")
        XCTAssertEqual(MarkdownGenerator.sanitizeFilename("What?"), "What")
        XCTAssertEqual(MarkdownGenerator.sanitizeFilename("File*Name"), "FileName")
        XCTAssertEqual(MarkdownGenerator.sanitizeFilename("Say \"Hello\""), "Say Hello")
        XCTAssertEqual(MarkdownGenerator.sanitizeFilename("A < B > C"), "A  B  C")
        XCTAssertEqual(MarkdownGenerator.sanitizeFilename("Pipe|Line"), "PipeLine")
    }

    func testPreservesParentheses() {
        XCTAssertEqual(
            MarkdownGenerator.sanitizeFilename("Project Alpha (PA) Strategy Meeting"),
            "Project Alpha (PA) Strategy Meeting"
        )
    }

    func testAppliesTextReplacementsBeforeSanitizing() {
        let event = makeEvent(title: "1:1 - Dusty / Landon", year: 2026, month: 3, day: 25)
        let filename = MarkdownGenerator.generateFilename(
            event: event,
            textReplacements: [(find: "1:1", replace: "One on One")]
        )
        XCTAssertEqual(filename, "2026-03-25 One on One - Dusty  Landon.md")
    }

    func testMultipleReplacements() {
        let event = makeEvent(title: "Fwd: RE: Weekly Sync", year: 2026, month: 1, day: 10)
        let filename = MarkdownGenerator.generateFilename(
            event: event,
            textReplacements: [(find: "Fwd: ", replace: ""), (find: "RE: ", replace: "")]
        )
        XCTAssertEqual(filename, "2026-01-10 Weekly Sync.md")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(MarkdownGenerator.sanitizeFilename("  Hello  "), "Hello")
    }

    private func makeEvent(title: String, year: Int, month: Int, day: Int) -> CalendarEvent {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = 12; c.minute = 0; c.timeZone = TimeZone.current
        let date = Calendar(identifier: .gregorian).date(from: c)!
        return CalendarEvent(
            title: title, startDate: date, endDate: date, organizer: nil,
            attendees: [], description: "", location: "", categories: [], status: ""
        )
    }
}
