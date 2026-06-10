import XCTest
@testable import ICSNote

final class NoteHistoryStoreTests: XCTestCase {

    private func sampleConversion(noteType: HookTrigger = .meeting) -> RecentConversion {
        RecentConversion(
            filename: "2026-06-10 Standup.md",
            attendeeCount: 3,
            strippedInfo: "Zoom stripped",
            outputURL: URL(fileURLWithPath: "/vault/Unfiled/2026-06-10 Standup.md"),
            timestamp: Date(timeIntervalSince1970: 1_749_600_000),
            vaultID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            vaultName: "Work",
            noteType: noteType
        )
    }

    // MARK: - RecentConversion Codable

    func testRecentConversionRoundTrips() throws {
        let original = sampleConversion()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecentConversion.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.filename, "2026-06-10 Standup.md")
        XCTAssertEqual(decoded.attendeeCount, 3)
        XCTAssertEqual(decoded.strippedInfo, "Zoom stripped")
        XCTAssertEqual(decoded.outputURL.path, "/vault/Unfiled/2026-06-10 Standup.md")
        XCTAssertEqual(decoded.timestamp, Date(timeIntervalSince1970: 1_749_600_000))
        XCTAssertEqual(decoded.vaultID, UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        XCTAssertEqual(decoded.vaultName, "Work")
        XCTAssertEqual(decoded.noteType, .meeting)
    }

    func testRecentConversionEmailRoundTrips() throws {
        let original = sampleConversion(noteType: .email)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecentConversion.self, from: data)
        XCTAssertEqual(decoded.noteType, .email)
    }

    func testRecentConversionNilFieldsRoundTrip() throws {
        let c = RecentConversion(
            filename: "note.md",
            attendeeCount: 0,
            strippedInfo: nil,
            outputURL: URL(fileURLWithPath: "/v/note.md"),
            timestamp: Date(timeIntervalSince1970: 0),
            vaultID: nil,
            vaultName: nil,
            noteType: .meeting
        )
        let decoded = try JSONDecoder().decode(RecentConversion.self, from: try JSONEncoder().encode(c))
        XCTAssertNil(decoded.strippedInfo)
        XCTAssertNil(decoded.vaultID)
        XCTAssertNil(decoded.vaultName)
    }

    // MARK: - NoteHistoryStore

    func testLoadReturnsEmptyWhenFileAbsent() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-history-\(UUID().uuidString).json")
        let entries = NoteHistoryStore.load(from: url)
        XCTAssertTrue(entries.isEmpty)
    }

    func testSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let entries = [sampleConversion(), sampleConversion(noteType: .email)]
        NoteHistoryStore.save(entries, to: url)

        let loaded = NoteHistoryStore.load(from: url)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].filename, entries[0].filename)
        XCTAssertEqual(loaded[1].noteType, .email)
    }

    func testSaveOverwritesExistingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        NoteHistoryStore.save([sampleConversion()], to: url)
        NoteHistoryStore.save([sampleConversion(), sampleConversion()], to: url)

        let loaded = NoteHistoryStore.load(from: url)
        XCTAssertEqual(loaded.count, 2)
    }
}
