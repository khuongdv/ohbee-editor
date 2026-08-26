# AGENTS.md

## Project: Ohbee Editor

Ohbee Editor is a lightweight, local-first text workbench for macOS.

It is NOT a full IDE.
It is NOT a VS Code clone.
It is NOT a collaborative editor.
It is NOT an AI writing assistant.

The product goal is to provide a fast, practical editor for temporary text, messy text cleanup, JSON/log inspection, and safe sharing.

Core positioning:

> The editor you open when the text is messy, temporary, sensitive, or not worth creating a project for.

## Product Principles

### 1. Local-first by default

Ohbee Editor must work fully offline.

Do not introduce:

- cloud sync
- account/login
- telemetry
- analytics
- remote config
- online AI calls
- background upload
- internet-dependent features

If a feature requires network access, do not implement it unless explicitly requested.

### 2. Lightweight over powerful

Prefer simple, fast, understandable features over large frameworks and heavy abstractions.

Avoid turning the app into:

- a full IDE
- a project management tool
- a Markdown publishing tool
- a plugin marketplace
- a Git client
- a terminal app

### 3. Text workbench, not code editor

Ohbee Editor may support syntax highlighting and developer-friendly utilities, but its main job is quick text manipulation.

Prioritize:

- scratch tabs
- search and replace
- regex replace
- line operations
- JSON formatting/minifying/validation
- URL encode/decode
- tracking parameter removal
- safe-to-share text cleanup
- temporary notes that survive app restart

Deprioritize:

- language servers
- autocomplete
- debugger integration
- Git integration
- build systems
- terminal integration
- extension marketplace

### 4. No project ceremony

The user should be able to open the app, paste text, clean it, and copy/share/save it quickly.

Do not require users to create a workspace, project, account, or folder before editing text.

### 5. Originals are respected

When editing existing files:

- avoid destructive changes unless the user explicitly saves
- support unsaved tabs
- preserve user text exactly unless a specific transform is applied
- make transformations predictable and reversible where possible

### 6. Privacy as a product feature

Ohbee Editor should help users safely handle sensitive text.

Potential privacy/safety tools:

- detect suspicious secrets
- mask selected sensitive patterns
- remove tracking parameters from URLs
- clean copied text before sharing
- warn before saving or sharing obvious secrets

Do not send text outside the device.

## Target User

The primary user is a practical Mac user who often deals with messy text:

- developers
- solo builders
- product/ops people
- support engineers
- content writers
- people who frequently copy/paste logs, JSON, URLs, snippets, emails, or AI output

The app should feel like a fast utility, not a heavyweight professional suite.

## Initial MVP Scope

Implement only the smallest useful version first.

### MVP Features

- Multi-tab plain text editor
- Unsaved scratch tabs
- Restore unsaved tabs after restart
- Open and save local text files
- Search
- Replace
- Regex replace
- Basic line operations:
  - trim whitespace
  - remove empty lines
  - remove duplicate lines
  - sort lines
  - join lines
- Case conversion:
  - lowercase
  - uppercase
  - Title Case
  - snake_case
  - kebab-case
  - camelCase
- JSON tools:
  - format JSON
  - minify JSON
  - validate JSON
- URL tools:
  - URL encode
  - URL decode
  - remove common tracking parameters
- Clean AI output recipe:
  - trim excessive blank lines
  - remove surrounding Markdown code fences
  - normalize line endings
  - trim trailing spaces
- Safe to share helper:
  - detect likely API keys, tokens, emails, phone numbers, and JWT-like strings
  - allow masking detected patterns

### Not MVP

Do not implement these unless explicitly requested:

- plugin system
- Git integration
- terminal
- LSP/autocomplete
- cloud sync
- collaboration
- Markdown preview
- WYSIWYG editing
- AI assistant
- database storage
- full settings system
- theme marketplace
- complex file explorer
- remote file editing
- syntax-aware refactoring
- multi-file search
- project tree
- package/runtime integration

## Implementation Phases

Follow `Strategy.md` as the implementation roadmap.

Update `progress.md` after every phase with:

- phase name
- date
- status
- success log
- error or blocker log
- useful lessons for future work

## Document Model

Use a simple document model from the beginning. Keep file-backed documents and scratch documents explicit.

Recommended fields:

```swift
struct EditorDocument: Identifiable, Codable {
    let id: UUID
    var title: String
    var text: String
    var fileURL: URL?
    var isScratch: Bool
    var isDirty: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

Rules:

- `fileURL == nil` means the document is not currently backed by a saved file.
- `isScratch == true` means the document should be restored as app session state.
- `isDirty == true` means the buffer has changes not written to its backing file or persistence target.
- Do not write to an existing file unless the user explicitly saves.

## Persistence Contract

Persist unsaved scratch tabs locally so the app can restore them after restart.

Use a versioned JSON file in Application Support. Do not use a database for MVP. Do not sync this file. Do not send it over the network.

Recommended session shape:

```json
{
  "version": 1,
  "selectedDocumentID": "uuid-string",
  "documents": []
}
```

Persistence is app session state, not a replacement for explicit file save.

## Operation Scope

### Text Transforms

Every transform must go through a shared editor operation path.

Behavior:

- operate on selected text if selection exists
- otherwise operate on the full document
- update dirty state
- register undo where the editor surface supports it
- return a small summary when practical
- never mutate text directly inside a button action

### Search and Replace

MVP search and replace is current-tab only.

Do not implement multi-file search unless explicitly requested.

### Undo

Destructive or text-changing actions must be undoable where practical. Prefer one shared `applyTransform` path so undo behavior is consistent across tools.

## UX Guidelines

### Main UI

Prefer a simple layout:

- editor area as the main focus
- tabs for open documents
- compact command/search controls
- optional side/bottom panel for text tools
- no cluttered toolbar

Suggested sections:

- Scratch
- Files
- Recipes
- Text Tools
- JSON
- Cleanup
- Safe Share

### Important UX Behaviors

- App should launch quickly.
- Creating a new scratch tab should be instant.
- Open tabs should be capped to avoid accidental runaway tab creation; MVP cap is 50 tabs.
- User should be able to paste text immediately.
- Transform actions should operate on selected text if selection exists; otherwise operate on the full document.
- Every transform should clearly show what changed when practical.
- Destructive actions should be undoable.
- Keyboard shortcuts should be first-class.

### Suggested Shortcuts

Use macOS conventions where possible.

- `Cmd+N`: new scratch tab
- `Cmd+O`: open file
- `Cmd+S`: save
- `Cmd+Shift+S`: save as
- `Cmd+F`: find
- `Cmd+Option+F`: replace
- `Cmd+Shift+J`: format JSON
- `Cmd+Shift+M`: minify JSON
- `Cmd+Shift+L`: line tools
- `Cmd+Shift+K`: clean text
- `Cmd+Shift+R`: safe-share / redact patterns

If a shortcut conflicts with macOS conventions or existing app shortcuts, prefer native macOS behavior.

## Architecture Guidelines

Prefer a clean, simple architecture.

Suggested layers:

- `App`
  - app entry point
  - window setup
  - high-level app state
- `Editor`
  - text editor view
  - tab model
  - document state
  - file open/save integration
- `TextTools`
  - pure functions for transformations
  - line operations
  - case conversion
  - cleanup recipes
- `JSONTools`
  - JSON format/minify/validate
- `URLTools`
  - URL encode/decode
  - tracking parameter removal
- `SafeShare`
  - sensitive pattern detection
  - masking/redaction utilities
- `Persistence`
  - local restoration of scratch tabs
  - recent files if needed
- `Tests`
  - unit tests for all text transformations

Keep transformation logic as pure functions wherever possible.

Bad:

```swift
Button("Format JSON") {
    editor.text = someComplexInlineMutation(editor.text)
}
```

Good:

```swift
let result = JSONFormatter.format(editor.selectedOrFullText)
editor.apply(result)
```

## Implementation Rules

### General

- Prefer small files with clear responsibility.
- Avoid premature abstractions.
- Avoid large global state.
- Avoid hidden side effects.
- Do not introduce dependencies unless the benefit is clear.
- Do not add internet permissions or networking libraries.
- Do not add analytics.
- Do not add crash reporting unless explicitly requested.

### Text Transformations

Text transformation functions must be:

- deterministic
- unit-tested
- safe for empty input
- safe for large input where practical
- Unicode-aware where possible
- explicit about whether they preserve line endings

When a transform can fail, return a structured result instead of silently changing text.

Example:

```swift
enum TextTransformResult {
    case success(text: String, summary: String)
    case failure(message: String)
}
```

### JSON Tools

JSON format/minify/validate should:

- preserve valid JSON content semantically
- report parse errors clearly
- not crash on invalid input
- handle empty input gracefully

### URL Tools

Tracking parameter removal should target common parameters such as:

- `utm_source`
- `utm_medium`
- `utm_campaign`
- `utm_term`
- `utm_content`
- `fbclid`
- `gclid`
- `msclkid`

Do not remove unknown query parameters unless explicitly requested.

### Safe Share Detection

Sensitive-pattern detection should be conservative.

Detect likely:

- API keys
- bearer tokens
- JWT-like strings
- emails
- phone numbers
- `.env` style key-value secrets
- URLs containing token-like parameters

Do not overclaim security.
This feature helps users notice sensitive text; it does not guarantee complete secret detection.

Use wording like:

> Potential sensitive text found.

Avoid wording like:

> All secrets detected.

## macOS Guidelines

If this is implemented as a native macOS app:

- Prefer SwiftUI for app structure.
- Use AppKit/NSTextView where SwiftUI text editing is insufficient.
- Respect macOS keyboard shortcuts.
- Support standard open/save panels.
- Support drag and drop text files where practical.
- Support dark mode.
- Avoid custom controls when native controls work well.
- Keep the app feeling fast and native.

## Testing Guidelines

Add unit tests for text transformation logic.

Minimum test coverage should include:

- empty input
- normal input
- Unicode input
- multi-line input
- trailing spaces
- repeated blank lines
- invalid JSON
- valid JSON
- URLs with and without tracking parameters
- selected-text transform behavior where applicable
- safe-share detection false-positive cases

Before completing a task, run the relevant tests.

If tests cannot be run, explain why and provide the exact command that should be run manually.

## Quality Bar

Before finishing any implementation task, check:

- Does the feature support the core product promise?
- Does it keep the app local-first?
- Does it avoid unnecessary complexity?
- Is the transformation logic tested?
- Does it preserve user data safely?
- Does it avoid turning the product into an IDE?
- Is the UI still fast and uncluttered?

## Coding Style

- Use clear names over clever names.
- Keep functions small.
- Prefer explicit state transitions.
- Prefer pure functions for text tools.
- Avoid magic constants; name them.
- Avoid large view files.
- Avoid deeply nested conditionals.
- Add comments only when they explain why, not what.

## Documentation

When adding a new text tool, document:

- what it does
- whether it affects selected text or the whole document
- whether it is reversible through undo
- known limitations

For complex behavior, add a short note in `/docs` if the project has a docs folder.

## Task Behavior for Codex

When working on this repository:

1. Read this AGENTS.md first.
2. Read `Strategy.md` before implementation planning.
3. Inspect the existing project structure before editing.
4. Prefer small, reviewable patches.
5. Do not introduce broad rewrites unless requested.
6. Do not add heavy dependencies without explaining why.
7. Keep the app offline/local-first.
8. Add or update tests for transformation logic.
9. Run relevant tests before final response.
10. Update `progress.md` after each completed phase or meaningful blocker.
11. In the final response, summarize:
    - what changed
    - what tests were run
    - any known limitations
    - any follow-up suggestions

## Product North Star

Ohbee Editor should feel like:

> Notepad++ spirit, Mac-native taste, Ohbee privacy discipline.

Fast.
Local.
Practical.
No account.
No cloud.
No nonsense.
