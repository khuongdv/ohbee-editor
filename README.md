# Ohbee Editor

A local-first text workbench for macOS. Clean, fast, no cloud, no AI writing assistant, no telemetry.

> A text workbench — not a full IDE, not a note-taking app.

## Features

### Editing
- **Multi-tab** — up to 50 tabs open simultaneously, mix scratch notes and file-backed documents
- **Session restore** — scratch notes, dirty file-backed tabs, and large unsaved buffers restore locally
- **Open With / drag & drop** — open files from Finder, file panels, recent files, or by dropping files onto the editor
- **Smart indentation** — auto-indent respects language context
- **Find & Replace** — regex support, case-sensitive and whole-word toggles, visible match navigation
- **Large-file guardrails** — avoids expensive highlighting, line-number scans, and search on large inputs
- **Read-only files** — non-writable files open safely with a lock indicator

### Syntax Highlighting
Automatic detection from file extension, with manual override via the Language menu:

Plain Text · Markdown · JSON · YAML · HTML · XML · CSS · JavaScript · Swift · Python · Java · C · C++ · C# · Shell · SQL

Plain Text mode stays visually plain: no automatic URL linkification or browser-opening behavior.

### Text Tools
A dedicated **Text Tools** menu for common text operations — no copy-pasting into web tools:

| Operation | Description |
|---|---|
| Trim Whitespace | Strip leading and trailing whitespace from every line |
| Trim Trailing Spaces | Remove trailing spaces only, preserve indentation |
| Remove Empty Lines | Delete all blank lines |
| Remove Duplicate Lines | Keep first occurrence of each line |
| Sort Lines | Alphabetical sort A→Z or Z→A |
| Join Lines | Collapse multi-line text into a single line |
| lowercase / UPPERCASE / Title Case | Case conversions |
| snake_case / kebab-case / camelCase / PascalCase | Identifier case conversions |
| Clean AI Output | Strip code fences, compact blank lines, trim trailing whitespace |
| Duplicate / Move Line | Duplicate the current line or move it with native undo |

### JSON Tools
Format · Minify · Validate — available when the active document is JSON.

### XML Tools
Format · Minify — available when the active document is XML.

### URL Tools
Encode · Decode · Remove common tracking parameters while preserving unknown query parameters.

### Inspect Tools
- **Document info** — lines, words, characters, language, and file size
- **Word Frequency** — top words in the current text
- **Compare Tabs** — create a local annotated line diff between two open tabs
- **Hash** — SHA-256 and MD5 checksums for selected text or the full document
- **Image Viewer** — inspect local PNG, JPG, WEBP, BMP, and SVG files with zoom and metadata

### Safe Share
Before pasting content somewhere else, run a scan:

- **Review Safe Share** — shows a local review sheet with categorized findings and a masked preview
- **Copy Masked** — copies the redacted preview without changing the document
- **Apply Mask** — replaces sensitive values with `abcd***xyz` redactions in-place and remains undoable
- **Detect Sensitive Text** — quick status-only scan for likely bearer tokens, JWTs, emails, phone numbers, `.env` secrets, API keys

Safe Share is conservative and best-effort. It helps notice likely sensitive text; it does not guarantee complete secret detection.

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
| `⌘⇧J` | Format JSON |
| `⌘⇧M` | Minify JSON |
| `⌘⇧K` | Clean AI Output |
| `⌘⇧R` | Review Safe Share |
| `⌘⇧C` | Compare Tabs |
| `⌘⇧D` | Duplicate Line |
| `⌥↑` / `⌥↓` | Move Line Up / Down |
| `⌘+` / `⌘−` / `⌘0` | Increase / decrease / reset font size |

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
