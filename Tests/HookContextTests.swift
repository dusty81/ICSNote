import XCTest
@testable import ICSNote

final class HookContextTests: XCTestCase {

    private func sampleMeetingContext() -> HookContext {
        let vault = VaultConfig(name: "Workspace", path: "/Users/u/Obsidian/Workspace", enabled: true)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 17
        comps.hour = 10; comps.minute = 30
        comps.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let event = CalendarEvent(
            title: "Board Meeting",
            startDate: date,
            endDate: date.addingTimeInterval(3600),
            organizer: Organizer(name: "Alice", email: "a@x.com"),
            attendees: [
                Attendee(name: "Bob", email: "b@x.com", status: .accepted),
                Attendee(name: "Carol", email: "c@x.com", status: .tentative),
            ],
            description: "",
            location: "",
            categories: [],
            status: "CONFIRMED"
        )
        return HookContext.meeting(
            event: event,
            vault: vault,
            outputURL: URL(fileURLWithPath: "/Users/u/Obsidian/Workspace/Unfiled/2026-04-17 Board Meeting.md")
        )
    }

    private func sampleEmailContext() -> HookContext {
        let vault = VaultConfig(name: "Workspace", path: "/Users/u/Obsidian/Workspace", enabled: true)
        let email = EmailMessage(
            subject: "RE: Quarterly report",
            from: EmailContact(name: "Alice", email: "alice@example.com"),
            to: [EmailContact(name: "Bob", email: "bob@example.com")],
            cc: [],
            date: Date(timeIntervalSince1970: 1776445200), // some ts
            body: "body",
            attachments: []
        )
        return HookContext.email(
            email: email,
            vault: vault,
            outputURL: URL(fileURLWithPath: "/Users/u/Obsidian/Workspace/Emails/2026-04-17 Quarterly report.md"),
            attachmentPaths: ["/Users/u/Obsidian/Workspace/attachments/Quarterly report.xlsx"]
        )
    }

    // MARK: - Substitution

    func testSubstitutesFilePath() {
        let ctx = sampleMeetingContext()
        XCTAssertEqual(
            ctx.substitute(in: "Path: {{file_path}}"),
            "Path: /Users/u/Obsidian/Workspace/Unfiled/2026-04-17 Board Meeting.md"
        )
    }

    func testSubstitutesMultipleVariables() {
        let ctx = sampleMeetingContext()
        let template = "Skill: /summary for {{note_type}} in {{vault_name}}: {{title}}"
        XCTAssertEqual(
            ctx.substitute(in: template),
            "Skill: /summary for meeting in Workspace: Board Meeting"
        )
    }

    func testSubstitutesMeetingAttendees() {
        let ctx = sampleMeetingContext()
        XCTAssertEqual(
            ctx.substitute(in: "Attendees: {{attendees}}"),
            "Attendees: Bob, Carol"
        )
    }

    func testSubstitutesEmailSpecifics() {
        let ctx = sampleEmailContext()
        XCTAssertTrue(ctx.substitute(in: "{{from}}").contains("Alice"))
        XCTAssertTrue(ctx.substitute(in: "{{recipients}}").contains("Bob"))
        XCTAssertTrue(ctx.substitute(in: "{{attachments}}").contains("Quarterly report.xlsx"))
    }

    func testEmptyFieldsSubstituteToEmptyString() {
        let ctx = sampleEmailContext()
        // organizer is nil for emails; should render as empty
        XCTAssertEqual(ctx.substitute(in: "Organizer=[{{organizer}}]"), "Organizer=[]")
    }

    func testUnknownVariableIsLeftUnchanged() {
        let ctx = sampleMeetingContext()
        XCTAssertEqual(
            ctx.substitute(in: "Unknown: {{not_a_variable}}"),
            "Unknown: {{not_a_variable}}"
        )
    }

    // MARK: - PostSaveHook.matches

    func testHookMatchesVaultAndType() {
        let vaultA = UUID(); let vaultB = UUID()
        var hook = PostSaveHook(
            name: "Test",
            enabled: true,
            vaultID: vaultA,
            trigger: .meeting,
            action: .claudeSkill(skillName: "summary", promptTemplate: "")
        )
        XCTAssertTrue(hook.matches(vaultID: vaultA, noteType: .meeting))
        XCTAssertFalse(hook.matches(vaultID: vaultA, noteType: .email))
        XCTAssertFalse(hook.matches(vaultID: vaultB, noteType: .meeting))

        hook.vaultID = nil // all vaults
        XCTAssertTrue(hook.matches(vaultID: vaultA, noteType: .meeting))
        XCTAssertTrue(hook.matches(vaultID: vaultB, noteType: .meeting))

        hook.trigger = .any
        XCTAssertTrue(hook.matches(vaultID: vaultA, noteType: .email))
    }

    func testDisabledHookDoesNotMatch() {
        var hook = PostSaveHook(
            name: "Test",
            enabled: false,
            trigger: .any,
            action: .claudeSkill(skillName: "x", promptTemplate: "")
        )
        XCTAssertFalse(hook.matches(vaultID: UUID(), noteType: .meeting))
        hook.enabled = true
        XCTAssertTrue(hook.matches(vaultID: UUID(), noteType: .meeting))
    }

    // MARK: - showInContextMenu

    func testShowInContextMenuDefaultsFalse() {
        let hook = PostSaveHook(
            name: "Test",
            trigger: .any,
            action: .claudeSkill(skillName: "x", promptTemplate: "")
        )
        XCTAssertFalse(hook.showInContextMenu)
    }

    func testShowInContextMenuRoundTrips() throws {
        let hook = PostSaveHook(
            name: "Context hook",
            trigger: .meeting,
            action: .claudeSkill(skillName: "summary", promptTemplate: ""),
            showInContextMenu: true
        )
        let data = try JSONEncoder().encode(hook)
        let decoded = try JSONDecoder().decode(PostSaveHook.self, from: data)
        XCTAssertTrue(decoded.showInContextMenu)

        var hook2 = hook
        hook2.showInContextMenu = false
        let data2 = try JSONEncoder().encode(hook2)
        let decoded2 = try JSONDecoder().decode(PostSaveHook.self, from: data2)
        XCTAssertFalse(decoded2.showInContextMenu)
    }

    func testShowInContextMenuDecodesFromLegacyJSON() throws {
        // JSON without the key at all (old persisted data) must decode with false
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"old hook","enabled":true,
         "trigger":"any","action":{"claudeSkill":{"skillName":"x","promptTemplate":""}}}
        """
        let hook = try JSONDecoder().decode(PostSaveHook.self, from: json.data(using: .utf8)!)
        XCTAssertFalse(hook.showInContextMenu)
    }

    // MARK: - fromConversion factory

    func testFromConversionMeetingContext() {
        let vault = VaultConfig(name: "Work", path: "/Obsidian/Work", enabled: true)
        let outputURL = URL(fileURLWithPath: "/Obsidian/Work/Meetings/2026-06-10 Standup.md")
        let ts = Date(timeIntervalSince1970: 1_749_600_000)
        let conversion = RecentConversion(
            filename: "2026-06-10 Standup.md",
            attendeeCount: 3,
            strippedInfo: nil,
            outputURL: outputURL,
            timestamp: ts,
            vaultID: vault.id,
            vaultName: vault.name,
            noteType: .meeting
        )

        let ctx = HookContext.fromConversion(conversion, vault: vault)

        XCTAssertEqual(ctx.filePath, "/Obsidian/Work/Meetings/2026-06-10 Standup.md")
        XCTAssertEqual(ctx.filename, "2026-06-10 Standup.md")
        XCTAssertEqual(ctx.vaultID, vault.id)
        XCTAssertEqual(ctx.vaultName, "Work")
        XCTAssertEqual(ctx.vaultPath, "/Obsidian/Work")
        XCTAssertEqual(ctx.noteType, .meeting)
        XCTAssertEqual(ctx.title, "2026-06-10 Standup")
        XCTAssertEqual(ctx.date, ts)
        XCTAssertNil(ctx.organizer)
        XCTAssertTrue(ctx.attendees.isEmpty)
        XCTAssertNil(ctx.from)
        XCTAssertTrue(ctx.recipients.isEmpty)
        XCTAssertTrue(ctx.attachmentPaths.isEmpty)
    }

    func testFromConversionEmailContext() {
        let vault = VaultConfig(name: "Personal", path: "/Obsidian/Personal", enabled: true)
        let outputURL = URL(fileURLWithPath: "/Obsidian/Personal/Emails/2026-06-10 Invoice.md")
        let ts = Date(timeIntervalSince1970: 1_749_686_400)
        let conversion = RecentConversion(
            filename: "2026-06-10 Invoice.md",
            attendeeCount: 0,
            strippedInfo: nil,
            outputURL: outputURL,
            timestamp: ts,
            vaultID: vault.id,
            vaultName: vault.name,
            noteType: .email
        )

        let ctx = HookContext.fromConversion(conversion, vault: vault)

        XCTAssertEqual(ctx.noteType, .email)
        XCTAssertEqual(ctx.title, "2026-06-10 Invoice")
        XCTAssertEqual(ctx.date, ts)
    }

    func testFromConversionSubstitutesFilePathVariable() {
        let vault = VaultConfig(name: "Work", path: "/Obsidian/Work", enabled: true)
        let outputURL = URL(fileURLWithPath: "/Obsidian/Work/Meetings/My Note.md")
        let conversion = RecentConversion(
            filename: "My Note.md",
            attendeeCount: 0,
            strippedInfo: nil,
            outputURL: outputURL,
            timestamp: Date(),
            vaultID: vault.id,
            vaultName: vault.name,
            noteType: .meeting
        )

        let ctx = HookContext.fromConversion(conversion, vault: vault)
        XCTAssertEqual(
            ctx.substitute(in: "Process {{file_path}} in {{vault_name}}"),
            "Process /Obsidian/Work/Meetings/My Note.md in Work"
        )
    }
}
