import Foundation
import SwiftUI

struct VaultConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String             // Display name (vault folder name)
    var path: String             // Absolute filesystem path
    var enabled: Bool            // User opted in
    var subfolder: String        // Meeting notes subfolder
    var emailSubfolder: String   // Email notes subfolder
    var attachmentSubfolder: String

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        enabled: Bool = false,
        subfolder: String = "",
        emailSubfolder: String = "Emails",
        attachmentSubfolder: String = "attachments"
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.enabled = enabled
        self.subfolder = subfolder
        self.emailSubfolder = emailSubfolder
        self.attachmentSubfolder = attachmentSubfolder
    }

    var outputDirectoryURL: URL? {
        guard !path.isEmpty else { return nil }
        var url = URL(fileURLWithPath: path)
        if !subfolder.isEmpty { url = url.appendingPathComponent(subfolder) }
        return url
    }

    var emailOutputDirectoryURL: URL? {
        guard !path.isEmpty else { return nil }
        var url = URL(fileURLWithPath: path)
        if !emailSubfolder.isEmpty { url = url.appendingPathComponent(emailSubfolder) }
        return url
    }

    var attachmentDirectoryURL: URL? {
        guard !path.isEmpty else { return nil }
        var url = URL(fileURLWithPath: path)
        if !attachmentSubfolder.isEmpty { url = url.appendingPathComponent(attachmentSubfolder) }
        return url
    }

    /// Deterministic color derived from the vault path. Same vault always gets
    /// the same color across launches, across devices, across machines.
    /// Picks from a curated hue palette for pleasant contrast with system chrome.
    var color: Color {
        let hash = VaultConfig.stableHash(path)
        return Self.colorPalette[Int(hash % UInt64(Self.colorPalette.count))]
    }

    /// Deterministic shape indicator. Combined with `color`, this gives far
    /// better distinguishability than color alone — especially for users with
    /// vaults that hash to similar hues (teal/mint, red/pink, etc.).
    /// Independent hash bits pick shape vs color to avoid correlation.
    var indicatorShape: VaultIndicatorShape {
        let hash = VaultConfig.stableHash(path)
        let shapeHash = hash / UInt64(Self.colorPalette.count)
        return VaultIndicatorShape.allCases[Int(shapeHash % UInt64(VaultIndicatorShape.allCases.count))]
    }

    static let colorPalette: [Color] = [
        .blue, .green, .orange, .pink, .purple, .red, .teal, .yellow, .indigo, .mint, .cyan, .brown,
    ]

    /// FNV-1a hash — stable across Swift versions (Swift's String.hashValue is randomized per-process).
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Shape variants for the vault indicator dot. All are SF Symbols, drawn filled.
enum VaultIndicatorShape: String, CaseIterable {
    case circle, square, triangle, diamond, hexagon, pentagon, star, rhombus

    var sfSymbol: String {
        switch self {
        case .circle:   "circle.fill"
        case .square:   "square.fill"
        case .triangle: "triangle.fill"
        case .diamond:  "diamond.fill"
        case .hexagon:  "hexagon.fill"
        case .pentagon: "pentagon.fill"
        case .star:     "star.fill"
        case .rhombus:  "rhombus.fill"
        }
    }
}

/// Renders the vault's deterministic color + shape indicator.
struct VaultIndicator: View {
    let vault: VaultConfig
    var size: CGFloat = 10

    var body: some View {
        Image(systemName: vault.indicatorShape.sfSymbol)
            .font(.system(size: size))
            .foregroundStyle(vault.color)
    }
}

enum DropZoneLayout: String, CaseIterable, Identifiable, Codable {
    case grid       // Option A — drop zone per vault
    case dropdown   // Option B — single zone + dropdown
    case segmented  // Option C — single zone + segmented control

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grid: "Grid"
        case .dropdown: "Dropdown"
        case .segmented: "Segmented"
        }
    }

    /// Maximum enabled vaults this layout can comfortably display.
    /// Exceeding this falls back to dropdown.
    var maxEnabledVaults: Int {
        switch self {
        case .grid: 6
        case .segmented: 5
        case .dropdown: .max
        }
    }

    /// Recommended default layout for the given enabled-vault count.
    static func recommended(forEnabledCount count: Int) -> DropZoneLayout {
        switch count {
        case 0, 1: return .dropdown  // single vault → picker is hidden, layout doesn't matter visually
        case 2, 3: return .grid
        case 4, 5: return .segmented
        default:   return .dropdown
        }
    }
}
