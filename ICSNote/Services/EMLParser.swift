import Foundation

enum EMLParseError: LocalizedError {
    case noBodyFound
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .noBodyFound:
            "No message body found in email"
        case .invalidFormat(let detail):
            "Could not parse email: \(detail)"
        }
    }
}

enum EMLParser {

    // MARK: - Public API

    static func parse(_ text: String) throws -> EmailMessage {
        let (headerBlock, bodyBlock) = splitHeadersAndBody(text)
        guard !headerBlock.isEmpty else {
            throw EMLParseError.invalidFormat("No headers found")
        }

        let headers = parseHeaders(headerBlock)

        guard let subject = headers["subject"], !subject.isEmpty else {
            throw EMLParseError.invalidFormat("No Subject header")
        }

        let from = parseAddress(headers["from"] ?? "")
        let to = parseAddressList(headers["to"] ?? "")
        let cc = parseAddressList(headers["cc"] ?? "")
        let date = parseDate(headers["date"] ?? "") ?? Date()

        let contentType = headers["content-type"] ?? "text/plain"

        var body = ""
        var attachments: [EmailAttachment] = []

        if contentType.lowercased().contains("multipart/") {
            let parts = parseMIMEParts(bodyBlock, contentType: contentType)
            body = extractBody(from: parts)
            attachments = extractAttachments(from: parts)
        } else {
            // Single-part message
            let encoding = headers["content-transfer-encoding"] ?? "7bit"
            body = decodeContent(bodyBlock, encoding: encoding, charset: extractCharset(from: contentType))
        }

        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EMLParseError.noBodyFound
        }

        return EmailMessage(
            subject: subject,
            from: from,
            to: to,
            cc: cc,
            date: date,
            body: body,
            attachments: attachments
        )
    }

    // MARK: - Header Parsing

    /// Split raw EML text into header block and body block at the first blank line.
    /// Headers may have continuation lines (starting with whitespace).
    private static func splitHeadersAndBody(_ text: String) -> (String, String) {
        // Normalize line endings
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        // First blank line separates headers from body
        if let range = normalized.range(of: "\n\n") {
            let headers = String(normalized[normalized.startIndex..<range.lowerBound])
            let body = String(normalized[range.upperBound...])
            return (headers, body)
        }
        return (normalized, "")
    }

    /// Parse unfolded headers into a dictionary. Header names are lowercased.
    /// Continuation lines (starting with space/tab) are joined to the previous header.
    static func parseHeaders(_ headerBlock: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentKey: String?
        var currentValue: String = ""

        for line in headerBlock.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // Continuation line
                if currentKey != nil {
                    currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                }
            } else if let colonIndex = line.firstIndex(of: ":") {
                // Save previous header
                if let key = currentKey {
                    headers[key] = currentValue
                }
                currentKey = String(line[line.startIndex..<colonIndex]).lowercased().trimmingCharacters(in: .whitespaces)
                currentValue = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        // Save last header
        if let key = currentKey {
            headers[key] = currentValue
        }

        return headers
    }

    // MARK: - Address Parsing

    /// Parse a single email address: "Display Name" <email@example.com> or email@example.com
    static func parseAddress(_ raw: String) -> EmailContact {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Format: "Name" <email> or Name <email>
        if let angleBracketStart = trimmed.lastIndex(of: "<"),
           let angleBracketEnd = trimmed.lastIndex(of: ">") {
            let email = String(trimmed[trimmed.index(after: angleBracketStart)..<angleBracketEnd])
                .trimmingCharacters(in: .whitespaces)
            var name = String(trimmed[trimmed.startIndex..<angleBracketStart])
                .trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if name.hasPrefix("\"") && name.hasSuffix("\"") {
                name = String(name.dropFirst().dropLast())
            }
            return EmailContact(name: name, email: email)
        }

        // Bare email
        if trimmed.contains("@") {
            return EmailContact(name: "", email: trimmed)
        }

        return EmailContact(name: trimmed, email: "")
    }

    /// Parse a comma-separated list of addresses, handling commas inside quoted names.
    static func parseAddressList(_ raw: String) -> [EmailContact] {
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        var contacts: [EmailContact] = []
        var current = ""
        var inQuotes = false
        var angleBracketDepth = 0

        for char in raw {
            if char == "\"" { inQuotes.toggle() }
            if char == "<" { angleBracketDepth += 1 }
            if char == ">" { angleBracketDepth = max(0, angleBracketDepth - 1) }

            if char == "," && !inQuotes && angleBracketDepth == 0 {
                let contact = parseAddress(current)
                if !contact.email.isEmpty || !contact.name.isEmpty {
                    contacts.append(contact)
                }
                current = ""
            } else {
                current.append(char)
            }
        }

        // Last entry
        let contact = parseAddress(current)
        if !contact.email.isEmpty || !contact.name.isEmpty {
            contacts.append(contact)
        }

        return contacts
    }

    // MARK: - Date Parsing

    /// Parse RFC 2822 date: "Fri, 3 Apr 2026 19:55:12 +0000"
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try with day name
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        if let date = formatter.date(from: trimmed) { return date }

        // Try without day name
        formatter.dateFormat = "d MMM yyyy HH:mm:ss Z"
        if let date = formatter.date(from: trimmed) { return date }

        // Try with timezone abbreviation
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: trimmed) { return date }

        return nil
    }

    // MARK: - MIME Multipart Parsing

    /// Represents a single MIME part with its headers and content.
    struct MIMEPart {
        let headers: [String: String]
        let content: String
        let subparts: [MIMEPart]

        var contentType: String { headers["content-type"] ?? "text/plain" }
        var encoding: String { headers["content-transfer-encoding"] ?? "7bit" }
        var isMultipart: Bool { contentType.lowercased().contains("multipart/") }
    }

    /// Parse the body of a multipart message into its MIME parts.
    /// Recursively handles nested multipart structures.
    private static func parseMIMEParts(_ body: String, contentType: String) -> [MIMEPart] {
        guard let boundary = extractBoundary(from: contentType) else { return [] }

        let delimiter = "--\(boundary)"
        let endDelimiter = "--\(boundary)--"

        let sections = body.components(separatedBy: delimiter)
        var parts: [MIMEPart] = []

        for (index, section) in sections.enumerated() {
            // Skip preamble (before first boundary) and epilogue
            if index == 0 { continue }
            let trimmed = section.trimmingCharacters(in: .newlines)
            if trimmed.isEmpty || trimmed.hasPrefix("--") { continue }

            // Check for end delimiter
            let sectionContent: String
            if let endRange = section.range(of: endDelimiter) {
                sectionContent = String(section[section.startIndex..<endRange.lowerBound])
            } else {
                sectionContent = section
            }

            // Remove leading newline after boundary
            let cleaned = sectionContent.hasPrefix("\n")
                ? String(sectionContent.dropFirst())
                : sectionContent

            let (partHeaderBlock, partBody) = splitHeadersAndBody(cleaned)
            let partHeaders = parseHeaders(partHeaderBlock)
            let partContentType = partHeaders["content-type"] ?? "text/plain"

            if partContentType.lowercased().contains("multipart/") {
                let subparts = parseMIMEParts(partBody, contentType: partContentType)
                parts.append(MIMEPart(headers: partHeaders, content: partBody, subparts: subparts))
            } else {
                parts.append(MIMEPart(headers: partHeaders, content: partBody, subparts: []))
            }
        }

        return parts
    }

    /// Extract boundary string from Content-Type header.
    static func extractBoundary(from contentType: String) -> String? {
        // Match boundary="value" or boundary=value
        let pattern = "boundary\\s*=\\s*\"?([^\"\\s;]+)\"?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: contentType, range: NSRange(contentType.startIndex..., in: contentType)),
              let range = Range(match.range(at: 1), in: contentType) else {
            return nil
        }
        return String(contentType[range])
    }

    // MARK: - Body Extraction

    /// Walk the MIME tree to find the text/plain body. Falls back to text/html.
    private static func extractBody(from parts: [MIMEPart]) -> String {
        // First pass: look for text/plain
        if let plain = findPart(in: parts, matching: "text/plain") {
            let charset = extractCharset(from: plain.contentType)
            return decodeContent(plain.content, encoding: plain.encoding, charset: charset)
        }

        // Fallback: text/html → strip tags
        if let html = findPart(in: parts, matching: "text/html") {
            let charset = extractCharset(from: html.contentType)
            let decoded = decodeContent(html.content, encoding: html.encoding, charset: charset)
            return stripHTMLTags(decoded)
        }

        return ""
    }

    /// Recursively search MIME parts for a matching content type.
    private static func findPart(in parts: [MIMEPart], matching type: String) -> MIMEPart? {
        for part in parts {
            if part.isMultipart {
                if let found = findPart(in: part.subparts, matching: type) {
                    return found
                }
            } else if part.contentType.lowercased().contains(type.lowercased()) {
                return part
            }
        }
        return nil
    }

    // MARK: - Attachment Extraction

    /// Collect all non-text MIME parts as attachments.
    private static func extractAttachments(from parts: [MIMEPart]) -> [EmailAttachment] {
        var attachments: [EmailAttachment] = []
        collectAttachments(from: parts, into: &attachments)
        return attachments
    }

    private static func collectAttachments(from parts: [MIMEPart], into attachments: inout [EmailAttachment]) {
        for part in parts {
            if part.isMultipart {
                collectAttachments(from: part.subparts, into: &attachments)
                continue
            }

            let ct = part.contentType.lowercased()
            // Skip text parts (body alternatives)
            if ct.hasPrefix("text/plain") || ct.hasPrefix("text/html") { continue }

            // Content-Disposition: attachment wins even if Content-ID is set.
            // Outlook puts Content-IDs on real attachments too, so we can't
            // treat Content-ID presence alone as "inline".
            let disposition = (part.headers["content-disposition"] ?? "").lowercased()
            let contentID = part.headers["content-id"] ?? ""
            let isInline: Bool
            if disposition.contains("attachment") {
                isInline = false
            } else if disposition.contains("inline") {
                isInline = true
            } else {
                // No disposition — treat as inline only if it has a Content-ID
                // (typical for embedded signature images)
                isInline = !contentID.isEmpty
            }

            let filename = extractFilename(from: part.headers) ?? "attachment"

            // Decode binary content
            if let data = Data(base64Encoded: part.content.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")) {
                attachments.append(EmailAttachment(
                    filename: filename,
                    contentType: ct,
                    data: data,
                    isInline: isInline
                ))
            }
        }
    }

    /// Extract filename from Content-Disposition or Content-Type headers.
    private static func extractFilename(from headers: [String: String]) -> String? {
        // Try Content-Disposition first
        if let disposition = headers["content-disposition"],
           let name = extractParameter("filename", from: disposition) {
            return name
        }
        // Fall back to Content-Type name parameter
        if let contentType = headers["content-type"],
           let name = extractParameter("name", from: contentType) {
            return name
        }
        return nil
    }

    /// Extract a parameter value from a header like: attachment; filename="file.xlsx"
    private static func extractParameter(_ param: String, from header: String) -> String? {
        // Try quoted value first (handles spaces in filenames)
        let quotedPattern = "\(param)\\s*=\\s*\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: quotedPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
           let range = Range(match.range(at: 1), in: header) {
            return String(header[range])
        }
        // Fall back to unquoted value
        let unquotedPattern = "\(param)\\s*=\\s*([^\\s;]+)"
        if let regex = try? NSRegularExpression(pattern: unquotedPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
           let range = Range(match.range(at: 1), in: header) {
            return String(header[range])
        }
        return nil
    }

    // MARK: - Content Decoding

    /// Decode content based on Content-Transfer-Encoding and charset.
    static func decodeContent(_ content: String, encoding: String, charset: String) -> String {
        switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
        case "quoted-printable":
            return decodeQuotedPrintable(content, charset: charset)
        case "base64":
            let cleaned = content
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let data = Data(base64Encoded: cleaned) {
                let cfEncoding = charsetToCFEncoding(charset)
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                return String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) ?? String(data: data, encoding: .utf8) ?? ""
            }
            return content
        default:
            // 7bit, 8bit, binary — return as-is
            return content
        }
    }

    /// Decode quoted-printable encoded text.
    static func decodeQuotedPrintable(_ text: String, charset: String = "utf-8") -> String {
        var bytes: [UInt8] = []
        var i = text.startIndex

        while i < text.endIndex {
            let char = text[i]
            if char == "=" {
                let next = text.index(after: i)
                if next < text.endIndex && text[next] == "\n" {
                    // Soft line break — skip
                    i = text.index(after: next)
                    continue
                }
                if next < text.endIndex && text[next] == "\r" {
                    // Soft line break with CR
                    let afterCR = text.index(after: next)
                    if afterCR < text.endIndex && text[afterCR] == "\n" {
                        i = text.index(after: afterCR)
                    } else {
                        i = text.index(after: next)
                    }
                    continue
                }
                // Hex encoded byte
                let hexStart = next
                if hexStart < text.endIndex {
                    let hexEnd = text.index(hexStart, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                    let hex = String(text[hexStart..<hexEnd])
                    if hex.count == 2, let byte = UInt8(hex, radix: 16) {
                        bytes.append(byte)
                        i = hexEnd
                        continue
                    }
                }
            }

            // Regular character
            for byte in String(char).utf8 {
                bytes.append(byte)
            }
            i = text.index(after: i)
        }

        let data = Data(bytes)
        let cfEncoding = charsetToCFEncoding(charset)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? ""
    }

    // MARK: - Charset Helpers

    static func extractCharset(from contentType: String) -> String {
        let pattern = "charset\\s*=\\s*\"?([^\"\\s;]+)\"?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: contentType, range: NSRange(contentType.startIndex..., in: contentType)),
              let range = Range(match.range(at: 1), in: contentType) else {
            return "utf-8"
        }
        return String(contentType[range])
    }

    private static func charsetToCFEncoding(_ charset: String) -> CFStringEncoding {
        let lower = charset.lowercased()
        switch lower {
        case "windows-1252", "cp1252":
            return 0x0500 // kCFStringEncodingWindowsLatin1
        case "iso-8859-1", "latin1":
            return 0x0201 // kCFStringEncodingISOLatin1
        case "us-ascii", "ascii":
            return CFStringBuiltInEncodings.ASCII.rawValue
        default:
            return CFStringBuiltInEncodings.UTF8.rawValue
        }
    }

    // MARK: - HTML Stripping

    private static func stripHTMLTags(_ html: String) -> String {
        var result = html
        // Replace <br> and <p> with newlines
        result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        // Strip all remaining tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        // Collapse excessive whitespace
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
