import XCTest
import SwiftUI
@testable import ICSNote

final class VaultConfigTests: XCTestCase {

    // MARK: - Default URLs

    func testOutputDirectoryWithSubfolder() {
        let v = VaultConfig(name: "Test", path: "/tmp/vault", subfolder: "Unfiled")
        XCTAssertEqual(v.outputDirectoryURL?.path, "/tmp/vault/Unfiled")
    }

    func testOutputDirectoryWithoutSubfolder() {
        let v = VaultConfig(name: "Test", path: "/tmp/vault", subfolder: "")
        XCTAssertEqual(v.outputDirectoryURL?.path, "/tmp/vault")
    }

    func testEmailOutputDirectory() {
        let v = VaultConfig(name: "Test", path: "/tmp/vault", emailSubfolder: "Emails")
        XCTAssertEqual(v.emailOutputDirectoryURL?.path, "/tmp/vault/Emails")
    }

    func testAttachmentDirectory() {
        let v = VaultConfig(name: "Test", path: "/tmp/vault", attachmentSubfolder: "attachments")
        XCTAssertEqual(v.attachmentDirectoryURL?.path, "/tmp/vault/attachments")
    }

    func testEmptyPathReturnsNilURLs() {
        let v = VaultConfig(name: "Test", path: "")
        XCTAssertNil(v.outputDirectoryURL)
        XCTAssertNil(v.emailOutputDirectoryURL)
        XCTAssertNil(v.attachmentDirectoryURL)
    }

    // MARK: - Color Hashing

    func testColorIsDeterministic() {
        let v1 = VaultConfig(name: "Workspace", path: "/Users/u/Obsidian/Workspace")
        let v2 = VaultConfig(name: "Different Name", path: "/Users/u/Obsidian/Workspace")
        // Same path → same color (color derived from path, not name)
        XCTAssertEqual(v1.color, v2.color)
    }

    func testShapeIsDeterministic() {
        let v1 = VaultConfig(name: "A", path: "/Users/u/Obsidian/Workspace")
        let v2 = VaultConfig(name: "B", path: "/Users/u/Obsidian/Workspace")
        XCTAssertEqual(v1.indicatorShape, v2.indicatorShape)
    }

    func testShapeAndColorUseIndependentHashBits() {
        // Two paths that happen to hash to the same color should NOT necessarily
        // hash to the same shape (shape uses higher-order bits of the hash).
        let paths = [
            "/Users/u/Obsidian/Workspace",
            "/Users/u/Obsidian/Consulting",
            "/Users/u/Obsidian/Personal",
            "/Users/u/Obsidian/Other Organizations",
        ]
        let pairs = paths.map { path -> (Color, VaultIndicatorShape) in
            let v = VaultConfig(name: "x", path: path)
            return (v.color, v.indicatorShape)
        }
        // All four should have distinct (color, shape) tuples
        let uniqueCombos = Set(pairs.map { "\($0.0.description)-\($0.1.rawValue)" })
        XCTAssertEqual(uniqueCombos.count, pairs.count, "All 4 example vaults should have unique (color, shape) combinations")
    }

    func testDifferentPathsGetDifferentColors() {
        let paths = [
            "/Users/u/Obsidian/Workspace",
            "/Users/u/Obsidian/Personal",
            "/Users/u/Obsidian/VaultC",
            "/Users/u/Obsidian/Consulting",
        ]
        let colors = Set(paths.map { VaultConfig(name: "x", path: $0).color.description })
        // Not guaranteed to be fully distinct with only 12 palette colors and 4 inputs,
        // but very likely — smoke test that hashing distributes reasonably.
        XCTAssertGreaterThanOrEqual(colors.count, 2, "Expected palette distribution to produce multiple colors across 4 paths")
    }

    // MARK: - Codable

    func testRoundTripEncoding() throws {
        let original = VaultConfig(
            name: "Workspace",
            path: "/Users/u/Obsidian/Workspace",
            enabled: true,
            subfolder: "Unfiled",
            emailSubfolder: "Emails",
            attachmentSubfolder: "attachments"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VaultConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - DropZoneLayout

    func testLayoutMaxEnabledVaults() {
        XCTAssertEqual(DropZoneLayout.grid.maxEnabledVaults, 6)
        XCTAssertEqual(DropZoneLayout.segmented.maxEnabledVaults, 5)
        XCTAssertEqual(DropZoneLayout.dropdown.maxEnabledVaults, .max)
    }

    func testLayoutRecommendations() {
        XCTAssertEqual(DropZoneLayout.recommended(forEnabledCount: 0), .dropdown)
        XCTAssertEqual(DropZoneLayout.recommended(forEnabledCount: 1), .dropdown)
        XCTAssertEqual(DropZoneLayout.recommended(forEnabledCount: 2), .grid)
        XCTAssertEqual(DropZoneLayout.recommended(forEnabledCount: 3), .grid)
        XCTAssertEqual(DropZoneLayout.recommended(forEnabledCount: 4), .segmented)
        XCTAssertEqual(DropZoneLayout.recommended(forEnabledCount: 5), .segmented)
        XCTAssertEqual(DropZoneLayout.recommended(forEnabledCount: 6), .dropdown)
        XCTAssertEqual(DropZoneLayout.recommended(forEnabledCount: 20), .dropdown)
    }
}
