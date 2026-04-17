import Foundation
import AppKit

/// Converts supported document files to PDF using NSAttributedString + NSPrintOperation.
/// Supports .doc, .docx, .rtf, .rtfd, .html, .htm, .txt, .webarchive.
/// Does NOT support .xlsx, .pptx, or other non-text formats — those return nil.
enum PDFConverter {

    /// File extensions we can reliably convert to PDF via NSAttributedString.
    static let supportedExtensions: Set<String> = [
        "doc", "docx", "rtf", "rtfd", "html", "htm", "txt", "webarchive",
    ]

    /// Returns true if the filename's extension is convertible to PDF.
    static func canConvert(filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// Convert the document at `sourceURL` to a PDF at `destinationURL`.
    /// Must be called on the main thread (NSPrintOperation requires it).
    /// Returns `true` on success, `false` on any failure.
    @MainActor
    static func convert(sourceURL: URL, destinationURL: URL) -> Bool {
        let ext = sourceURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return false }

        guard let attributed = loadAttributedString(from: sourceURL) else {
            return false
        }

        // Set up a text view to host the content for rendering
        let pageSize = NSSize(width: 612, height: 792) // US Letter points
        let margin: CGFloat = 36

        let textView = NSTextView(frame: NSRect(
            x: margin, y: margin,
            width: pageSize.width - 2 * margin,
            height: pageSize.height - 2 * margin
        ))
        textView.textStorage?.setAttributedString(attributed)

        // Configure print info to save as PDF
        let printInfo = NSPrintInfo()
        printInfo.paperSize = pageSize
        printInfo.topMargin = margin
        printInfo.bottomMargin = margin
        printInfo.leftMargin = margin
        printInfo.rightMargin = margin
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destinationURL

        let printOp = NSPrintOperation(view: textView, printInfo: printInfo)
        printOp.showsPrintPanel = false
        printOp.showsProgressPanel = false

        return printOp.run()
    }

    /// Load an attributed string from a document file, hinting at the format by extension.
    private static func loadAttributedString(from url: URL) -> NSAttributedString? {
        let ext = url.pathExtension.lowercased()
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]

        switch ext {
        case "docx":
            options[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc":
            options[.documentType] = NSAttributedString.DocumentType.docFormat
        case "rtf":
            options[.documentType] = NSAttributedString.DocumentType.rtf
        case "rtfd":
            options[.documentType] = NSAttributedString.DocumentType.rtfd
        case "html", "htm":
            options[.documentType] = NSAttributedString.DocumentType.html
        case "txt":
            options[.documentType] = NSAttributedString.DocumentType.plain
        case "webarchive":
            options[.documentType] = NSAttributedString.DocumentType.webArchive
        default:
            break
        }

        return try? NSAttributedString(url: url, options: options, documentAttributes: nil)
    }
}
