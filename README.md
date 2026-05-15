# Ohbee Editor

A local-first text workbench for macOS. Clean, fast, no cloud, no AI writing assistant, no telemetry.

> A text workbench — not a full IDE, not a note-taking app.

## Features

### Editing
- **Multi-tab** — up to 50 tabs open simultaneously, mix scratch notes and file-backed documents
- **Session restore** — scratch notes survive restarts automatically
- **Drag & drop** — drop files onto the editor to open them as tabs
- **Smart indentation** — auto-indent respects language context
- **Find & Replace** — regex support, case-sensitive toggle, match navigation

### Syntax Highlighting
Automatic detection from file extension, with manual override via the Language menu:

Plain Text · Markdown · JSON · YAML · HTML · XML · CSS · JavaScript · Swift · Python · Java · C · C++ · C# · Shell · SQL

### Text Tools
A dedicated **Text Tools** menu for common text operations — no copy-pasting into web tools:

| Operation | Description |
|---|---|
| Trim Whitespace | Strip leading and trailing whitespace from every line |
| Trim Trailing Spaces | Remove trailing spaces only, preserve indentation |
| Remove Empty Lines | Delete all blank lines |
| Remove Duplicate Lines | Keep first occurrence of each line |
| Sort Lines | Alphabetical sort (locale-aware) |
| Join Lines | Collapse multi-line text into a single line |
| lowercase / UPPERCASE / Title Case | Case conversions |
| snake_case / kebab-case / camelCase | Identifier case conversions |
| Clean AI Output | Strip code fences, compact blank lines, trim trailing whitespace |

### JSON Tools
Format · Minify · Validate — available when the active document is JSON.

### Safe Share
Before pasting content somewhere else, run a scan:

- **Detect Sensitive Text** — flags bearer tokens, JWTs, emails, phone numbers, `.env` secrets, API keys
- **Mask Detected Patterns** — replaces sensitive values with `abcd***xyz` redactions in-place

## Requirements

- macOS 13 Ventura or later
- No external dependencies — built entirely with Swift Package Manager

## Build & Install

```bash
# Clone
git clone https://github.com/khuongdv/ohbee-editor.git
cd ohbee-editor

# Install to /Applications (recommended)
make install

# Or just build the bundle without installing
make bundle
```

### Makefile targets

| Command | Description |
|---|---|
| `make dev` | Run via `swift run` for development — no file type registration |
| `make bundle` | Build release `.app` bundle in the project directory |
| `make run` | Build release bundle and open it |
| `make install` | Deploy to `/Applications` and register file type associations |
| `make clean` | Remove build artifacts and unregister the local bundle |

## File Type Support

After installing, Ohbee Editor appears as an option in **Get Info → Open With** for:

`.txt` `.text` `.md` `.markdown` `.log` `.conf` `.cfg` `.ini` `.env` `.csv` `.tsv`
`.json` `.yaml` `.yml` `.html` `.htm` `.xml` `.css` `.js` `.ts` `.swift` `.py`
`.sh` `.bash` `.zsh` `.sql` `.java` `.cs` `.cpp` `.c` `.h` `.hpp`

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘N` | New scratch note |
| `⌘O` | Open file(s) |
| `⌘S` | Save |
| `⌘⇧S` | Save As |
| `⌘W` | Close tab |
| `⌘F` | Find |
| `⌘⌥F` | Find and Replace |
| `⌘⇧R` | Detect Sensitive Text |

## Project Structure

```
Sources/
  OhbeeEditorCore/   — Pure Swift library: document model, file I/O, transforms, search
  OhbeeEditor/       — SwiftUI + AppKit UI layer
  OhbeeEditorSelfTests/ — Executable self-tests (no XCTest dependency)
Support/
  Info.plist         — App bundle metadata and file type declarations
```

---

© 2025 Ohbee Labs · [ohbee.link](https://ohbee.link)
