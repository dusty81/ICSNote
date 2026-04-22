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
    let vaultID: UUID?
    let vaultName: String?
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

    // Hook execution state — maintained for the Activity window.
    // Capped at 100 entries; oldest are dropped.
    var hookRuns: [HookRun] = []
    private static let maxHookRuns = 100

    var hasRunningHooks: Bool {
        hookRuns.contains { !$0.isComplete }
    }

    var hasRecentHookFailures: Bool {
        hookRuns.prefix(10).contains { $0.isFailure }
    }

    // Recurring event date picker state
    var pendingEvent: CalendarEvent?
    var pendingEventVaultID: UUID?
    var showDatePicker = false
    var selectedDate = Date()

    // PDF conversion prompt state (Ask mode)
    var pendingEmail: EmailMessage?
    var pendingEmailVaultID: UUID?
    var pendingConvertibleFilenames: [String] = []
    var pendingEmailFilenames: [String] = []
    var showPDFConvertPrompt = false

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

    /// Resolve a target vault for an incoming drop. Defaults to the active vault
    /// when no explicit vault ID is provided. Returns nil (and shows an error)
    /// if no vault is configured.
    private func resolveTargetVault(_ vaultID: UUID?) -> VaultConfig? {
        let target: VaultConfig?
        if let vaultID, let v = settings.vault(id: vaultID), v.enabled {
            target = v
        } else {
            target = settings.activeVault
        }
        if target == nil {
            showError(message: "Please configure an Obsidian vault in Settings.")
        }
        return target
    }

    func processICSText(_ text: String, sourceName: String, vaultID: UUID? = nil) {
        guard let vault = resolveTargetVault(vaultID) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError(message: "The calendar data is empty.")
            return
        }
        do {
            let event = try ICSParser.parse(text)
            handleParsedEvent(event, vault: vault)
        } catch {
            Self.logger.error("Failed to process ICS from \(sourceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    func processFile(at url: URL, vaultID: UUID? = nil) {
        let ext = url.pathExtension.lowercased()
        guard ext == "ics" || ext == "eml" else {
            showError(message: "Only .ics and .eml files are supported.")
            return
        }
        guard let vault = resolveTargetVault(vaultID) else { return }
        do {
            let gaining = url.startAccessingSecurityScopedResource()
            defer { if gaining { url.stopAccessingSecurityScopedResource() } }

            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                showError(message: "The file is empty.")
                return
            }

            if ext == "eml" {
                processEMLText(text, sourceName: url.lastPathComponent, vaultID: vault.id)
            } else {
                let event = try ICSParser.parse(text)
                handleParsedEvent(event, vault: vault)
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

    func processEMLText(_ text: String, sourceName: String, vaultID: UUID? = nil) {
        guard let vault = resolveTargetVault(vaultID) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError(message: "The email data is empty.")
            return
        }
        do {
            let email = try EMLParser.parse(text)
            writeEmailAndRecord(email: email, vault: vault)
        } catch {
            Self.logger.error("Failed to process EML from \(sourceName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    private func writeEmailAndRecord(email: EmailMessage, vault: VaultConfig) {
        // Save attachments first, collecting the actual saved filenames
        var savedFilenames: [String] = []
        if settings.saveAttachments {
            savedFilenames = saveAttachments(from: email, vault: vault)
        } else {
            savedFilenames = email.attachments.filter { !$0.isInline }.map { $0.filename }
        }

        // Determine convertible files based on the original (non-PDF) attachments
        let convertibleFilenames = savedFilenames.filter { filename in
            !filename.lowercased().hasSuffix(".pdf") && PDFConverter.canConvert(filename: filename)
        }

        switch settings.pdfConversionMode {
        case .never:
            finalizeEmail(email: email, attachmentFilenames: savedFilenames, vault: vault)
        case .always:
            let finalFilenames = convertAttachmentsToPDF(originalFilenames: savedFilenames, convertibleFilenames: convertibleFilenames, vault: vault)
            finalizeEmail(email: email, attachmentFilenames: finalFilenames, vault: vault)
        case .ask:
            if convertibleFilenames.isEmpty {
                finalizeEmail(email: email, attachmentFilenames: savedFilenames, vault: vault)
            } else {
                // Store state and show prompt; user's choice will call confirmPDFConversion(convert:)
                pendingEmail = email
                pendingEmailVaultID = vault.id
                pendingConvertibleFilenames = convertibleFilenames
                pendingEmailFilenames = savedFilenames
                showPDFConvertPrompt = true
            }
        }
    }

    /// Called from the PDF conversion prompt dialog.
    func confirmPDFConversion(convert: Bool) {
        guard let email = pendingEmail,
              let vaultID = pendingEmailVaultID,
              let vault = settings.vault(id: vaultID) else {
            pendingEmail = nil
            pendingEmailVaultID = nil
            showPDFConvertPrompt = false
            return
        }
        let originalFilenames = pendingEmailFilenames
        let finalFilenames: [String]
        if convert {
            finalFilenames = convertAttachmentsToPDF(
                originalFilenames: originalFilenames,
                convertibleFilenames: pendingConvertibleFilenames,
                vault: vault
            )
        } else {
            finalFilenames = originalFilenames
        }
        pendingEmail = nil
        pendingEmailVaultID = nil
        pendingConvertibleFilenames = []
        pendingEmailFilenames = []
        showPDFConvertPrompt = false
        finalizeEmail(email: email, attachmentFilenames: finalFilenames, vault: vault)
    }

    /// Convert each convertible file in the attachment directory to a PDF.
    /// Returns the merged filename list (originals + new PDFs, preserving order).
    private func convertAttachmentsToPDF(originalFilenames: [String], convertibleFilenames: [String], vault: VaultConfig) -> [String] {
        guard let attachDir = vault.attachmentDirectoryURL else { return originalFilenames }

        var result: [String] = []
        for filename in originalFilenames {
            result.append(filename)
            if convertibleFilenames.contains(filename) {
                let sourceURL = attachDir.appendingPathComponent(filename)
                let baseName = (filename as NSString).deletingPathExtension
                var pdfURL = attachDir.appendingPathComponent("\(baseName).pdf")
                // Avoid collision
                var counter = 2
                while FileManager.default.fileExists(atPath: pdfURL.path) {
                    pdfURL = attachDir.appendingPathComponent("\(baseName)-\(counter).pdf")
                    counter += 1
                }
                if PDFConverter.convert(sourceURL: sourceURL, destinationURL: pdfURL) {
                    result.append(pdfURL.lastPathComponent)
                    Self.logger.info("Converted \(filename, privacy: .public) to \(pdfURL.lastPathComponent, privacy: .public)")
                } else {
                    Self.logger.error("PDF conversion failed for \(filename, privacy: .public)")
                }
            }
        }
        return result
    }

    /// Write the email note and record the conversion.
    private func finalizeEmail(email: EmailMessage, attachmentFilenames: [String], vault: VaultConfig) {
        do {
            let filename = MarkdownGenerator.generateFilename(
                email: email,
                textReplacements: settings.replacementTuples
            )

            // Thread merge: check for existing note with same subject in the target vault
            if settings.mergeEmailThreads, let existingURL = findExistingEmailNote(subject: email.cleanSubject, in: vault) {
                let existingContent = try String(contentsOf: existingURL, encoding: .utf8)
                let updated = MarkdownGenerator.updateNoteWithNewMessage(existingContent: existingContent, newEmail: email)
                try updated.write(to: existingURL, atomically: true, encoding: .utf8)

                let conversion = RecentConversion(
                    filename: existingURL.lastPathComponent,
                    attendeeCount: 0,
                    strippedInfo: "thread updated",
                    outputURL: existingURL,
                    timestamp: Date(),
                    vaultID: vault.id,
                    vaultName: vault.name
                )
                recentConversions.insert(conversion, at: 0)
                Self.logger.info("Updated thread: \(existingURL.lastPathComponent, privacy: .public)")
            } else {
                let markdown = MarkdownGenerator.generate(
                    email: email,
                    textReplacements: settings.replacementTuples,
                    notesTemplate: settings.emailNotesTemplate,
                    attachmentFilenames: attachmentFilenames
                )
                let outputURL = try writeEmailMarkdown(markdown, filename: filename, vault: vault)

                let attachmentCount = attachmentFilenames.count
                let info = attachmentCount > 0 ? "\(attachmentCount) attachment\(attachmentCount == 1 ? "" : "s")" : nil

                let conversion = RecentConversion(
                    filename: filename,
                    attendeeCount: 0,
                    strippedInfo: info,
                    outputURL: outputURL,
                    timestamp: Date(),
                    vaultID: vault.id,
                    vaultName: vault.name
                )
                recentConversions.insert(conversion, at: 0)
                Self.logger.info("Converted email: \(filename, privacy: .public)")
            }

            if settings.playSuccessSound {
                NSSound(named: .init("Glass"))?.play()
            }

            // Fire any matching post-save hooks (fire-and-forget).
            // Both the thread-merge and new-note paths end up here — use the final
            // file URL from whichever branch ran.
            let savedURL: URL
            if let last = recentConversions.first {
                savedURL = last.outputURL
            } else {
                return
            }
            let attachmentFullPaths = attachmentFilenames.compactMap { name -> String? in
                guard let attachDir = vault.attachmentDirectoryURL else { return nil }
                return attachDir.appendingPathComponent(name).path
            }
            let hookContext = HookContext.email(
                email: email,
                vault: vault,
                outputURL: savedURL,
                attachmentPaths: attachmentFullPaths
            )
            fireHooks(context: hookContext)
        } catch {
            Self.logger.error("Failed to write email note: \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    /// Search the vault's email output folder for an existing note whose filename contains the cleaned subject.
    private func findExistingEmailNote(subject: String, in vault: VaultConfig) -> URL? {
        guard let dir = vault.emailOutputDirectoryURL else { return nil }
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

    /// Save non-inline attachments to the vault's attachment directory.
    /// Returns the list of actual saved filenames (may differ from originals if
    /// duplicates caused -2/-3 suffixes), in the same order as the email's attachments.
    private func saveAttachments(from email: EmailMessage, vault: VaultConfig) -> [String] {
        guard let attachDir = vault.attachmentDirectoryURL else { return [] }
        let fm = FileManager.default
        var savedFilenames: [String] = []

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
                savedFilenames.append(fileURL.lastPathComponent)
                Self.logger.info("Saved attachment: \(fileURL.lastPathComponent, privacy: .public)")
            } catch {
                Self.logger.error("Failed to save attachment \(attachment.filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return savedFilenames
    }

    private func writeEmailMarkdown(_ content: String, filename: String, vault: VaultConfig) throws -> URL {
        guard let outputDir = vault.emailOutputDirectoryURL else {
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

    private func handleParsedEvent(_ event: CalendarEvent, vault: VaultConfig) {
        if event.isRecurring {
            pendingEvent = event
            pendingEventVaultID = vault.id
            // Prefer the parser's suggested occurrence date (often the actual
            // instance the user dragged) over a generic "today" default.
            selectedDate = event.suggestedOccurrenceDate
            showDatePicker = true
        } else {
            writeAndRecord(event: event, vault: vault)
        }
    }

    func confirmRecurringDate() {
        guard let event = pendingEvent,
              let vaultID = pendingEventVaultID,
              let vault = settings.vault(id: vaultID) else {
            pendingEvent = nil
            pendingEventVaultID = nil
            showDatePicker = false
            return
        }
        let adjusted = event.withDate(selectedDate)
        writeAndRecord(event: adjusted, vault: vault)
        pendingEvent = nil
        pendingEventVaultID = nil
        showDatePicker = false
    }

    func cancelRecurringDate() {
        pendingEvent = nil
        pendingEventVaultID = nil
        showDatePicker = false
    }

    // MARK: - Write & Record

    private func writeAndRecord(event: CalendarEvent, vault: VaultConfig) {
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
            let outputURL = try writeMarkdown(markdown, filename: filename, vault: vault)

            var stripped: [String] = []
            if settings.stripZoom && event.description.contains("Zoom") { stripped.append("Zoom") }
            if settings.stripTeams && event.description.lowercased().contains("teams meeting") { stripped.append("Teams") }

            let conversion = RecentConversion(
                filename: filename,
                attendeeCount: event.attendees.count,
                strippedInfo: stripped.isEmpty ? nil : stripped.joined(separator: ", ") + " stripped",
                outputURL: outputURL,
                timestamp: Date(),
                vaultID: vault.id,
                vaultName: vault.name
            )
            recentConversions.insert(conversion, at: 0)
            Self.logger.info("Converted \(filename, privacy: .public)")

            if settings.playSuccessSound {
                NSSound(named: .init("Glass"))?.play()
            }

            // Fire any matching post-save hooks (fire-and-forget)
            let hookContext = HookContext.meeting(event: event, vault: vault, outputURL: outputURL)
            fireHooks(context: hookContext)
        } catch {
            Self.logger.error("Failed to write markdown: \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - File Writing

    private func writeMarkdown(_ content: String, filename: String, vault: VaultConfig) throws -> URL {
        guard let outputDir = vault.outputDirectoryURL else {
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

    // MARK: - Hook Firing

    /// Fire hooks and record each run in `hookRuns` for the Activity window.
    private func fireHooks(context: HookContext) {
        HookRunner.fire(
            hooks: settings.hooks,
            context: context,
            customSkillPaths: settings.customSkillPaths,
            onStart: { [weak self] run in
                guard let self else { return }
                self.hookRuns.insert(run, at: 0)
                // Cap the list to prevent unbounded growth
                if self.hookRuns.count > Self.maxHookRuns {
                    self.hookRuns = Array(self.hookRuns.prefix(Self.maxHookRuns))
                }
            },
            onFinish: { [weak self] run in
                guard let self else { return }
                if let idx = self.hookRuns.firstIndex(where: { $0.id == run.id }) {
                    self.hookRuns[idx] = run
                }
            }
        )
    }

    func clearHookRuns() {
        hookRuns.removeAll()
    }

    /// Cancel a running hook. Fire-and-forget — the onFinish callback will
    /// update the row's status to `.cancelled` when the process exits.
    func cancelHookRun(_ run: HookRun) {
        guard !run.isComplete else { return }
        Task { await HookRunner.cancel(runID: run.id) }
    }

    // MARK: - Utilities

    func revealInFinder(_ conversion: RecentConversion) {
        NSWorkspace.shared.activateFileViewerSelecting([conversion.outputURL])
    }

    func openInObsidian(_ conversion: RecentConversion) {
        // Determine the target vault: prefer the conversion's recorded vault,
        // fall back to the active vault for older entries without vaultID.
        let vault: VaultConfig?
        if let id = conversion.vaultID, let v = settings.vault(id: id) {
            vault = v
        } else {
            vault = settings.activeVault
        }
        guard let vault else { return }

        // Build the file path within the vault by stripping the vault path prefix
        // from the output URL. This correctly handles whichever subfolder the
        // note was written to (meetings vs emails vs custom).
        let vaultBase = URL(fileURLWithPath: vault.path).standardizedFileURL.path
        let outputPath = conversion.outputURL.standardizedFileURL.path
        var relative = outputPath
        if outputPath.hasPrefix(vaultBase + "/") {
            relative = String(outputPath.dropFirst(vaultBase.count + 1))
        } else if outputPath.hasPrefix(vaultBase) {
            relative = String(outputPath.dropFirst(vaultBase.count))
        }
        // Strip .md extension for Obsidian URI
        if relative.hasSuffix(".md") {
            relative = String(relative.dropLast(3))
        }

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault.name),
            URLQueryItem(name: "file", value: relative),
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
