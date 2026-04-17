import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

/// NSView-based drop target that properly handles NSFilePromiseReceiver
/// (used by Outlook when dragging calendar items). SwiftUI's onDrop doesn't
/// reliably resolve file promises on repeated drops.
///
/// Each instance is associated with a specific vault via its callbacks —
/// the callbacks close over the target vault ID in the caller's scope,
/// so multiple drop targets can coexist (e.g., for the grid layout).
struct VaultDropTargetView: NSViewRepresentable {
    let vaultID: UUID
    let onICSContent: (String, String) -> Void
    let onEMLContent: (String, String) -> Void
    let onDropTargeted: (Bool) -> Void

    func makeNSView(context: Context) -> ICSDropNSView {
        let view = ICSDropNSView()
        view.onICSContent = onICSContent
        view.onEMLContent = onEMLContent
        view.onDropTargeted = onDropTargeted
        return view
    }

    func updateNSView(_ nsView: ICSDropNSView, context: Context) {
        nsView.onICSContent = onICSContent
        nsView.onEMLContent = onEMLContent
        nsView.onDropTargeted = onDropTargeted
    }
}

class ICSDropNSView: NSView {
    private static let logger = Logger(subsystem: "com.icsnote.app", category: "DropTarget")

    var onICSContent: ((String, String) -> Void)?
    var onEMLContent: ((String, String) -> Void)?
    var onDropTargeted: ((Bool) -> Void)?

    /// Dedicated background queue for file promise resolution.
    /// Using main queue can block Outlook's file writing.
    private let promiseQueue = OperationQueue()

    /// Create a fresh unique directory for each promise to avoid name collisions
    private func makePromiseDestination() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ICSNote-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(
            NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) } + [
                .fileURL,
                NSPasteboard.PasteboardType("com.apple.ical.ics"),
                NSPasteboard.PasteboardType("com.apple.mail.email"),
                NSPasteboard.PasteboardType("public.email-message"),
            ]
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDropTargeted?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTargeted?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDropTargeted?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDropTargeted?(false)
        let pasteboard = sender.draggingPasteboard

        // Log pasteboard types for debugging (but don't read data yet —
        // reading all types eagerly can interfere with Outlook's file promises)
        if let types = pasteboard.types {
            Self.logger.info("Pasteboard types: \(types.map(\.rawValue).joined(separator: ", "), privacy: .public)")
        }

        // Strategy 1: Quick check of known ICS pasteboard types only.
        // Outlook usually puts inline ICS data on specific calendar types.
        // We intentionally do NOT scan all types — that's slow and can
        // interfere with Outlook's file promise setup.
        let icsTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("com.apple.ical.ics"),
            NSPasteboard.PasteboardType("public.calendar-event"),
            NSPasteboard.PasteboardType("com.microsoft.outlook16.icalendar"),
        ]
        for type in icsTypes {
            if let data = pasteboard.data(forType: type),
               data.count > 20,
               let text = String(data: data, encoding: .utf8),
               text.contains("BEGIN:VCALENDAR") {
                Self.logger.info("Found ICS data in pasteboard type: \(type.rawValue, privacy: .public)")
                DispatchQueue.main.async { [weak self] in
                    self?.onICSContent?(text, "Calendar Event")
                }
                return true
            }
        }

        // Strategy 2: File URLs (.ics or .eml from Finder)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL] {
            let supportedURLs = urls.filter { ["ics", "eml"].contains($0.pathExtension.lowercased()) }
            if !supportedURLs.isEmpty {
                Self.logger.info("Handling \(supportedURLs.count) file URL(s)")
                for url in supportedURLs {
                    readAndDeliverFile(at: url)
                }
                return true
            }
        }

        // Strategy 3: File promises (Outlook) with retry logic.
        // Outlook uses NSFilePromiseReceiver for both calendar and email drags.
        // The resolved file may be .ics or .eml — readAndDeliverFile routes both.
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !promises.isEmpty {
            Self.logger.info("Handling \(promises.count) file promise(s)")

            let destination = makePromiseDestination()
            for promise in promises {
                Self.logger.info("Promise file types: \(promise.fileTypes.joined(separator: ", "), privacy: .public)")

                promise.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                    if let error {
                        Self.logger.error("Promise failed: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    Self.logger.info("Promise resolved: \(url.lastPathComponent, privacy: .public)")

                    // Outlook writes the file asynchronously. Poll until the
                    // file exists and is non-empty, with increasing back-off.
                    let fm = FileManager.default
                    for attempt in 1...6 {
                        Thread.sleep(forTimeInterval: 0.3 * Double(attempt))
                        if fm.fileExists(atPath: url.path),
                           let attrs = try? fm.attributesOfItem(atPath: url.path),
                           let size = attrs[.size] as? UInt64, size > 10 {
                            Self.logger.info("File ready after attempt \(attempt): \(url.lastPathComponent, privacy: .public) (\(size) bytes)")
                            self?.readAndDeliverFile(at: url, cleanupDirectory: destination)
                            return
                        }
                        Self.logger.info("Attempt \(attempt): file not ready at \(url.lastPathComponent, privacy: .public)")
                    }

                    // Final attempt even if file seems small/missing
                    Self.logger.warning("File may not be fully written, attempting read anyway: \(url.lastPathComponent, privacy: .public)")
                    self?.readAndDeliverFile(at: url, cleanupDirectory: destination)
                }
            }
            return true
        }

        // Strategy 4: Last resort — scan ALL pasteboard types for inline content.
        // This catches edge cases where Outlook provides data in unexpected types.
        if let types = pasteboard.types {
            for type in types {
                guard let data = pasteboard.data(forType: type), data.count > 50 else { continue }
                guard let text = String(data: data, encoding: .utf8) else { continue }

                if text.contains("BEGIN:VCALENDAR") {
                    Self.logger.info("Fallback: found ICS in \(type.rawValue, privacy: .public)")
                    DispatchQueue.main.async { [weak self] in
                        self?.onICSContent?(text, "Calendar Event")
                    }
                    return true
                }
            }
        }

        Self.logger.error("No recognized data in drop")
        return false
    }

    /// Read file content using NSFileCoordinator and route to the appropriate callback.
    /// File promises from Outlook involve file coordination — we must coordinate
    /// our read to wait for Outlook's write to complete.
    /// May be called from a background queue.
    private func readAndDeliverFile(at url: URL, cleanupDirectory: URL? = nil) {
        let name = url.lastPathComponent
        Self.logger.info("Coordinating read of \(url.path, privacy: .public)")

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do {
                let text = try String(contentsOf: readURL, encoding: .utf8)
                Self.logger.info("Read \(text.count) chars from \(name, privacy: .public)")

                // Clean up temp directory to avoid leaving data on disk
                if let cleanupDirectory {
                    try? FileManager.default.removeItem(at: cleanupDirectory)
                    Self.logger.info("Cleaned up temp directory")
                }

                if text.contains("BEGIN:VCALENDAR") || text.contains("BEGIN:VEVENT") {
                    DispatchQueue.main.async { [weak self] in
                        self?.onICSContent?(text, name)
                    }
                } else if url.pathExtension.lowercased() == "eml" || (text.contains("From:") && text.contains("Subject:")) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onEMLContent?(text, name)
                    }
                } else {
                    Self.logger.error("Unrecognized file format (\(text.count) chars): \(name, privacy: .public)")
                }
            } catch {
                Self.logger.error("Failed to read \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                if let cleanupDirectory {
                    try? FileManager.default.removeItem(at: cleanupDirectory)
                }
            }
        }

        if let coordinatorError {
            Self.logger.error("File coordination error: \(coordinatorError.localizedDescription, privacy: .public)")
            if let cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanupDirectory)
            }
        }
    }
}
