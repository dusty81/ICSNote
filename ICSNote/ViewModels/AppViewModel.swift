import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AppKit
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

    // Recurring event date picker state
    var pendingEvent: CalendarEvent?
    var showDatePicker = false
    var selectedDate = Date()

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
        } else if looksLikeEML(icsText) {
            processEMLText(icsText, sourceName: "Dropped Email")
        } else {
            let preview = String(icsText.prefix(100))
            showError(message: "The dropped item does not contain calendar or email data.\n\nType: \(typeId)\nPreview: \(preview)")
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
            handleParsedEvent(event)
        } catch {
            Self.logger.error("Failed to process ICS from \(sourceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    func processFile(at url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "ics" || ext == "eml" else {
            showError(message: "Only .ics and .eml files are supported.")
            return
        }
        guard settings.isVaultConfigured else {
            showError(message: "Please configure your Obsidian vault in Settings.")
            return
        }
        do {
            let gaining = url.startAccessingSecurityScopedResource()
            defer { if gaining { url.stopAccessingSecurityScopedResource() } }

            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showError(message: "The file is empty.")
                return
            }

            if ext == "eml" {
                processEMLText(text, sourceName: url.lastPathComponent)
            } else {
                let event = try ICSParser.parse(text)
                handleParsedEvent(event)
            }
        } catch {
            Self.logger.error("Failed to process file: \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - EML Processing

    private func looksLikeEML(_ text: String) -> Bool {
        let start = String(text.prefix(2000))
        return start.contains("From:") && start.contains("Subject:")
    }

    func processEMLText(_ text: String, sourceName: String) {
        guard settings.isVaultConfigured else {
            showError(message: "Please configure your Obsidian vault in Settings.")
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError(message: "The email data is empty.")
            return
        }
        do {
            let email = try EMLParser.parse(text)
            writeEmailAndRecord(email: email)
        } catch {
            Self.logger.error("Failed to process EML from \(sourceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    private func writeEmailAndRecord(email: EmailMessage) {
        do {
            // Save attachments first
            if settings.saveAttachments {
                saveAttachments(from: email)
            }

            let filename = MarkdownGenerator.generateFilename(
                email: email,
                textReplacements: settings.replacementTuples
            )

            // Thread merge: check for existing note with same subject
            if settings.mergeEmailThreads, let existingURL = findExistingEmailNote(subject: email.cleanSubject) {
                let existingContent = try String(contentsOf: existingURL, encoding: .utf8)
                let updated = MarkdownGenerator.updateNoteWithNewMessage(existingContent: existingContent, newEmail: email)
                try updated.write(to: existingURL, atomically: true, encoding: .utf8)

                let conversion = RecentConversion(
                    filename: existingURL.lastPathComponent,
                    attendeeCount: 0,
                    strippedInfo: "thread updated",
                    outputURL: existingURL,
                    timestamp: Date()
                )
                recentConversions.insert(conversion, at: 0)
                Self.logger.info("Updated thread: \(existingURL.lastPathComponent, privacy: .public)")
            } else {
                let markdown = MarkdownGenerator.generate(
                    email: email,
                    textReplacements: settings.replacementTuples,
                    notesTemplate: settings.emailNotesTemplate
                )
                let outputURL = try writeEmailMarkdown(markdown, filename: filename)

                let attachmentCount = email.attachments.filter { !$0.isInline }.count
                let info = attachmentCount > 0 ? "\(attachmentCount) attachment\(attachmentCount == 1 ? "" : "s")" : nil

                let conversion = RecentConversion(
                    filename: filename,
                    attendeeCount: 0,
                    strippedInfo: info,
                    outputURL: outputURL,
                    timestamp: Date()
                )
                recentConversions.insert(conversion, at: 0)
                Self.logger.info("Converted email: \(filename, privacy: .public)")
            }

            if settings.playSuccessSound {
                NSSound(named: .init("Glass"))?.play()
            }
        } catch {
            Self.logger.error("Failed to write email note: \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    /// Search the email output folder for an existing note whose filename contains the cleaned subject.
    private func findExistingEmailNote(subject: String) -> URL? {
        guard let dir = settings.emailOutputDirectoryURL else { return nil }
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }

        let sanitized = MarkdownGenerator.sanitizeFilename(subject)
        guard !sanitized.isEmpty else { return nil }

        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }

        return contents.first { url in
            url.pathExtension == "md" && url.lastPathComponent.contains(sanitized)
        }
    }

    private func saveAttachments(from email: EmailMessage) {
        guard let attachDir = settings.attachmentDirectoryURL else { return }
        let fm = FileManager.default

        for attachment in email.attachments where !attachment.isInline {
            do {
                if !fm.fileExists(atPath: attachDir.path) {
                    try fm.createDirectory(at: attachDir, withIntermediateDirectories: true)
                }
                var fileURL = attachDir.appendingPathComponent(attachment.filename)
                if fm.fileExists(atPath: fileURL.path) {
                    let name = (attachment.filename as NSString).deletingPathExtension
                    let ext = (attachment.filename as NSString).pathExtension
                    var counter = 2
                    while fm.fileExists(atPath: fileURL.path) {
                        fileURL = attachDir.appendingPathComponent("\(name)-\(counter).\(ext)")
                        counter += 1
                    }
                }
                try attachment.data.write(to: fileURL)
                Self.logger.info("Saved attachment: \(fileURL.lastPathComponent, privacy: .public)")
            } catch {
                Self.logger.error("Failed to save attachment \(attachment.filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func writeEmailMarkdown(_ content: String, filename: String) throws -> URL {
        guard let outputDir = settings.emailOutputDirectoryURL else {
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

    // MARK: - Recurring Event Handling

    private func handleParsedEvent(_ event: CalendarEvent) {
        if event.isRecurring {
            pendingEvent = event
            selectedDate = Date()
            showDatePicker = true
        } else {
            writeAndRecord(event: event)
        }
    }

    func confirmRecurringDate() {
        guard let event = pendingEvent else { return }
        let adjusted = event.withDate(selectedDate)
        writeAndRecord(event: adjusted)
        pendingEvent = nil
        showDatePicker = false
    }

    func cancelRecurringDate() {
        pendingEvent = nil
        showDatePicker = false
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

            if settings.playSuccessSound {
                NSSound(named: .init("Glass"))?.play()
            }
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

    func openInObsidian(_ conversion: RecentConversion) {
        // Build obsidian://open URL from vault path and file
        // Format: obsidian://open?vault=VaultName&file=Subfolder/Filename
        let vaultName = (settings.vaultPath as NSString).lastPathComponent
        let baseName = conversion.filename.hasSuffix(".md")
            ? String(conversion.filename.dropLast(3))
            : conversion.filename
        let fileWithinVault: String
        if settings.subfolder.isEmpty {
            fileWithinVault = baseName
        } else {
            fileWithinVault = "\(settings.subfolder)/\(baseName)"
        }

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vaultName),
            URLQueryItem(name: "file", value: fileWithinVault),
        ]

        if let url = components.url {
            Self.logger.info("Opening in Obsidian: \(url.absoluteString, privacy: .public)")
            NSWorkspace.shared.open(url)
        }
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
