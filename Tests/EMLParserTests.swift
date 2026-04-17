import XCTest
@testable import ICSNote

final class EMLParserTests: XCTestCase {

    // MARK: - Header Parsing

    func testParsesBasicHeaders() throws {
        let eml = try loadFixture("governance-email")
        let email = try EMLParser.parse(eml)

        XCTAssertEqual(email.subject, "Project status update")
        XCTAssertEqual(email.from.name, "Eve Example")
        XCTAssertEqual(email.from.email, "TExample@example.com")
    }

    func testParsesMultipleRecipients() throws {
        let eml = try loadFixture("governance-email")
        let email = try EMLParser.parse(eml)

        XCTAssertEqual(email.to.count, 2)
        XCTAssertTrue(email.to.contains { $0.name == "Bob Example" })
        XCTAssertTrue(email.to.contains { $0.name == "Alex User" })
    }

    func testParsesSingleRecipient() throws {
        let eml = try loadFixture("vendor-spend-email")
        let email = try EMLParser.parse(eml)

        XCTAssertEqual(email.to.count, 1)
        XCTAssertEqual(email.to.first?.name, "Alex User")
        XCTAssertEqual(email.to.first?.email, "DUser@example.com")
    }

    // MARK: - Address Parsing

    func testParsesNameWithAngleBrackets() {
        let contact = EMLParser.parseAddress("Eve Example <TExample@example.com>")
        XCTAssertEqual(contact.name, "Eve Example")
        XCTAssertEqual(contact.email, "TExample@example.com")
    }

    func testParsesQuotedName() {
        let contact = EMLParser.parseAddress("\"Jane Doe\" <jane@example.com>")
        XCTAssertEqual(contact.name, "Jane Doe")
        XCTAssertEqual(contact.email, "jane@example.com")
    }

    func testParsesBareEmail() {
        let contact = EMLParser.parseAddress("user@example.com")
        XCTAssertEqual(contact.name, "")
        XCTAssertEqual(contact.email, "user@example.com")
    }

    func testParsesAddressList() {
        let contacts = EMLParser.parseAddressList("Alice <a@x.com>, Bob <b@x.com>, Carol <c@x.com>")
        XCTAssertEqual(contacts.count, 3)
        XCTAssertEqual(contacts[0].name, "Alice")
        XCTAssertEqual(contacts[1].name, "Bob")
        XCTAssertEqual(contacts[2].name, "Carol")
    }

    // MARK: - Date Parsing

    func testParsesRFC2822Date() {
        let date = EMLParser.parseDate("Fri, 3 Apr 2026 19:55:12 +0000")
        XCTAssertNotNil(date)

        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 3)
        XCTAssertEqual(components.hour, 19)
        XCTAssertEqual(components.minute, 55)
    }

    // MARK: - Body Extraction

    func testExtractsPlainTextBody() throws {
        let eml = try loadFixture("governance-email")
        let email = try EMLParser.parse(eml)

        XCTAssertTrue(email.body.contains("Hi guys"))
        XCTAssertTrue(email.body.contains("AI agent governance"))
        XCTAssertTrue(email.body.contains("Eve Example"))
    }

    func testExtractsVendorSpendBody() throws {
        let eml = try loadFixture("vendor-spend-email")
        let email = try EMLParser.parse(eml)

        XCTAssertTrue(email.body.contains("vendor spend for 2025"))
        XCTAssertTrue(email.body.contains("Alice Example"))
    }

    // MARK: - Quoted-Printable Decoding

    func testDecodesQuotedPrintableSoftBreaks() {
        let input = "long li=\nne continues"
        let decoded = EMLParser.decodeQuotedPrintable(input)
        XCTAssertEqual(decoded, "long line continues")
    }

    func testDecodesQuotedPrintableHexChars() {
        // =97 is em-dash in Windows-1252
        let input = "hello =97 world"
        let decoded = EMLParser.decodeQuotedPrintable(input, charset: "windows-1252")
        XCTAssertTrue(decoded.contains("hello"))
        XCTAssertTrue(decoded.contains("world"))
    }

    // MARK: - Attachment Extraction

    func testExtractsAttachmentFromVendorSpend() throws {
        let eml = try loadFixture("vendor-spend-email")
        let email = try EMLParser.parse(eml)

        let realAttachments = email.attachments.filter { !$0.isInline }
        XCTAssertEqual(realAttachments.count, 1)
        XCTAssertEqual(realAttachments.first?.filename, "Quarterly report.xlsx")
        XCTAssertTrue(realAttachments.first?.data.count ?? 0 > 0, "Attachment data should be non-empty")
    }

    func testMarksInlineImagesAsInline() throws {
        let eml = try loadFixture("governance-email")
        let email = try EMLParser.parse(eml)

        let inlineImages = email.attachments.filter { $0.isInline }
        XCTAssertTrue(inlineImages.count >= 1, "Should have at least one inline image (logo)")
        XCTAssertEqual(inlineImages.first?.filename, "image001.png")
    }

    func testGovernanceEmailHasNoRealAttachments() throws {
        let eml = try loadFixture("governance-email")
        let email = try EMLParser.parse(eml)

        let realAttachments = email.attachments.filter { !$0.isInline }
        XCTAssertEqual(realAttachments.count, 0)
    }

    // MARK: - Real Outlook Email with Multiple Attachments

    func testBoardMeetingExtractsAllRealAttachments() throws {
        // Outlook email with 5 attachments — all have both Content-Disposition: attachment
        // AND Content-ID. Previously all were mis-classified as inline and dropped.
        let eml = try loadFixture("board-meeting-with-attachments")
        let email = try EMLParser.parse(eml)

        let real = email.attachments.filter { !$0.isInline }
        XCTAssertGreaterThanOrEqual(real.count, 5, "Should extract all 5 Outlook attachments despite Content-ID presence")

        let names = Set(real.map { $0.filename })
        XCTAssertTrue(names.contains { $0.contains("Example Presentation") && $0.hasSuffix(".pdf") })
        XCTAssertTrue(names.contains { $0.contains("Committee Notes") })
        XCTAssertTrue(names.contains("Professional Standards.docx"))
    }

    func testAttachmentWithContentIDAndDispositionIsNotInline() {
        // Regression test for the bug: Content-ID should NOT override
        // Content-Disposition: attachment
        let eml = """
        From: test@example.com
        Subject: Test
        Date: Fri, 3 Apr 2026 19:55:12 +0000
        Content-Type: multipart/mixed; boundary="boundary1"

        --boundary1
        Content-Type: text/plain

        Body text

        --boundary1
        Content-Type: application/pdf; name="report.pdf"
        Content-Disposition: attachment; filename="report.pdf"
        Content-ID: <abc123@example>
        Content-Transfer-Encoding: base64

        SGVsbG8gUERG
        --boundary1--
        """
        let email = try! EMLParser.parse(eml)
        XCTAssertEqual(email.attachments.count, 1)
        XCTAssertFalse(email.attachments[0].isInline, "Attachment with both Content-ID and Content-Disposition: attachment should NOT be inline")
        XCTAssertEqual(email.attachments[0].filename, "report.pdf")
    }

    // MARK: - MIME Boundary

    func testExtractsBoundary() {
        let ct = "multipart/mixed; boundary=\"_006_abcdef\""
        XCTAssertEqual(EMLParser.extractBoundary(from: ct), "_006_abcdef")
    }

    func testExtractsBoundaryWithoutQuotes() {
        let ct = "multipart/alternative; boundary=_000_abcdef"
        XCTAssertEqual(EMLParser.extractBoundary(from: ct), "_000_abcdef")
    }

    // MARK: - Reply Prefix Stripping

    func testStripsREPrefix() {
        XCTAssertEqual(EmailMessage.stripReplyPrefix("RE: Quarterly report for 2025"), "Quarterly report for 2025")
    }

    func testStripsFWPrefix() {
        XCTAssertEqual(EmailMessage.stripReplyPrefix("FW: Important update"), "Important update")
    }

    func testStripsFwdPrefix() {
        XCTAssertEqual(EmailMessage.stripReplyPrefix("Fwd: Newsletter"), "Newsletter")
    }

    func testStripsMultiplePrefixes() {
        XCTAssertEqual(EmailMessage.stripReplyPrefix("RE: RE: FW: Topic"), "Topic")
    }

    func testStripsMixedCasePrefixes() {
        XCTAssertEqual(EmailMessage.stripReplyPrefix("Re: re: FWD: Hello"), "Hello")
    }

    func testPreservesSubjectWithoutPrefix() {
        XCTAssertEqual(EmailMessage.stripReplyPrefix("Regular subject"), "Regular subject")
    }

    // MARK: - Error Handling

    func testThrowsOnEmptyInput() {
        XCTAssertThrowsError(try EMLParser.parse("")) { error in
            XCTAssertTrue(error is EMLParseError)
        }
    }

    func testThrowsOnMissingSubject() {
        let eml = "From: test@example.com\nDate: Fri, 3 Apr 2026 19:55:12 +0000\n\nBody text"
        XCTAssertThrowsError(try EMLParser.parse(eml)) { error in
            XCTAssertTrue(error is EMLParseError)
        }
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "eml") else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture \(name).eml not found in test bundle"])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
