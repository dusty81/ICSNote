import Foundation
import SwiftUI
import UniformTypeIdentifiers
import os

struct RecentConversion: Identifiable {
    let id = UUID()
    let filename: String
    let attendeeCount: Int
    let strippedInfo: String?
    let outputURL: URL
    let timestamp: Date
}

@MainActor
@Observable
final class AppViewModel {

    private static let logger = Logger(subsystem: "com.icsnote.app", category: "AppViewModel")

    let settings: AppSettings

    var recentConversions: [RecentConversion] = []
    var errorMessage: String?
    var showError = false
    var isDropTargeted = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Drop Handling

    // Types to try, in priority order
    private static let calendarTypes = [
        "com.apple.ical.ics",
        "public.calendar-event",
        "com.microsoft.outlook16.icalendar",
        "public.text",
    ]

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            let registeredTypes = provider.registeredTypeIdentifiers
            Self.logger.info("Drop provider types: \(registeredTypes.joined(separator: ", "), privacy: .public)")

            // Strategy 1: Try loadDataRepresentation for calendar types
            // This loads data into memory, avoiding file promise timing issues
            for typeId in Self.calendarTypes {
                if provider.hasItemConformingToTypeIdentifier(typeId) {
                    Self.logger.info("Loading data representation for type: \(typeId, privacy: .public)")
                    provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, error in
                        Task { @MainActor in
                            if let data {
                                self.handleDroppedData(data, typeId: typeId)
                            } else if let error {
                                Self.logger.error("loadDataRepresentation(\(typeId, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                                // Fall through to file URL strategy
                                self.tryFileURL(provider: provider)
                            }
                        }
                    }
                    return true
                }
            }

            // Strategy 2: File URL (Finder drops of .ics files)
            tryFileURL(provider: provider)
            return true
        }
        return false
    }

    private func tryFileURL(provider: NSItemProvider) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                Task { @MainActor in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        self.processFile(at: url)
                    } else if let error {
                        self.showError(message: "Failed to read dropped file: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func handleDroppedData(_ data: Data, typeId: String) {
        Self.logger.info("Received \(data.count) bytes via \(typeId, privacy: .public)")

        guard !data.isEmpty else {
            Self.logger.error("Empty data from \(typeId, privacy: .public)")
            showError(message: "The dropped item contained no data.")
            return
        }

        // Try UTF-8 first, then UTF-16, then ASCII
        let icsText: String
        if let utf8 = String(data: data, encoding: .utf8) {
            icsText = utf8
        } else if let utf16 = String(data: data, encoding: .utf16) {
            icsText = utf16
        } else if let ascii = String(data: data, encoding: .ascii) {
            icsText = ascii
        } else {
            let hex = data.prefix(40).map { String(format: "%02x", $0) }.joined(separator: " ")
            showError(message: "Could not decode the dropped data. First bytes: \(hex)")
            return
        }

        if icsText.contains("BEGIN:VCALENDAR") || icsText.contains("BEGIN:VEVENT") {
            processICSText(icsText, sourceName: "Dropped Calendar Event")
        } else {
            let preview = String(icsText.prefix(100))
            showError(message: "The dropped item does not contain calendar data.\n\nType: \(typeId)\nPreview: \(preview)")
        }
    }

    // MARK: - Open / Import

    func handleOpenURL(_ url: URL) { processFile(at: url) }

    func handleFileImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url): processFile(at: url)
        case .failure(let error): showError(message: "Failed to open file: \(error.localizedDescription)")
        }
    }

    // MARK: - Processing

    func processICSText(_ text: String, sourceName: String) {
        guard settings.isVaultConfigured else {
            showError(message: "Please configure your Obsidian vault in Settings.")
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError(message: "The calendar data is empty.")
            return
        }
        do {
            let event = try ICSParser.parse(text)
            writeAndRecord(event: event)
        } catch {
            Self.logger.error("Failed to process ICS from \(sourceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    func processFile(at url: URL) {
        guard url.pathExtension.lowercased() == "ics" else {
            showError(message: "Only .ics files are supported.")
            return
        }
        guard settings.isVaultConfigured else {
            showError(message: "Please configure your Obsidian vault in Settings.")
            return
        }
        do {
            let gaining = url.startAccessingSecurityScopedResource()
            defer { if gaining { url.stopAccessingSecurityScopedResource() } }

            let icsText = try String(contentsOf: url, encoding: .utf8)
            guard !icsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showError(message: "The file is empty. It may not have been exported correctly from Outlook.")
                return
            }
            let event = try ICSParser.parse(icsText)
            writeAndRecord(event: event)
        } catch {
            Self.logger.error("Failed to process ICS: \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - Write & Record

    private func writeAndRecord(event: CalendarEvent) {
        do {
            let markdown = MarkdownGenerator.generate(
                event: event,
                stripZoom: settings.stripZoom,
                stripTeams: settings.stripTeams,
                textReplacements: settings.replacementTuples,
                notesTemplate: settings.notesTemplate
            )
            let filename = MarkdownGenerator.generateFilename(
                event: event,
                textReplacements: settings.replacementTuples
            )
            let outputURL = try writeMarkdown(markdown, filename: filename)

            var stripped: [String] = []
            if settings.stripZoom && event.description.contains("Zoom") { stripped.append("Zoom") }
            if settings.stripTeams && event.description.lowercased().contains("teams meeting") { stripped.append("Teams") }

            let conversion = RecentConversion(
                filename: filename,
                attendeeCount: event.attendees.count,
                strippedInfo: stripped.isEmpty ? nil : stripped.joined(separator: ", ") + " stripped",
                outputURL: outputURL,
                timestamp: Date()
            )
            recentConversions.insert(conversion, at: 0)
            Self.logger.info("Converted \(filename, privacy: .public)")
        } catch {
            Self.logger.error("Failed to write markdown: \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - File Writing

    private func writeMarkdown(_ content: String, filename: String) throws -> URL {
        guard let outputDir = settings.outputDirectoryURL else {
            throw NSError(domain: "ICSNote", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vault path not configured"])
        }
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }
        var fileURL = outputDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let name = (filename as NSString).deletingPathExtension
            var counter = 2
            while FileManager.default.fileExists(atPath: fileURL.path) {
                fileURL = outputDir.appendingPathComponent("\(name)-\(counter).md")
                counter += 1
            }
        }
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Utilities

    func revealInFinder(_ conversion: RecentConversion) {
        NSWorkspace.shared.activateFileViewerSelecting([conversion.outputURL])
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
