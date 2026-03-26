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
- **RRULE expansion**: when a single VEVENT has a past DTSTART and an RRULE, the parser advances to the next upcoming occurrence. This is critical because Outlook puts the series definition (first occurrence date) on the pasteboard, not the specific occurrence the user dragged.
- **Text replacements** are applied to titles before filename sanitization, so "1:1" becomes "One on One" before the colon would be stripped.

### Zoom/Teams Stripping

Outlook wraps URLs in `nam11.safelinks.protection.outlook.com` SafeLinks. Zoom blocks can end with either "International numbers" (phone dial-in) or `@zoomcrc.com` (H.323/SIP). The stripper tries multiple start-pattern × end-pattern combinations and returns on first match.

## Conventions

- All view models and settings use `@Observable` (not `ObservableObject`) with `@MainActor`.
- Settings persist via `UserDefaults` with `didSet { save() }` on each property.
- Logging uses `os.Logger` with `privacy: .public`.
- No external dependencies — pure Swift/SwiftUI/AppKit.
- Test fixtures are real ICS files in `TestFixtures/`, loaded via `Bundle(for:).url(forResource:)`.
