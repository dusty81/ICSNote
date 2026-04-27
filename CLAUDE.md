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

Four parallel pipelines from a dropped file to an Obsidian-ready note (and optional downstream action):

1. **ICS text → `CalendarEvent` → Markdown → file in target vault**
2. **EML text → `EmailMessage` → Markdown → file in target vault (+ attachments + optional PDF conversions)**
3. **Recurring event → date picker dialog → `CalendarEvent.withDate` → pipeline 1**
4. **Any saved note → `HookRunner` → `claude -p` spawned with skill prompt**

**Models** — `CalendarEvent` (meetings), `EmailMessage`/`EmailContact`/`EmailAttachment` (emails), `VaultConfig` + `DropZoneLayout` (multi-vault), `PostSaveHook` + `HookRun` (hook system). `EmailMessage.stripReplyPrefix()` handles RE:/FW:/Fwd: stripping for thread matching. `VaultConfig.color` and `VaultConfig.indicatorShape` are derived deterministically from the vault path via FNV-1a.

**Services layer** — stateless enums with static methods, no dependencies between each other except via explicit arguments. Key services:
- `ICSParser`, `EMLParser` — pure parsers
- `MarkdownGenerator` — parallel generators for meetings and emails, plus `updateNoteWithNewMessage()` for thread merging
- `PDFConverter` — convert `.doc/.docx/.rtf/.html/.txt` to PDF via `NSAttributedString` + `NSPrintOperation`
- `ObsidianVaultDiscovery` — parses Obsidian's own `~/Library/Application Support/obsidian/obsidian.json`
- `ClaudeSkillDiscovery` — scans standard and user-configured skill directories for `SKILL.md` frontmatter
- `HookContext` — variable substitution for hook prompt templates
- `HookRunner` — spawns `claude -p` with `--permission-mode` and `--allowedTools`, captures stdout/stderr, fires start/finish callbacks to the caller

**ViewModel layer** — `AppViewModel` is `@Observable @MainActor`, owns `AppSettings`, coordinates drop → parse → generate → write → hook-fire → UI state. All note-writing methods thread a `vaultID` (or active vault default) through to the per-vault directories. Maintains `recentConversions` and `hookRuns` arrays for UI.

**View layer**:
- `MainView` — three drop zone layouts (grid / dropdown / segmented) gated by `settings.effectiveDropZoneLayout`; window size scales with layout and vault count
- `VaultDropCell` — per-cell NSView with its own drag state so grid cells highlight independently (resolves ambiguity about which vault is the target mid-drag)
- `SettingsView` — 6 tabs: Vaults, Stripping, Replacements, Notes, Email, Hooks
- `HookActivityView` — dedicated window (not popover) for hook run history with expandable prompt/stdout/stderr tabs
- `DropTargetView` → `VaultDropTargetView` — AppKit bridge for drag-and-drop (SwiftUI's `onDrop` doesn't reliably handle file promises on repeated drops)

### Drop Handling (the tricky part)

`VaultDropTargetView` is an `NSViewRepresentable` wrapping `ICSDropNSView` — an AppKit NSView, not SwiftUI's `onDrop`. SwiftUI's `onDrop` doesn't reliably handle Outlook's `NSFilePromiseReceiver` on repeated drops.

In the grid layout, **each cell hosts its own NSView** and the callbacks close over the target vault ID. Option B (dropdown) and Option C (segmented) use a single NSView; the active vault is read from `AppSettings.activeVaultID` at drop time.

The drop handler in `performDragOperation` uses four strategies in priority order:
1. **Quick ICS check** — reads only 3 known calendar pasteboard types (`com.apple.ical.ics`, `public.calendar-event`, `com.microsoft.outlook16.icalendar`). Does NOT scan all types — that's slow and interferes with Outlook's file promise setup. EML detection is NOT done inline because Outlook metadata types contain "From:" and "Subject:" without being valid EML.
2. **File URLs** — `NSURL` pasteboard objects for Finder drops of `.ics` and `.eml` files.
3. **File promises** — `NSFilePromiseReceiver` on a background `OperationQueue` with a unique temp directory per drop. Uses polling with increasing back-off (up to 6 attempts over ~6s) to wait for Outlook's async file write, then `NSFileCoordinator` for coordinated read. Routes both `.ics` and `.eml` files. Temp dirs are cleaned up immediately after reading.
4. **Full pasteboard fallback** — last resort scan of all types for ICS content only.

### Multi-vault Specifics

- `VaultConfig` is `Codable` and persisted as JSON in `UserDefaults["vaults"]`. Migration from v1.1 single-vault settings happens in `AppSettings.init` if `UserDefaults["vaults"]` is missing but `UserDefaults["vaultPath"]` is present.
- `ObsidianVaultDiscovery.discover()` filters out vaults whose paths no longer exist on disk.
- `DropZoneLayout.maxEnabledVaults` caps each layout (grid: 6, segmented: 5, dropdown: unlimited). `AppSettings.effectiveDropZoneLayout` auto-falls-back to `.dropdown` when enabled vault count exceeds the chosen layout's cap.
- Vault color/shape derive from `VaultConfig.stableHash(path)` using different bits for each (shape uses `hash / paletteCount`) so they're independent.
- `VaultIndicator` is the single SwiftUI view used anywhere the color+shape combo is rendered. Change it to update all call sites.
- `AppViewModel.openInObsidian` derives the subfolder from the output path (strips the vault path prefix) so it correctly handles meetings, emails, and custom subfolders with a single implementation.

### ICS Parsing Specifics

- **Line unfolding** must happen first (RFC 5545: continuation lines start with space/tab).
- **Recurring event handling**: when a VEVENT has an RRULE or RECURRENCE-ID, the parser sets `isRecurring: true` on the `CalendarEvent`. The ViewModel then shows a date picker dialog (defaulting to today) so the user can confirm or change the occurrence date. This is critical because Outlook puts the series definition (first occurrence date) on the pasteboard, not the specific occurrence the user dragged. Outlook often includes both the series-definition VEVENT (with RRULE) and modified-occurrence VEVENTs (with RECURRENCE-ID but no RRULE); `selectNextOccurrence` picks the most recent, so RECURRENCE-ID must also trigger the recurring flow. The `CalendarEvent.withDate(_:)` method shifts the event to the chosen date while preserving the original time-of-day and duration.
- **Text replacements** are applied to titles before filename sanitization, so "1:1" becomes "One on One" before the colon would be stripped.

### Zoom/Teams Stripping

Outlook wraps URLs in `nam11.safelinks.protection.outlook.com` SafeLinks. Zoom blocks can end with "International numbers" (phone dial-in) or `@zoomcrc.com` (H.323/SIP). The stripper tries multiple start-pattern × end-pattern combinations and returns on first match. End patterns are ordered so the **furthest** endpoint (`@zoomcrc.com`) is tried before closer ones (`International numbers`), ensuring the full block is consumed when H.323/SIP follows phone dial-in. A third Zoom format — `~===~` delimited blocks with "You have been invited to a Zoom meeting" — is also handled.

Teams stripping covers several formats:
- Standard internal Teams (`Join Microsoft Teams Meeting` … `Learn more about Teams`)
- External-org underscore-delimited blocks (`_{40,}\s+Microsoft Teams meeting.*?_{40,}`) — `\s+` (not `\n`) so blank lines between the delimiter and header are handled
- Fallback end markers: `Reset PIN`, `Reset dial-in PIN`, `Meeting options`, `Learn More`
- Outer `_{40,}` skips the inner `_{32,}` separator that some templates use within the block

### EML Parsing Specifics

- **Header parsing** splits at the first blank line, unfolds continuation lines (starting with whitespace).
- **MIME multipart traversal** recursively walks `multipart/mixed` > `multipart/related` > `multipart/alternative` to find `text/plain` body and attachment parts.
- **Quoted-printable decoding** handles `=XX` hex bytes, `=\n` soft line breaks, and Windows-1252 charset.
- **Attachment extraction** — `Content-Disposition: attachment` wins over Content-ID presence. Outlook puts Content-IDs on every MIME part including real attachments, so `Content-ID` alone is NOT enough to classify a part as inline. A part is inline only if `Content-Disposition: inline` is explicit, or if no disposition is set AND there's a Content-ID (typical for embedded signature images).
- **PDF embedding**: attachments ending in `.pdf` are linked with `![[filename]]` (Obsidian embed syntax) instead of `[[filename]]` so they render inline in preview.
- **PDF conversion** (optional, per-vault setting): `PDFConverter` uses `NSAttributedString(url:options:)` to load `.doc/.docx/.rtf/.rtfd/.html/.htm/.txt/.webarchive` into a text view, then `NSPrintOperation` with `jobDisposition = .save` and `jobSavingURL` to render a PDF. Must run on `@MainActor`. Returns false for unsupported formats (`.xlsx`, `.pptx`, images). Modes: `never` / `always` / `ask` (prompts once per drop).
- **Thread merging**: `EmailMessage.stripReplyPrefix()` strips RE:/FW:/Fwd: prefixes (case-insensitive, handles multiples). `AppViewModel.findExistingEmailNote(subject:in:)` scans the target vault's email output folder for a file whose name contains the cleaned subject. `MarkdownGenerator.updateNoteWithNewMessage()` moves the current ## Body into a collapsed `> [!quote]-` callout under ## Previous Messages and inserts the new body. Frontmatter date/from fields are updated to reflect the newest message.

### Hook System

`AppViewModel.writeAndRecord` (meetings) and `AppViewModel.finalizeEmail` (emails) both call `fireHooks(context:)` after a successful save. This spawns any `PostSaveHook` whose `matches(vaultID:noteType:)` returns true, on detached Tasks so nothing blocks the drop handler.

- **Skill discovery**: `ClaudeSkillDiscovery.discover(projectPath:customPaths:)` scans `~/.claude/skills/`, `~/.claude/plugins/cache/` (recursive — plugin versioned subdirs are walked), the target vault's `.claude/skills/`, and every directory in `AppSettings.customSkillPaths` (also recursive). Results are deduplicated by `"<source>:<name>"`.
- **Variable substitution**: `HookContext.substitute(in:)` handles 13 context-derived tokens. `HookRunner.runClaudeSkill` runs a second pass for `{{skill_name}}`, `{{skill_path}}`, `{{skill_content}}` because those depend on skill lookup, which the context doesn't own.
- **Process invocation**: `claude -p "<prompt>" --permission-mode <mode> [--allowedTools "<list>"]`, with `currentDirectoryURL` set to the target vault path so project-level skills are discovered. `claude` binary is autodetected in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`; if none exist, the run is marked `.skipped`.
- **Output capture**: both stdout and stderr are captured regardless of exit code, capped at 100KB per stream. The prompt (after substitution) is stored on the `HookRun` too so users can inspect exactly what was sent. Exit 143 (SIGTERM from our timeout) is replaced with a friendlier message.
- **Callbacks**: `HookRunner.fire` accepts `@Sendable @MainActor` `onStart` and `onFinish` callbacks. `AppViewModel.fireHooks` uses these to update `hookRuns` so the Activity window reflects state live.
- **Permission modes** — `acceptEdits` (default for new hooks): auto-approves file edits, bash still prompts (will block on tool use). `bypassPermissions`: skips all prompts (needed for MCP tool calls). `plan`: read-only. `default`: will fail unattended. Map directly to Claude's `--permission-mode` CLI flag via `ClaudePermissionMode.cliValue`.
- **Allowed tools** — optional free-form string mapped to `--allowedTools`. Wildcard patterns like `mcp__outlook__*` are supported by Claude.

## Conventions

- All view models and settings use `@Observable` (not `ObservableObject`) with `@MainActor`.
- Settings persist via `UserDefaults` with `didSet { save() }` on each property. Complex types (vaults, hooks, textReplacements) serialize as JSON via `JSONEncoder`.
- Logging uses `os.Logger` with `privacy: .public`.
- No external dependencies — pure Swift/SwiftUI/AppKit.
- Test fixtures are real ICS and EML files in `TestFixtures/`, loaded via `Bundle(for:).url(forResource:)`.
- Hook and vault runs are fire-and-forget on `Task.detached`. UI feedback goes through main-actor callbacks, not shared mutable state.
