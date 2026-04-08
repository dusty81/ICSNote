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

Three-layer pipeline: ICS text → CalendarEvent model → Markdown string + file.

**Services layer** (`ICSParser`, `MarkdownGenerator`) — stateless enums with static methods, no dependencies. All parsing and generation logic lives here. This is where most feature work happens.

**ViewModel layer** (`AppViewModel`) — `@Observable @MainActor`, owns `AppSettings`, coordinates drop handling → parsing → generation → file writing → UI state. Single instance created in `ICSNoteApp`.

**View layer** — `MainView` (drop zone + recent list), `SettingsView` (4-tab settings), `DropTargetView` (AppKit bridge for drag-and-drop).

### Drop Handling (the tricky part)

`DropTargetView` is an `NSViewRepresentable` wrapping `ICSDropNSView` — an AppKit NSView, not SwiftUI's `onDrop`. This exists because SwiftUI's `onDrop` does not reliably handle Outlook's `NSFilePromiseReceiver` on repeated drops.

The drop handler in `performDragOperation` uses three strategies in priority order:
1. **Pasteboard scan** — iterates all pasteboard types looking for inline ICS data (`BEGIN:VCALENDAR`). This is what actually works for Outlook most of the time.
2. **File URLs** — `NSURL` pasteboard objects for Finder drops.
3. **File promises** — `NSFilePromiseReceiver` on a background `OperationQueue` with a unique temp directory per drop, `Thread.sleep(0.5)` for Outlook's async write, and `NSFileCoordinator` for coordinated read. Temp dirs are cleaned up immediately after reading.

### ICS Parsing Specifics

- **Line unfolding** must happen first (RFC 5545: continuation lines start with space/tab).
- **Recurring event handling**: when a VEVENT has an RRULE or RECURRENCE-ID, the parser sets `isRecurring: true` on the `CalendarEvent`. The ViewModel then shows a date picker dialog (defaulting to today) so the user can confirm or change the occurrence date. This is critical because Outlook puts the series definition (first occurrence date) on the pasteboard, not the specific occurrence the user dragged. Outlook often includes both the series-definition VEVENT (with RRULE) and modified-occurrence VEVENTs (with RECURRENCE-ID but no RRULE); `selectNextOccurrence` picks the most recent, so RECURRENCE-ID must also trigger the recurring flow. The `CalendarEvent.withDate(_:)` method shifts the event to the chosen date while preserving the original time-of-day and duration.
- **Text replacements** are applied to titles before filename sanitization, so "1:1" becomes "One on One" before the colon would be stripped.

### Zoom/Teams Stripping

Outlook wraps URLs in `nam11.safelinks.protection.outlook.com` SafeLinks. Zoom blocks can end with either "International numbers" (phone dial-in) or `@zoomcrc.com` (H.323/SIP). The stripper tries multiple start-pattern × end-pattern combinations and returns on first match. End patterns are ordered so the **furthest** endpoint (`@zoomcrc.com`) is tried before closer ones (`International numbers`), ensuring the full block is consumed when H.323/SIP follows phone dial-in. A third Zoom format — `~===~` delimited blocks with "You have been invited to a Zoom meeting" — is also handled.

## Conventions

- All view models and settings use `@Observable` (not `ObservableObject`) with `@MainActor`.
- Settings persist via `UserDefaults` with `didSet { save() }` on each property.
- Logging uses `os.Logger` with `privacy: .public`.
- No external dependencies — pure Swift/SwiftUI/AppKit.
- Test fixtures are real ICS files in `TestFixtures/`, loaded via `Bundle(for:).url(forResource:)`.
