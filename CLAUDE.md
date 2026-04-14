# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

XcodeGen is required. The system's xcode-select points to CommandLineTools, so all xcodebuild commands must be prefixed:

```bash
# Generate Xcode project (run after any project.yml changes)
xcodegen generate

# Build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme ICSNote -destination 'platform=macOS' build

# Run all tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme ICSNoteTests -destination 'platform=macOS'

# Release build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme ICSNote -configuration Release -destination 'platform=macOS' -derivedDataPath ./build build
```

After creating or renaming Swift files, re-run `xcodegen generate` before building.

## Architecture

Two parallel pipelines: ICS text → CalendarEvent → Markdown, and EML text → EmailMessage → Markdown.

**Models** — `CalendarEvent` (meetings), `EmailMessage`/`EmailContact`/`EmailAttachment` (emails). `EmailMessage.stripReplyPrefix()` handles RE:/FW:/Fwd: stripping for thread matching.

**Services layer** (`ICSParser`, `EMLParser`, `MarkdownGenerator`) — stateless enums with static methods, no dependencies. `EMLParser` handles full MIME multipart parsing, quoted-printable/base64 decoding, and attachment extraction. `MarkdownGenerator` has parallel methods for meetings and emails, plus `updateNoteWithNewMessage()` for thread merging.

**ViewModel layer** (`AppViewModel`) — `@Observable @MainActor`, owns `AppSettings`, coordinates drop handling → parsing → generation → file writing → UI state. Routes ICS and EML content to separate processing pipelines. Handles attachment saving and thread merge detection.

**View layer** — `MainView` (drop zone + recent list), `SettingsView` (5-tab settings), `DropTargetView` (AppKit bridge for drag-and-drop).

### Drop Handling (the tricky part)

`DropTargetView` is an `NSViewRepresentable` wrapping `ICSDropNSView` — an AppKit NSView, not SwiftUI's `onDrop`. This exists because SwiftUI's `onDrop` does not reliably handle Outlook's `NSFilePromiseReceiver` on repeated drops.

The drop handler in `performDragOperation` uses four strategies in priority order:
1. **Quick ICS check** — only reads 3 known calendar pasteboard types (`com.apple.ical.ics`, `public.calendar-event`, `com.microsoft.outlook16.icalendar`). Does NOT scan all types — that's slow and interferes with Outlook's file promise setup. EML detection is NOT done inline because Outlook metadata types contain "From:" and "Subject:" without being valid EML.
2. **File URLs** — `NSURL` pasteboard objects for Finder drops of `.ics` and `.eml` files.
3. **File promises** — `NSFilePromiseReceiver` on a background `OperationQueue` with a unique temp directory per drop. Uses polling with increasing back-off (up to 6 attempts over ~6s) to wait for Outlook's async file write, then `NSFileCoordinator` for coordinated read. Routes both `.ics` and `.eml` files. Temp dirs are cleaned up immediately after reading.
4. **Full pasteboard fallback** — last resort scan of all types for ICS content only.

### ICS Parsing Specifics

- **Line unfolding** must happen first (RFC 5545: continuation lines start with space/tab).
- **Recurring event handling**: when a VEVENT has an RRULE or RECURRENCE-ID, the parser sets `isRecurring: true` on the `CalendarEvent`. The ViewModel then shows a date picker dialog (defaulting to today) so the user can confirm or change the occurrence date. This is critical because Outlook puts the series definition (first occurrence date) on the pasteboard, not the specific occurrence the user dragged. Outlook often includes both the series-definition VEVENT (with RRULE) and modified-occurrence VEVENTs (with RECURRENCE-ID but no RRULE); `selectNextOccurrence` picks the most recent, so RECURRENCE-ID must also trigger the recurring flow. The `CalendarEvent.withDate(_:)` method shifts the event to the chosen date while preserving the original time-of-day and duration.
- **Text replacements** are applied to titles before filename sanitization, so "1:1" becomes "One on One" before the colon would be stripped.

### Zoom/Teams Stripping

Outlook wraps URLs in `nam11.safelinks.protection.outlook.com` SafeLinks. Zoom blocks can end with either "International numbers" (phone dial-in) or `@zoomcrc.com` (H.323/SIP). The stripper tries multiple start-pattern × end-pattern combinations and returns on first match. End patterns are ordered so the **furthest** endpoint (`@zoomcrc.com`) is tried before closer ones (`International numbers`), ensuring the full block is consumed when H.323/SIP follows phone dial-in. A third Zoom format — `~===~` delimited blocks with "You have been invited to a Zoom meeting" — is also handled.

### EML Parsing Specifics

- **Header parsing** splits at the first blank line, unfolds continuation lines (starting with whitespace).
- **MIME multipart traversal** recursively walks `multipart/mixed` > `multipart/related` > `multipart/alternative` to find `text/plain` body and attachment parts.
- **Quoted-printable decoding** handles `=XX` hex bytes, `=\n` soft line breaks, and Windows-1252 charset.
- **Attachment extraction** distinguishes `Content-Disposition: attachment` (real files) from `Content-Disposition: inline` with `Content-ID` (signature images marked `isInline: true` and skipped during save).
- **Thread merging**: `EmailMessage.stripReplyPrefix()` strips RE:/FW:/Fwd: prefixes (case-insensitive, handles multiples). `AppViewModel.findExistingEmailNote()` scans the email output folder for a file whose name contains the cleaned subject. `MarkdownGenerator.updateNoteWithNewMessage()` moves the current ## Body into a collapsed `> [!quote]-` callout under ## Previous Messages and inserts the new body.

## Conventions

- All view models and settings use `@Observable` (not `ObservableObject`) with `@MainActor`.
- Settings persist via `UserDefaults` with `didSet { save() }` on each property.
- Logging uses `os.Logger` with `privacy: .public`.
- No external dependencies — pure Swift/SwiftUI/AppKit.
- Test fixtures are real ICS and EML files in `TestFixtures/`, loaded via `Bundle(for:).url(forResource:)`.
