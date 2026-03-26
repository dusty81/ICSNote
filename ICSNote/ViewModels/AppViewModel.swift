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

    // UTType identifiers Outlook may use when dragging calendar items
    private static let outlookCalendarType = "com.microsoft.outlook16.icalendar"
    private static let icsType = "com.apple.ical.ics"
    private static let calendarTextTypes = [outlookCalendarType, icsType, "public.calendar-event"]

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // First try: Outlook or calendar-specific pasteboard types (raw ICS text)
            for calType in Self.calendarTextTypes {
                if provider.hasItemConformingToTypeIdentifier(calType) {
                    provider.loadItem(forTypeIdentifier: calType, options: nil) { item, error in
                        Task { @MainActor in
                            if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                                self.processICSText(text, sourceName: "Outlook Calendar Event")
                            } else if let text = item as? String {
                                self.processICSText(text, sourceName: "Outlook Calendar Event")
                            } else if let error {
                                self.showError(message: "Failed to read calendar data: \(error.localizedDescription)")
                            }
                        }
                    }
                    return true
                }
            }

            // Fallback: file URL (from Finder)
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
                return true
            }
        }
        return false
    }

    func handleOpenURL(_ url: URL) { processFile(at: url) }

    func handleFileImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url): processFile(at: url)
        case .failure(let error): showError(message: "Failed to open file: \(error.localizedDescription)")
        }
    }

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

    func revealInFinder(_ conversion: RecentConversion) {
        NSWorkspace.shared.activateFileViewerSelecting([conversion.outputURL])
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
