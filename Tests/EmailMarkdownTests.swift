import XCTest
@testable import ICSNote

final class EmailMarkdownTests: XCTestCase {

    private var sampleEmail: EmailMessage!

    override func setUp() {
        super.setUp()
        sampleEmail = EmailMessage(
            subject: "Project status update",
            from: EmailContact(name: "Eve Example", email: "TExample@example.com"),
            to: [
                EmailContact(name: "Bob Example", email: "RExample@example.com"),
                EmailContact(name: "Alex User", email: "DUser@example.com"),
            ],
            cc: [],
            date: makeDate(year: 2026, month: 4, day: 3, hour: 19, minute: 55),
            body: "Hi guys,\n\nWanted to share what we've put in place around AI agent governance.",
            attachments: []
        )
    }

    // MARK: - Frontmatter

    func testGeneratesEmailFrontmatter() {
        let markdown = MarkdownGenerator.generate(email: sampleEmail)
        XCTAssertTrue(markdown.hasPrefix("---\n"))
        XCTAssertTrue(markdown.contains("title: \"Project status update\""))
        XCTAssertTrue(markdown.contains("from: \"Eve Example\""))
        XCTAssertTrue(markdown.contains("type: email"))
        XCTAssertTrue(markdown.contains("subject: \"Project status update\""))
    }

    func testFrontmatterContainsRecipients() {
        let markdown = MarkdownGenerator.generate(email: sampleEmail)
        XCTAssertTrue(markdown.contains("to:"))
        XCTAssertTrue(markdown.contains("  - \"Bob Example\""))
        XCTAssertTrue(markdown.contains("  - \"Alex User\""))
    }

    // MARK: - Metadata Table

    func testGeneratesEmailMetadataTable() {
        let markdown = MarkdownGenerator.generate(email: sampleEmail)
        XCTAssertTrue(markdown.contains("## Email Details"))
        XCTAssertTrue(markdown.contains("| **From** | Eve Example (TExample@example.com) |"))
        XCTAssertTrue(markdown.contains("| **To** | Bob Example, Alex User |"))
        XCTAssertTrue(markdown.contains("| **Subject** | Project status update |"))
    }

    // MARK: - Body

    func testGeneratesBodySection() {
        let markdown = MarkdownGenerator.generate(email: sampleEmail)
        XCTAssertTrue(markdown.contains("## Body"))
        XCTAssertTrue(markdown.contains("Hi guys,"))
        XCTAssertTrue(markdown.contains("AI agent governance"))
    }

    // MARK: - Attachments

    func testGeneratesAttachmentWikiLinks() {
        let email = EmailMessage(
            subject: "Quarterly report", from: EmailContact(name: "Alice", email: "j@x.com"),
            to: [EmailContact(name: "Alex", email: "d@x.com")], cc: [],
            date: Date(), body: "Here is the file.",
            attachments: [
                EmailAttachment(filename: "Quarterly report.xlsx", contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", data: Data(), isInline: false),
                EmailAttachment(filename: "image001.png", contentType: "image/png", data: Data(), isInline: true),
            ]
        )
        let markdown = MarkdownGenerator.generate(email: email)
        XCTAssertTrue(markdown.contains("## Attachments"))
        XCTAssertTrue(markdown.contains("- [[Quarterly report.xlsx]]"))
        // Inline images should NOT appear in attachments section
        XCTAssertFalse(markdown.contains("[[image001.png]]"))
    }

    func testOmitsAttachmentsSectionWhenNoRealAttachments() {
        let markdown = MarkdownGenerator.generate(email: sampleEmail)
        XCTAssertFalse(markdown.contains("## Attachments"))
    }

    // MARK: - Section Order

    func testBodyAppearsBeforeAttachments() {
        let email = EmailMessage(
            subject: "Report", from: EmailContact(name: "J", email: "j@x.com"),
            to: [], cc: [], date: Date(), body: "Here is the content.",
            attachments: [
                EmailAttachment(filename: "Report.pdf", contentType: "application/pdf", data: Data(), isInline: false),
            ]
        )
        let markdown = MarkdownGenerator.generate(email: email)
        guard let bodyIdx = markdown.range(of: "## Body")?.lowerBound,
              let attachIdx = markdown.range(of: "## Attachments")?.lowerBound else {
            XCTFail("Both ## Body and ## Attachments should be present")
            return
        }
        XCTAssertLessThan(bodyIdx, attachIdx, "## Body should appear before ## Attachments")
    }

    // MARK: - PDF Embedding

    func testEmbedsPDFsWithBangSyntax() {
        let email = EmailMessage(
            subject: "Report", from: EmailContact(name: "J", email: "j@x.com"),
            to: [], cc: [], date: Date(), body: "See attached.",
            attachments: [
                EmailAttachment(filename: "Report.pdf", contentType: "application/pdf", data: Data(), isInline: false),
            ]
        )
        let markdown = MarkdownGenerator.generate(email: email)
        // PDFs use embedded syntax
        XCTAssertTrue(markdown.contains("![[Report.pdf]]"), "PDF should be embedded with ![[...]]")
        XCTAssertFalse(markdown.contains("- [[Report.pdf]]"), "PDF should not use plain [[...]]")
    }

    func testNonPDFsUsePlainWikiLinks() {
        let email = EmailMessage(
            subject: "Report", from: EmailContact(name: "J", email: "j@x.com"),
            to: [], cc: [], date: Date(), body: "See attached.",
            attachments: [
                EmailAttachment(filename: "Report.docx", contentType: "app/docx", data: Data(), isInline: false),
            ]
        )
        let markdown = MarkdownGenerator.generate(email: email)
        XCTAssertTrue(markdown.contains("- [[Report.docx]]"), "Non-PDF should use plain [[...]]")
        XCTAssertFalse(markdown.contains("![[Report.docx]]"), "Non-PDF should not use embedded syntax")
    }

    func testAttachmentFilenamesOverrideEmailAttachments() {
        // When attachmentFilenames is passed explicitly (e.g., for converted PDFs),
        // it should be used instead of email.attachments
        let email = EmailMessage(
            subject: "Mixed", from: EmailContact(name: "J", email: "j@x.com"),
            to: [], cc: [], date: Date(), body: "See attached.",
            attachments: [
                EmailAttachment(filename: "Original.docx", contentType: "app/docx", data: Data(), isInline: false),
            ]
        )
        // Simulate a conversion that produced both the original and a PDF
        let markdown = MarkdownGenerator.generate(
            email: email,
            attachmentFilenames: ["Original.docx", "Original.pdf"]
        )
        XCTAssertTrue(markdown.contains("- [[Original.docx]]"), "Original should be linked")
        XCTAssertTrue(markdown.contains("- ![[Original.pdf]]"), "Converted PDF should be embedded")
    }

    // MARK: - Filename

    func testGeneratesEmailFilename() {
        let filename = MarkdownGenerator.generateFilename(email: sampleEmail)
        XCTAssertTrue(filename.contains("Project status update"))
        XCTAssertTrue(filename.hasSuffix(".md"))
    }

    func testFilenameStripsReplyPrefix() {
        let replyEmail = EmailMessage(
            subject: "RE: Quarterly report for 2025",
            from: EmailContact(name: "Alice", email: "j@x.com"),
            to: [], cc: [], date: Date(), body: "Updated.", attachments: []
        )
        let filename = MarkdownGenerator.generateFilename(email: replyEmail)
        XCTAssertTrue(filename.contains("Quarterly report for 2025"))
        XCTAssertFalse(filename.contains("RE:"))
    }

    // MARK: - Thread Merging

    func testUpdateNoteWithNewMessageMovesOldBody() {
        let existing = """
        ---
        title: "Quarterly report for 2025"
        date: 2026-02-20
        time: "4:42 PM (CDT)"
        from: "Alice Example"
        type: email
        ---

        ## Email Details

        | Field | Value |
        |-------|-------|

        ## Body

        Here is the vendor spend for 2025.

        ## Notes

        ### Action Items

        - Review the numbers
        """

        let newEmail = EmailMessage(
            subject: "RE: Quarterly report for 2025",
            from: EmailContact(name: "Alice Example", email: "j@x.com"),
            to: [], cc: [],
            date: makeDate(year: 2026, month: 4, day: 3, hour: 14, minute: 30),
            body: "Here is the updated spend.",
            attachments: []
        )

        let updated = MarkdownGenerator.updateNoteWithNewMessage(existingContent: existing, newEmail: newEmail)

        // New body should be present
        XCTAssertTrue(updated.contains("Here is the updated spend."), "New body should appear")
        // Old body should be in Previous Messages
        XCTAssertTrue(updated.contains("## Previous Messages"), "Should have Previous Messages section")
        XCTAssertTrue(updated.contains("> [!quote]-"), "Should have collapsed callout")
        XCTAssertTrue(updated.contains("> Here is the vendor spend for 2025."), "Old body in callout")
        // Notes should be preserved
        XCTAssertTrue(updated.contains("## Notes"), "Notes section preserved")
        XCTAssertTrue(updated.contains("Review the numbers"), "Notes content preserved")
        // Frontmatter should be updated
        XCTAssertTrue(updated.contains("from: \"Alice Example\""), "From updated")
    }

    // MARK: - Notes Section

    func testIncludesNotesTemplate() {
        let markdown = MarkdownGenerator.generate(email: sampleEmail, notesTemplate: "### Action Items\n\n- ")
        XCTAssertTrue(markdown.contains("## Notes"))
        XCTAssertTrue(markdown.contains("### Action Items"))
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}
