# ICSNote

<p align="center">
  <img src="ICSNote/Resources/AppIcon.svg" width="128" height="128" alt="ICSNote app icon">
</p>

A native macOS app that converts ICS calendar files into Obsidian-compatible markdown notes. Drag an appointment from Outlook for Mac (or any `.ics` file from Finder) and get a clean, queryable meeting note in your vault -- ready for note-taking.

## Features

- **Drag-and-drop** from Outlook for Mac or Finder
- **"Open with"** file association for `.ics` files
- **File > Open** menu support
- **YAML frontmatter** (Dataview-queryable): title, date, time, organizer, attendees with acceptance status, location, categories, status, type
- **Metadata table** in the note body (similar to OneNote meeting notes)
- **Attendee list with status indicators**: ✅ accepted, ❌ declined, ❓ tentative, ➖ no response
- **Zoom and Microsoft Teams boilerplate stripping** -- removes SafeLinks, H.323/SIP blocks, dial-in numbers, and join links
- **Title text replacements** -- configurable find/replace rules (e.g., "1:1" to "One on One", strip "Fwd:", "RE:")
- **Configurable output** -- pick your Obsidian vault and subfolder
- **Notes template** -- default sections for Action Items, Decisions, and Follow-ups
- **Recurring meeting support** -- detects RRULE series and prompts with a date picker (defaults to today) so you always get the correct occurrence date
- **Recent conversions list** with Open in Obsidian and Reveal in Finder buttons
- **Success sound** on conversion (toggleable)
- **Duplicate file avoidance** -- appends a numeric suffix when a file already exists
- **Temp file cleanup** -- no appointment data left on disk after processing

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

## Settings

The Settings window has four tabs:

| Tab | What it controls |
|-----|-----------------|
| **Vault** | Obsidian vault path and subfolder for output files |
| **Stripping** | Toggle Zoom and Microsoft Teams boilerplate removal; toggle success sound |
| **Replacements** | Editable find/replace rules applied to meeting titles |
| **Notes** | Markdown template appended under the Notes heading |

## Tech

- Pure SwiftUI -- no external dependencies
- XcodeGen for project generation (`project.yml`)
- Swift 5.9, macOS 14+
- `@Observable` / `@MainActor` architecture
- Security-scoped resource handling for sandboxed file access

## Building from Source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# Generate the Xcode project
xcodegen generate

# Build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme ICSNote -destination 'platform=macOS' build
```

## License

All rights reserved.
