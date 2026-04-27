# ICSNote

<p align="center">
  <img src="ICSNote/Resources/AppIcon.svg" width="128" height="128" alt="ICSNote app icon">
</p>

A native macOS app that converts ICS calendar files and EML email messages into Obsidian-compatible markdown notes. Drag an appointment or email from Outlook for Mac (or any `.ics`/`.eml` file from Finder), and get a clean, queryable note routed into the right vault — ready for note-taking, searching with Dataview, and automated follow-up via Claude Code skills.

## Features

### Meetings (ICS)

- **Drag-and-drop** from Outlook for Mac or Finder
- **"Open with"** file association for `.ics` files
- **YAML frontmatter** (Dataview-queryable): title, date, time, organizer, attendees with acceptance status, location, categories, status, type
- **Metadata table** in the note body (similar to OneNote meeting notes)
- **Attendee list with status indicators**: ✅ accepted, ❌ declined, ❓ tentative, ➖ no response
- **Zoom and Microsoft Teams boilerplate stripping** — removes SafeLinks, H.323/SIP blocks, dial-in numbers, join links, and the various underscore-delimited external-org footer formats
- **Recurring meeting support** — detects RRULE series and prompts with a date picker (defaults to today) so you always get the correct occurrence date

### Emails (EML)

- **Drag-and-drop** `.eml` files from Outlook or Finder
- **Full MIME parsing** — multipart traversal, quoted-printable and base64 decoding, Windows-1252 charset support
- **Attachment extraction** — real attachments (xlsx, pdf, etc.) saved to the vault and linked with `[[wiki-links]]`. Existing PDFs are embedded inline with `![[...]]`. Inline signature images are skipped.
- **Automatic PDF conversion** (optional) — convert `.doc`, `.docx`, `.rtf`, `.html`, `.txt` attachments to PDF alongside the original. Modes: Never / Always / Ask-per-drop.
- **Thread merging** — dropping a reply (RE:/FW:/Fwd:) appends to the existing note with the same subject, collapsing previous messages into Obsidian callout blocks
- **Configurable email subfolder and notes template**

### Multi-vault

- **Auto-discovers vaults** from Obsidian's own registry (`~/Library/Application Support/obsidian/obsidian.json`) — no manual path typing
- **Per-vault configuration**: separate meeting, email, and attachment subfolders for each vault
- **Three drop zone layouts** — pick what suits your workflow:
  - **Grid** — one drop zone per vault (best for 1–3 vaults, max 6)
  - **Dropdown** — single zone with a vault picker (scales to any count)
  - **Segmented** — single zone with a tab-style vault selector (2–5 vaults)
- **Visual vault indicators** — each vault gets a stable color + shape combination (12 colors × 8 shapes: circle, square, triangle, diamond, hexagon, pentagon, star, rhombus). Deterministic from the vault path so the same vault always looks the same.
- **Per-conversion vault badges** in the Recent list so you always know where a note landed

### Post-save hooks (Claude Code skills)

Fire a Claude Code skill automatically after a note is saved — summarize the meeting, generate a briefing, sync to downstream systems, enrich the note with context from other tools.

- **Skill picker** populated from discovered skills (user-level `~/.claude/skills/`, plugin cache, per-vault `.claude/skills/`, plus user-configured custom directories scanned recursively)
- **13+ template variables** for dynamic prompts: `{{file_path}}`, `{{title}}`, `{{organizer}}`, `{{from}}`, `{{skill_path}}`, `{{skill_content}}`, and more
- **Three prompt template styles** from the "Insert default" menu:
  1. Reference skill by path
  2. Inline skill content directly (most reliable — no file reads needed)
  3. Invoke by skill name (standard Claude locations only)
- **Per-hook configuration**: trigger (meeting / email / any), vault filter (any / specific), timeout, permission mode (accept edits / bypass / plan / default), and optional `--allowedTools` list for granular MCP tool access
- **Hook Activity window** — dedicated window showing every run with status (running / success / failure / skipped), duration, and expandable tabs for the full prompt, stdout, and stderr (selectable, copy-able)
- **Toolbar failure indicator** — bolt icon badges red when recent runs have failed, so problems are visible without opening the activity window

### Shared

- **Title text replacements** — configurable find/replace rules (e.g., "1:1" → "One on One", strip "Fwd:", "RE:")
- **Notes templates** — customizable markdown appended under `## Notes` — one template for meetings, one for emails
- **Recent conversions list** with Open in Obsidian and Reveal in Finder buttons, and static clock-time timestamps
- **Success sound** on conversion (toggleable)
- **Duplicate file avoidance** — appends a numeric suffix when a file already exists
- **Temp file cleanup** — no data left on disk after processing

## Output Example

A dropped meeting produces a file named `2026-03-26 Weekly Team Standup.md`:

```markdown
---
title: "Weekly Team Standup"
date: 2026-03-26
time: "9:00 AM - 9:30 AM (CDT)"
organizer: "Jane Smith"
attendees:
  - name: "Alice Johnson"
    status: accepted
  - name: "Bob Williams"
    status: tentative
  - name: "Carol Davis"
    status: needs-action
location: "Conference Room B"
categories:
  - "Team"
status: "Confirmed"
type: meeting
---

## Meeting Details

| Field | Value |
|-------|-------|
| **Subject** | Weekly Team Standup |
| **Organizer** | Jane Smith (jane.smith@example.com) |
| **Date** | Wednesday, March 26, 2026 |
| **Time** | 9:00 AM - 9:30 AM (CDT) |
| **Location** | Conference Room B |
| **Status** | Confirmed |
| **Categories** | Team |

## Attendees

- ✅ Alice Johnson (alice@example.com)
- ❓ Bob Williams (bob@example.com)
- ➖ Carol Davis (carol@example.com)

## Description

Review sprint progress and blockers.

## Notes

### Action Items

-

### Decisions

-

### Follow-ups

-
```

## Email Output Example

A dropped email with attachments produces a file with the body, followed by embedded PDFs (and wiki-links to original files):

```markdown
---
title: "Quarterly Review"
date: 2026-04-17
time: "8:36 AM (CDT)"
from: "Alice Example"
to:
  - "Team"
subject: "Quarterly Review"
attachments:
  - "Quarterly Review Agenda.doc"
  - "Quarterly Review Agenda.pdf"
  - "Supporting Materials.pdf"
type: email
---

## Email Details

| Field | Value |
|-------|-------|
| **From** | Alice Example (alice@example.com) |
| **To** | Team |
| **Date** | Friday, April 17, 2026 |
| **Subject** | Quarterly Review |

## Body

Please find the attached agenda and supporting materials...

## Attachments

- [[Quarterly Review Agenda.doc]]
- ![[Quarterly Review Agenda.pdf]]
- ![[Supporting Materials.pdf]]

## Notes
```

When a reply is dropped (e.g., "RE: Quarterly Review"), the existing note is updated — the new message replaces `## Body` and the previous message moves into a collapsed callout:

```markdown
## Previous Messages

> [!quote]- Alice Example — 2026-04-17 8:36 AM (CDT)
> Please find the attached agenda and supporting materials...
```

## Settings

The Settings window has six tabs:

| Tab | What it controls |
|-----|-----------------|
| **Vaults** | Auto-discovered Obsidian vaults with per-vault enable toggle, meeting/email/attachment subfolders, and drop zone layout picker |
| **Stripping** | Toggle Zoom and Microsoft Teams boilerplate removal; toggle success sound |
| **Replacements** | Editable find/replace rules applied to meeting and email titles |
| **Notes** | Markdown template appended under the Notes heading for meetings |
| **Email** | Attachment extraction, PDF conversion mode (Never/Always/Ask), thread merging, and email notes template |
| **Hooks** | Post-save hook editor with skill picker, prompt template, permission mode, timeout, and allowed tools per hook |

## Tech

- Pure SwiftUI — no external dependencies
- XcodeGen for project generation (`project.yml`)
- Swift 5.9, macOS 14+
- `@Observable` / `@MainActor` architecture
- Security-scoped resource handling for sandboxed file access
- PDF conversion via `NSAttributedString` + `NSPrintOperation` (pure AppKit, no Office apps or external binaries required)

## Building from Source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# Generate the Xcode project
xcodegen generate

# Build (debug)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme ICSNote -destination 'platform=macOS' build

# Run tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme ICSNoteTests -destination 'platform=macOS'

# Release build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme ICSNote -configuration Release -destination 'platform=macOS' -derivedDataPath ./build build
```

## Hooks — Requirements

The hook system shells out to the `claude` CLI. For hooks to run:

- Install Claude Code and ensure `claude` is in your PATH, or at one of:
  - `/opt/homebrew/bin/claude`
  - `/usr/local/bin/claude`
  - `~/.local/bin/claude`
- For skills not in standard Claude locations, add the parent directory under **Settings → Hooks → Custom skill directories** (scanned recursively)

If the CLI isn't detected, the Hooks tab shows a warning and hooks are silently skipped — nothing else breaks.

## License

[PolyForm Noncommercial License 1.0.0](LICENSE)
