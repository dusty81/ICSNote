import Foundation

struct EmailContact: Equatable {
    let name: String
    let email: String
}

struct EmailAttachment {
    let filename: String
    let contentType: String
    let data: Data
    let isInline: Bool
}

struct EmailMessage {
    let subject: String
    let from: EmailContact
    let to: [EmailContact]
    let cc: [EmailContact]
    let date: Date
    let body: String
    let attachments: [EmailAttachment]

    /// The subject with RE:/FW:/Fwd: prefixes stripped for thread matching and filenames.
    var cleanSubject: String {
        EmailMessage.stripReplyPrefix(subject)
    }

    /// Strips leading reply/forward prefixes (RE:, Re:, FW:, Fwd:, FWD:, etc.)
    /// Handles multiples like "RE: RE: FW: Topic" → "Topic"
    static func stripReplyPrefix(_ subject: String) -> String {
        var result = subject
        let pattern = "^\\s*(RE|Re|re|FW|Fw|fw|FWD|Fwd|fwd)\\s*:\\s*"
        while let range = result.range(of: pattern, options: .regularExpression) {
            result = String(result[range.upperBound...])
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
