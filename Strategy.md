# Strategy.md

## Purpose

This document is the implementation strategy for Ohbee Editor. Codex should read it after `AGENTS.md` and before making implementation changes.

The strategy is intentionally phase-based. Finish each phase with a small, reviewable result, then update `progress.md` with success logs, errors, blockers, and lessons learned.

## Product Frame

Ohbee Editor is a local-first macOS text workbench for temporary, messy, sensitive, or low-ceremony text.

Keep the product focused on:

- fast scratch editing
- safe local text handling
- practical text cleanup
- JSON/log/URL inspection
- safe sharing assistance

Do not drift toward:

- IDE behavior
- project/workspace ceremony
- cloud sync
- collaboration
- AI assistant behavior
- plugin marketplace behavior
- multi-file developer tooling

## Implementation Principles

- Build the editor spine before adding many tools.
- Keep transformation logic pure and testable.
- Route all text-changing tools through one shared operation path.
- Make scratch documents and file-backed documents explicit.
- Persist only local session state.
- Prefer native macOS behavior over custom UI.
- Keep every phase small enough to review.
- Record phase outcomes in `progress.md`.

## Phase 0: Repository Instructions and Planning

Goal: make the repo ready for consistent implementation.

Tasks:

- Clean `AGENTS.md` so it is a real repository instruction file.
- Remove copied-answer wrapper text, outer Markdown fences, and citation artifacts.
- Add missing implementation contracts:
  - document model
  - persistence contract
  - operation scope
  - undo policy
  - current-tab-only search scope
- Create this `Strategy.md`.
- Create `progress.md`.
- Log Phase 0 outcome in `progress.md`.

Exit criteria:

- `AGENTS.md` starts with `# AGENTS.md`.
- `AGENTS.md` has no outer code fence or content-reference artifact.
- `Strategy.md` exists and describes the implementation phases.
- `progress.md` exists and contains a Phase 0 entry.

## Phase 1: App Skeleton

Goal: open the app and edit text immediately.

Tasks:

- Scaffold the native macOS app structure.
- Prefer SwiftUI for app/window structure.
- Use a simple editor surface first.
- Create one default scratch tab on launch.
- Add a basic tab store.
- Add an initial `EditorDocument` model.
- Cap open tabs at 50 for MVP so accidental repeated tab creation cannot overwhelm the app.

Recommended model:

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

Notes:

- `SwiftUI.TextEditor` can be used for bootstrap if it keeps the phase small.
- Keep the design open to replacing it with an AppKit `NSTextView` wrapper when selection, undo, or performance need it.
- Do not add text tools yet.

Exit criteria:

- App launches.
- User can type or paste into a scratch tab.
- There is at least one visible tab/document.
- The document model is explicit.
- New scratch tab creation is bounded by the MVP tab cap.

## Phase 2: Local Session Persistence

Goal: scratch tabs survive app restart.

Tasks:

- Save session state to a versioned JSON file in Application Support.
- Restore scratch documents on launch.
- Persist selected document ID.
- Handle missing/corrupt session files gracefully.

Recommended session shape:

```json
{
  "version": 1,
  "selectedDocumentID": "uuid-string",
  "documents": []
}
```

Rules:

- Do not use a database in MVP.
- Do not sync the session file.
- Do not treat session persistence as explicit file save.

Exit criteria:

- Scratch tabs restore after restart.
- Corrupt persistence does not crash the app.
- Persistence code has focused tests where practical.

## Phase 3: File Open, Save, and Save As

Goal: support local files without destructive surprises.

Tasks:

- Open local text files through native macOS open panels.
- Save file-backed documents.
- Save scratch documents through Save As.
- Track dirty state.
- Warn before closing unsaved dirty documents where practical.

Rules:

- Opening a file reads into a buffer.
- Transforms change the buffer only.
- Existing files are written only when the user explicitly saves.

Exit criteria:

- Open local text file works.
- Save works for file-backed documents.
- Save As works for scratch documents.
- Dirty state is visible or internally reliable.

## Phase 4: Editor Operation Pipeline

Goal: create the shared path all text-changing tools use.

Tasks:

- Add a common `applyTransform` path.
- Add selected-text-or-full-document behavior.
- Update dirty state through the shared path.
- Register undo through the editor surface where practical.
- Return useful summaries from transformations.

Recommended result shape:

```swift
enum TextTransformResult {
    case success(text: String, summary: String)
    case failure(message: String)
}
```

Rules:

- Buttons and menu commands must not directly mutate document text with complex inline logic.
- Pure transform functions should not know about tabs, files, persistence, or UI.

Exit criteria:

- One simple transform can be applied through the pipeline.
- Selected text behavior is defined or explicitly deferred with a logged reason.
- Transform results can report success or failure.

## Phase 5: Core Text Tools

Goal: add practical cleanup tools on top of the pipeline.

Tasks:

- Add line operations:
  - trim whitespace
  - remove empty lines
  - remove duplicate lines
  - sort lines
  - join lines
- Add case conversion:
  - lowercase
  - uppercase
  - Title Case
  - snake_case
  - kebab-case
  - camelCase
- Add Clean AI Output recipe:
  - trim excessive blank lines
  - remove surrounding Markdown code fences
  - normalize line endings
  - trim trailing spaces

Testing:

- Empty input.
- Unicode input.
- Multi-line input.
- Trailing spaces.
- Repeated blank lines.
- Line ending behavior.

Exit criteria:

- Tools are pure functions.
- Tools are reachable from UI or command surface.
- Relevant tests pass.

## Phase 6: Current-Tab Search and Replace

Goal: add useful search without turning the app into an IDE.

Tasks:

- Search in current tab.
- Next and previous match.
- Replace one.
- Replace all.
- Regex mode.
- Case-sensitive toggle if it stays simple.

Rules:

- MVP search is current-tab only.
- Do not add project search or multi-file search unless explicitly requested.

Exit criteria:

- Search works in the active document.
- Replace and regex replace work predictably.
- Invalid regex reports a clear error.

## Phase 6 Follow-up: Tab Management and Language Metadata

Goal: make multi-tab editing feel practical without adding project ceremony.

Tab tasks:

- Add right-click context menu on each tab.
- Support common tab actions:
  - close this tab
  - close other tabs
  - close all tabs
  - close tabs to the right
- Support close-tab keyboard shortcuts.
- Warn before closing tabs with unsaved dirty content.
- Keep at least one note open after closing tabs.

Language tasks:

- Add a lightweight per-document language metadata field.
- Add View > Language menu with common language choices:
  - Plain Text
  - Java
  - JavaScript
  - JSON
  - HTML
  - XML
  - C#
  - C++
  - SQL
  - YAML
  - Markdown
  - Swift
  - Python
  - Shell
  - CSS

Rules:

- Language selection is metadata for the current tab and may drive simple local highlighting.
- Do not add language servers, autocomplete, code navigation, build systems, or project behavior.
- Closing tabs must not write to files implicitly.

Exit criteria:

- Context menu tab closing actions work.
- `Cmd+W` and `Ctrl+W` close the active tab.
- Dirty tabs show an unsaved-changes warning before close actions discard the tab.
- View > Language updates the selected document language.
- Tests cover core tab close behavior and language metadata.

## Phase 6 Follow-up: Simple Syntax Highlighting

Goal: make selected-language text easier for human eyes to scan without turning Ohbee Editor into an IDE.

Tasks:

- Replace the bootstrap `SwiftUI.TextEditor` with an AppKit `NSTextView` wrapper.
- Use the selected or inferred document language to apply lightweight local syntax coloring.
- Use small regex-based highlighting for common inspectable formats:
  - JSON
  - XML
  - HTML
  - YAML
  - SQL
  - JavaScript
  - Java
  - C#
  - C++
- Preserve plain text editing performance and native undo.
- Keep selected-text transform support and search highlighting on the same editor surface.

Rules:

- Highlighting is for readability only.
- No language servers.
- No autocomplete.
- No code navigation.
- No symbol index.
- No syntax-aware refactoring.
- No remote grammar loading.
- No internet access.
- Avoid parser dependencies unless explicitly requested.
- Highlighting must degrade safely to plain text for large files or unknown languages.

Exit criteria:

- Language highlighting works locally for at least JSON and one markup language.
- Plain Text mode stays visually quiet and fast.
- Search selection and selected-text transforms have a clear integration path through `NSTextView`.

## Phase 7: JSON and URL Tools

Goal: support common messy text inspection tasks.

JSON tasks:

- Format JSON.
- Minify JSON.
- Validate JSON.
- Report parse errors clearly.

URL tasks:

- URL encode.
- URL decode.
- Remove known tracking parameters only.

Known tracking parameters:

- `utm_source`
- `utm_medium`
- `utm_campaign`
- `utm_term`
- `utm_content`
- `fbclid`
- `gclid`
- `msclkid`

Exit criteria:

- JSON tools do not crash on invalid or empty input.
- URL tools preserve unknown query parameters.
- Tests cover valid and invalid cases.

## Phase 8: Safe Share

Goal: help users notice likely sensitive text without overclaiming security.

Tasks:

- Detect likely sensitive text:
  - API keys
  - bearer tokens
  - JWT-like strings
  - emails
  - phone numbers
  - `.env` style key-value secrets
  - URLs containing token-like parameters
- Show wording like: `Potential sensitive text found.`
- Allow masking detected items.

Rules:

- Be conservative.
- Prefer false negatives over noisy false positives when uncertain.
- Do not claim complete secret detection.
- Keep everything local.

Exit criteria:

- Detection returns categorized findings.
- Masking is undoable through the editor pipeline.
- False-positive tests exist for common normal text.

## Phase 9: UX Polish and macOS Integration

Goal: make the app feel fast, native, and pleasant without expanding scope.

Tasks:

- Add keyboard shortcuts.
- Add native menu commands.
- Improve compact tool surface.
- Add status summaries after transforms.
- Support dark mode.
- Support drag and drop text files where practical.
- Check launch performance.

Rules:

- The editor remains the main focus.
- Tool UI stays compact.
- Do not turn the first screen into a dashboard.

Exit criteria:

- Common actions are keyboard-accessible.
- The app feels native on macOS.
- UI remains uncluttered.

## Phase 10: Finder Open With Integration

Goal: make Ohbee Editor appear naturally in Finder's right-click `Open With` menu for text-like files.

Tasks:

- Package Ohbee Editor as a proper macOS `.app` bundle.
- Add document type declarations in the app bundle metadata for plain text and common local text formats.
- Include extensions such as `txt`, `log`, `json`, `jsonl`, `csv`, `tsv`, `xml`, `html`, `htm`, `md`, `markdown`, `yaml`, `yml`, `sql`, `css`, `js`, `swift`, `py`, `sh`, `java`, `cs`, `cpp`, `h`, and `data`.
- Support opening file URLs passed by Finder into new tabs without requiring a project/workspace.
- Avoid claiming default ownership of broad file types; Ohbee Editor should be available under `Open With`, not aggressively replace user defaults.
- Keep all file opening local and explicit.

Rules:

- Do not add a file explorer or project tree as part of Finder integration.
- Do not write to files just because Finder opened them.
- Do not add network permissions.

Exit criteria:

- After installing the app bundle, Finder shows Ohbee Editor in `Open With` for text-like files.
- Selecting Ohbee Editor from Finder opens the chosen file in a tab.
- File-backed tabs preserve the existing explicit-save behavior.

## Phase 11: Editor UX — Line Numbers and Document Info

Goal: add lightweight editor chrome that helps orientation without adding IDE features.

Tasks:

- Add a line number gutter using `NSRulerView` on the left side of the scroll view.
- Draw line numbers aligned to each logical line; handle wrapped lines correctly (only one number per logical line).
- Handle the empty-document case (show "1") and the extra line fragment case (cursor on empty last line after a newline).
- Add a toggle in View → Show Line Numbers, persisted via `@AppStorage("ohbee.lineNumbers")`.
- Add a small `(i)` button in the status bar that opens a popover with:
  - Lines, Words, Characters, Characters (no whitespace)
  - Language / syntax
  - File size (for file-backed documents)

Rules:

- No code folding, minimap, or IDE gutter widgets.
- Line numbers use muted system colors; compact fixed-width gutter.
- Info popover is read-only and dismisses on outside click.
- No external dependencies.

Exit criteria:

- Line numbers appear and update on edit, scroll, and resize.
- Toggle persists across restarts.
- Info popover shows correct counts and dismisses cleanly.

## Phase 12: Help and Menu Discoverability

Goal: make key features discoverable through the macOS Help menu and Edit menu without adding documentation weight.

Tasks:

- Replace the default macOS Help menu item with a native in-app help sheet.
- Show keyboard shortcuts, gestures, and quick tips in the help sheet.
- Add a Vertical Selection entry to the Edit menu that explains the Option+Drag gesture via a native alert.
- Fix the vertical selection alert icon (use `info.circle` SF Symbol instead of the default app/folder icon).

Rules:

- Help content is in-app only; no external URLs, no web fetch, no documentation site.
- The help sheet is read-only and dismisses cleanly.
- No new architecture; wire state the same way as `AboutOhbeeView`.
- Do not add inline help, tooltips beyond what macOS provides, or context-sensitive help.

Exit criteria:

- Help → Ohbee Editor Help opens the in-app help sheet.
- Sheet lists all keyboard shortcuts, gestures, and quick tips.
- Edit → Vertical Selection… shows a correct info-icon alert explaining the gesture.
- Build passes with no errors.

## Phase 13: Cursor Line Gutter Highlight and Recent Files

Goal: small focused UX improvements that make the editor feel more alive and reduce friction re-opening recent work.

Tasks:

- Highlight the line number in the gutter that corresponds to the current cursor position using the system accent color and medium weight.
- All other line numbers remain muted (quaternary label color).
- Track recently opened file-backed documents (up to 10) in `EditorStore`, persisted in `UserDefaults`.
- Add an `Open Recent` submenu under `File → Open…` listing recent file names with full-path tooltip.
- Include a `Clear Recent Files` item at the bottom when the list is non-empty.
- Show a disabled `No Recent Files` item when the list is empty.

Rules:

- Cursor line highlight only affects the gutter number, not the text background.
- Recent files list is file-backed documents only; scratch notes are not tracked.
- Dedup on open (most recent at top); cap at 10 entries.
- No iCloud, no external storage, no sync.

Exit criteria:

- Moving the cursor updates the highlighted line number immediately.
- Opening a file appears at the top of the recent list on next launch.
- Clear Recent Files wipes the list persistently.
- Build passes with no errors.

## Phase 14: Tab Bar UX Polish

Goal: make tab interactions feel native and informative without adding project complexity.

Tasks:

- Show full file path as tooltip on hover for file-backed tabs; show tab name only for scratch notes (`.help()` modifier).
- Add middle-truncation for long tab titles (`.truncationMode(.middle)`).
- Add close (X) button always visible on each tab; show filled dot instead of X when tab has unsaved changes.
- Support drag-to-reorder tabs via `onDrag` / `DropDelegate`; animate reordering in real time.
- Fix gutter cursor-line highlight: correct off-by-one for extra line fragment case; ensure `syncCursorLine()` runs after `makeFirstResponder` on tab switch.

Rules:

- Close button triggers the same unsaved-changes warning as Cmd+W.
- Drag reorder persists to session on drop.
- No tab pinning, locking, or grouping.

Exit criteria:

- Hovering a file-backed tab shows full path tooltip.
- Tab title truncates from the middle when the tab is narrow.
- X button is always visible; shows dot when dirty.
- Dragging a tab reorders it; order persists after restart.
- Gutter highlights the correct line number at cursor position, including the extra line fragment case.

## Phase 15: Editor Comfort, Checksum Tools, and Offline Trust

Goal: editing conveniences and hash inspection while preserving offline/no-browser-handoff behavior.

Tasks:

- Font size control:
  - Increase: Cmd+=, Decrease: Cmd+−, Reset: Cmd+0
  - Persist via `@AppStorage("ohbee.fontSize")`, range 10–36pt, default 13pt
  - Applied to `NSFont.monospacedSystemFont(ofSize:weight:)` in `HighlightedTextEditor`

- Duplicate current line: Cmd+Shift+D
  - Duplicate the logical line at cursor; wrapped in undo group

- Move line up: Option+Up
  - Swap current line with previous line; wrapped in undo group

- Move line down: Option+Down
  - Swap current line with next line; wrapped in undo group

- Offline trust correction:
  - Do not automatically linkify URLs in editor text
  - Do not open URLs from editor text via Cmd+Click
  - Keep Plain Text visually plain
  - Avoid browser handoffs unless the user explicitly requests a future feature that requires one

- SHA-256 and MD5 checksums:
  - Inspect selected text or full document (non-destructive)
  - Use `CryptoKit` (`SHA256`, `Insecure.MD5`)
  - Show hash in status bar via `inspectText`
  - Exposed via status bar Hash menu and Text Tools menu

- Bug fix: title header divider overlap
  - Add `Divider()` between the document title `HStack` and `HighlightedTextEditor`
  - in `ScratchEditorView`

Rules:

- No internet access.
- No browser handoffs from editor content.
- No external hashing library; use `CryptoKit` (macOS 10.15+).
- Checksum is inspect-only; does not mutate the document.
- Font size is global across tabs (one persisted setting).
- Line operations target the logical line at cursor (not wrapped visual line).

Exit criteria:

- Cmd+= / Cmd+− / Cmd+0 change and reset font size; persists across restarts.
- Cmd+Shift+D duplicates the current line with native undo.
- Option+Up/Down moves the current line with native undo.
- URLs are not automatically underlined or opened from editor text.
- SHA-256 and MD5 hash appears in the status bar (selected or full text).
- Title header is clearly separated from the editor surface.
- Build passes with no errors.

## Phase 16: Inspect Tools, Tab Diff, and Distribution Prep

Goal: deepen text inspection, add tab comparison, and prepare the app for distribution.

Items dropped or deferred:
- Base64 encode/decode — deferred (low demand vs. effort ratio).
- Epoch/timestamp conversion — deferred (niche, separate phase if needed).
- Sparkle / automatic update check — removed. Violates local-first, no-network principle.
- `Help > Check for Updates...` browser handoff — removed. The app should not include network-dependent update checks or general browser handoffs.
- Menu bar mode — deferred (changes app lifecycle; own phase).

### XML Tools

- Format XML: Foundation `XMLDocument` with `.nodePrettyPrint` option.
- Minify XML: `XMLDocument` without pretty-print.
- Report parse errors clearly; do not mutate document on failure.
- Gate in status bar and Text Tools menu to XML-language documents (same pattern as JSON gating).

### Word Frequency

- Inspect-only: split text on whitespace + punctuation, lowercase, discard ≤1-char tokens.
- Return top 20 words by frequency (ties broken alphabetically).
- Status bar: shows top-5 preview via Text Tools > Word Frequency.
- Status bar icon (chart.bar.xaxis): opens scrollable popover with full top-20 table.

### Tab Diff

- Compare two open tabs via LCS line diff.
- UI: `CompareTabsSheet` sheet with two Pickers (Base, Changed) and a Compare button.
- Output: annotated diff text in a new scratch tab (`--- Base / +++ Changed / common / + added / - removed`).
- Accessible from status bar (arrow.left.arrow.right icon) and Edit > Compare Tabs… (Cmd+Shift+C).
- Button/command disabled when fewer than two tabs are open.

### Distribution Prep

- `make icon`: generates `Support/AppIcon.icns` from `logo.png` via `sips` + `iconutil`. Run once; commit the .icns for faster bundles.
- `make codesign`: signs the `.app` bundle with hardened runtime using `DEVELOPER_ID` env var and `Support/Entitlements.plist`.
- `make notarize`: submits to Apple notarization via `xcrun notarytool` (requires `notarytool-profile` in Keychain) then staples the ticket.
- `Support/Entitlements.plist`: minimal empty-dict entitlements; no sandbox, no special capabilities.

Rules:
- No app sandbox in this phase; open panels provide file access without entitlements.
- Notarization scripts are scaffolding only; user supplies their Developer ID cert.
- No IDE behavior, no language servers, no cloud sync, no plugin architecture.

Exit criteria:
- Format XML and Minify XML work on valid XML; invalid XML reports error and does not mutate document.
- Word Frequency popover shows top-20 words; Text Tools menu shows top-5 preview in status bar.
- Compare Tabs opens a new scratch tab with annotated diff output.
- `make icon` generates `Support/AppIcon.icns` from `logo.png`.
- `make codesign` and `make notarize` Makefile targets exist with correct flags.
- `Support/Entitlements.plist` exists.
- No update-check or browser-opening menu item is added.
- Build passes with no errors. All 56 self tests pass.

## Phase 17: Not Used

Phase 17 was never planned or implemented. The number is kept unused so existing `progress.md`
entries and phase references stay stable.

## Phase 18: Safe Share Review and Clean Copy

Goal: make privacy review a complete local workflow before sharing text.

Tasks:

- Add a Safe Share review sheet opened by `Cmd+Shift+R` and Text Tools > Review Safe Share.
- Review selected text when there is a selection; otherwise review the full active document.
- Show cautious wording: `Potential sensitive text found.` when findings exist, and `No obvious sensitive patterns found.` when none exist.
- Show categorized counts for likely sensitive text types.
- Show a findings list with category and masked snippets.
- Show a masked preview of the selected/full text.
- Add `Copy Masked` so users can copy the redacted preview without mutating the document.
- Add `Apply Mask` so users can redact the active selection/full document through the shared editor operation path with native undo.
- Keep `Detect Sensitive Text` as a quick status-only scan.

Rules:

- Do not add network access, browser handoffs, telemetry, analytics, or cloud behavior.
- Do not overclaim detection quality; Safe Share remains best-effort and conservative.
- Copying masked text must not change the document.
- Applying the mask must be undoable where the editor surface supports undo.
- Keep the review UI compact and focused; no sharing integrations.

Exit criteria:

- `Cmd+Shift+R` opens the Safe Share review sheet.
- Review works for selected text and full-document fallback.
- Copy Masked writes the masked preview to the local pasteboard only.
- Apply Mask updates the editor through the shared operation path.
- Core review behavior has self-tests.
- Build and self-tests pass.

## Phase 19: Post-Release Trust Polish

Goal: tighten release confidence after `1.1.4` without expanding product scope.

Tasks:

- Add a repo-local release QA checklist for manual release passes.
- Polish Safe Share Copy Masked feedback so users understand it writes only to the local pasteboard and leaves the document unchanged.
- Add search/replace edge-case self-tests:
  - empty query behavior
  - invalid regex summary and replace failure
  - regex capture replacement
  - whole-word boundaries
  - case-sensitive matching

Rules:

- Do not add Markdown preview in this phase.
- Do not add network access, telemetry, analytics, accounts, cloud sync, or AI calls.
- Keep Safe Share wording conservative and best-effort.
- Keep changes scoped to trust, QA, and existing feature hardening.

Exit criteria:

- Release checklist exists in `docs/`.
- Copy Masked clearly communicates document-unchanged behavior.
- Search/replace edge-case tests pass.
- `progress.md` is updated with the Phase 19 outcome.

## Phase 20: Utility Spine and Security Hardening

Goal: record the work that shipped after `1.1.8` but was never written into this roadmap.

Delivered:

- Selection-aware transforms through the shared editor operation path.
- Command palette for common local actions.
- Log cleanup tools and a Wrap Text preference.
- ReDoS, TOCTOU, and session file-permission hardening.
- App Sandbox adoption for `make install`, with security-scoped bookmarks for persistent access.
- Debounced, generation-checked asynchronous search evaluation with cached ranges.
- Detection of tabs whose original file was deleted, plus an explicit reauthorization flow.
- A Report Issue action.

Rules clarified by this phase:

- Editor *content* still never triggers a browser handoff: URLs in text are not linkified and are
  not opened on click.
- A user-initiated support action (Report Issue) may hand off to the default mail client or
  browser. It sends no document text, runs no background request, and is never automatic. Update
  requests, telemetry, and any automatic network access remain out of scope.

## Phase 21: Audit Remediation

Goal: close the findings from the full documentation and source audit without expanding scope.

Tasks:

- Resolve the pre-sandbox session directory against the real account home so migration can run
  inside the sandbox container.
- Add the app-scoped bookmark entitlement and stop swallowing bookmark failures.
- Quarantine an unreadable session manifest, keep local note text, and warn the user.
- Offer Save All when closing several dirty tabs.
- Redact Safe Share findings without keeping any prefix, suffix, or length.
- Keep the phone-number detector off timestamps, IP addresses, versions, IDs, and dates.
- Preserve terminal line endings in every line transform, including CRLF text.
- Narrow the regex guard to nested quantifiers and backreferences only.
- Share one implementation of file and tab-close commands between the menu bar and the window.
- Bring `CHANGELOG.md`, `README.md`, `.gitignore`, and this roadmap back in line with the code.

Rules:

- No new features, no network access, no scope growth.
- Every fix that can be expressed as a pure-function or store-level behavior gets a self-test.

Exit criteria:

- `swift build` and the full self-test suite pass.
- Each finding has either a regression test or a documented reason why it cannot be tested
  without a signed, sandboxed GUI build.

## Phase Update Protocol

After each phase, update `progress.md` with:

- date
- phase
- status: `success`, `partial`, `blocked`, or `error`
- changed files
- success log
- error or blocker log
- tests run
- lessons learned
- next recommended phase

Keep entries short but useful. The file is both a progress tracker and a small knowledge base for future Codex sessions.

## Recommended First Real Coding Slice

After Phase 0, the first implementation slice should be:

1. Scaffold the macOS app.
2. Add `EditorDocument`.
3. Add a tab/session store.
4. Show one editable scratch tab.
5. Persist and restore scratch tabs.
6. Add minimal tests for model/persistence if practical.

This creates the app's core loop before spending time on tools.
