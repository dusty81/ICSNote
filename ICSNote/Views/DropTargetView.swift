import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

/// NSView-based drop target that properly handles NSFilePromiseReceiver
/// (used by Outlook when dragging calendar items). SwiftUI's onDrop doesn't
/// reliably resolve file promises on repeated drops.
struct DropTargetView: NSViewRepresentable {
    let onICSContent: (String, String) -> Void
    let onDropTargeted: (Bool) -> Void

    func makeNSView(context: Context) -> ICSDropNSView {
        let view = ICSDropNSView()
        view.onICSContent = onICSContent
        view.onDropTargeted = onDropTargeted
        return view
    }

    func updateNSView(_ nsView: ICSDropNSView, context: Context) {
        nsView.onICSContent = onICSContent
        nsView.onDropTargeted = onDropTargeted
    }
}

class ICSDropNSView: NSView {
    private static let logger = Logger(subsystem: "com.icsnote.app", category: "DropTarget")

    var onICSContent: ((String, String) -> Void)?
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

        // Log ALL pasteboard types and their data sizes for debugging
        if let types = pasteboard.types {
            for type in types {
                let data = pasteboard.data(forType: type)
                let size = data?.count ?? -1
                Self.logger.info("Pasteboard type: \(type.rawValue, privacy: .public) = \(size) bytes")

                // If any type contains ICS data, use it directly
                if let data, data.count > 20,
                   let text = String(data: data, encoding: .utf8),
                   text.contains("BEGIN:VCALENDAR") {
                    Self.logger.info("Found ICS data in pasteboard type: \(type.rawValue, privacy: .public)")
                    DispatchQueue.main.async { [weak self] in
                        self?.onICSContent?(text, "Calendar Event")
                    }
                    return true
                }
            }
        }

        // Strategy 1: File URLs (Finder drops of .ics files)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL] {
            let icsURLs = urls.filter { $0.pathExtension.lowercased() == "ics" }
            if !icsURLs.isEmpty {
                Self.logger.info("Handling \(icsURLs.count) file URL(s)")
                for url in icsURLs {
                    readAndDeliverICS(at: url)
                }
                return true
            }
        }

        // Strategy 2: File promises (Outlook) — resolve to temp dir on background queue
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !promises.isEmpty {
            Self.logger.info("Handling \(promises.count) file promise(s)")

            let destination = makePromiseDestination()
            for promise in promises {
                // Log the promised file types
                Self.logger.info("Promise file types: \(promise.fileTypes.joined(separator: ", "), privacy: .public)")

                promise.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                    if let error {
                        Self.logger.error("Promise failed: \(error.localizedDescription, privacy: .public)")
                        return
                    }
                    Self.logger.info("Promise resolved: \(url.lastPathComponent, privacy: .public)")

                    // Wait a moment for the file to be fully written, then read
                    Thread.sleep(forTimeInterval: 0.5)
                    self?.readAndDeliverICS(at: url, cleanupDirectory: destination)
                }
            }
            return true
        }

        Self.logger.error("No recognized calendar data in drop")
        return false
    }

    /// Read ICS content from a file using NSFileCoordinator.
    /// File promises from Outlook involve file coordination — we must coordinate
    /// our read to wait for Outlook's write to complete.
    /// May be called from a background queue.
    private func readAndDeliverICS(at url: URL, cleanupDirectory: URL? = nil) {
        let name = url.lastPathComponent
        Self.logger.info("Coordinating read of \(url.path, privacy: .public)")

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do {
                let icsText = try String(contentsOf: readURL, encoding: .utf8)
                Self.logger.info("Read \(icsText.count) chars from \(name, privacy: .public)")

                // Clean up temp directory to avoid leaving appointment data on disk
                if let cleanupDirectory {
                    try? FileManager.default.removeItem(at: cleanupDirectory)
                    Self.logger.info("Cleaned up temp directory")
                }

                if icsText.contains("BEGIN:VCALENDAR") || icsText.contains("BEGIN:VEVENT") {
                    DispatchQueue.main.async { [weak self] in
                        self?.onICSContent?(icsText, name)
                    }
                } else {
                    Self.logger.error("File does not contain ICS data (\(icsText.count) chars): \(name, privacy: .public)")
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
