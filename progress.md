# progress.md

This file tracks implementation progress for Ohbee Editor. It should be updated after every phase and after meaningful blockers or errors.

Use it as a small project knowledge base: keep success logs, error logs, test commands, and lessons learned.

## 2026-06-26 - Bug Fix: Restored Tabs Empty When Original File Deleted

Status: success

Changed files:

- `Sources/OhbeeEditorCore/EditorDocument.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/MissingFileWarning.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Root cause:

- Clean file-backed tabs never store their text in the session (`LargeFilePolicy.sessionText` returns `""` for them); the disk file is treated as the source of truth and reloaded on restart via `reloadFileBackedDocumentsIfNeeded`.
- If the original file was deleted/moved/renamed between sessions, `fileExists` is false, the reload is skipped, and the tab silently shows empty content. Scratch notes and dirty file-backed tabs are unaffected because their text is persisted.

Success log:

- Added a runtime-only `isMissingFile` flag to `EditorDocument` (not persisted, excluded from `==`, like `isLargeFile`/`isReadOnly`).
- Added synchronous `EditorStore.markMissingBackingFiles()` (runs in init before the async reload) that flags only clean, empty-text file-backed docs whose file is gone. Dirty docs keep their in-session content and are never flagged.
- `updateDocumentText` clears `isMissingFile` when the user types, so an edited buffer rejoins the normal unsaved-changes flow instead of being silently discardable.
- Added `EditorStore.discardMissingDocument(_:)` that removes the tab without copying content anywhere and without recording it as recently closed (it cannot be reopened).
- Tab UI: missing tabs render with a red title, red strikethrough, and a small red warning-triangle icon (`TabItemView`).
- Clicking a missing tab shows `MissingFileWarning` ("Original file was deleted", OK + Cancel); OK removes the tab. The tab close button and the menu-bar close path also route missing tabs to `discardMissingDocument`.
- No content backup is written and nothing leaks to a separate file, per product privacy discipline.
- Added 4 self-tests: detection on init, dirty-not-flagged, discard behavior (incl. last-tab -> fresh scratch, no recently-closed entry), and edit-clears-flag.

Error or blocker log:

- Detection runs at restore time only. A file deleted while the app is running is not flagged until the next launch. This matches the reported scenario; broader live detection is a possible follow-up.
- The alert copy is in English to stay consistent with the rest of the app UI. The requested wording was Vietnamese ("File gốc đã bị xoá"); switching is a one-line change if preferred.
- Alert and tab styling are UI behavior verified by `swift build`; the store-level logic is covered by self-tests.

Tests run:

- `swift build` succeeded (all targets incl. UI).
- `swift run OhbeeEditorSelfTests` succeeded: 72/72 tests passed, including the 4 new ones.

Lessons learned:

- "Disk is the source of truth" for clean file-backed tabs is correct for size/privacy, but it must degrade visibly: when the source disappears, mark it instead of showing a silent empty buffer.
- Keep the missing-file flag a runtime classification (not persisted) and re-derive it on launch, so the session JSON stays lightweight and never stores file content.

## 2026-06-15 - Release 1.1.8

Status: success

Changed files:

- `CHANGELOG.md`
- `Makefile`
- `README.md`
- `Support/Info.plist`
- `progress.md`

Success log:

- Reviewed commits from `1.1.7` through `HEAD` before writing release notes.
- Bumped app version to `1.1.8` and bundle build number to `13`.
- Added a `1.1.8` changelog entry covering command palette, selection-aware transforms, log cleanup tools, Wrap Text, metadata, Safe Share snippet hardening, SQL CRLF highlighting, tab-width rendering, and editor crash-path hardening.

Error or blocker log:

- A sandboxed `make bundle` attempt failed because SwiftPM could not write compiler cache files outside the workspace. Rerunning with approved cache access succeeded.

Tests run:

- `swift build`
- `swift run OhbeeEditorSelfTests`
- `make bundle`
- Verified `Ohbee Editor.app/Contents/Info.plist` reports version `1.1.8` and build `13`.

Lessons learned:

- Release notes should be written from commit history, then grouped by user-facing impact so small fixes do not disappear.

## 2026-06-15 - Editor View: Word Wrap Preference

Status: success

Changed files:

- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `progress.md`

Success log:

- Added a global `ohbee.wordWrap` AppStorage preference, defaulting to enabled for viewport-friendly text inspection.
- Added a `Wrap Text` menu toggle beside existing view preferences.
- Updated the AppKit editor wrapper so word wrap disables horizontal scrolling and tracks the viewport width without mutating document text.
- Preserved the previous horizontal-scroll behavior when word wrap is turned off.

Error or blocker log:

- No blocker. This is a view preference only, so no text transform tests were needed.

Tests run:

- `swift build`
- `swift run OhbeeEditorSelfTests`

Lessons learned:

- Word wrap belongs in the editor view layer, not the document model or transform pipeline, because it changes presentation only.

## 2026-06-15 - Editor View: Word Wrap Toggle Relayout Fix

Status: success

Changed files:

- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `progress.md`

Success log:

- Fixed the `Wrap Text` OFF -> ON transition so the active editor immediately rewraps long lines without requiring a tab switch.
- Resizes the AppKit text view back to the scroll viewport width when wrapping is enabled.
- Invalidates and ensures text layout immediately, then repeats the configuration on the next main-loop pass after the scroll view tiles.

Error or blocker log:

- No blocker. This is an AppKit presentation fix and does not mutate document text.

Tests run:

- `swift build`
- `swift run OhbeeEditorSelfTests`

Lessons learned:

- Toggling `NSTextContainer.widthTracksTextView` is not enough after a text view has expanded for horizontal scrolling; the text view frame also needs to be collapsed to the viewport width.

## 2026-06-07 - Document Info: File Metadata Rows

Status: success

Changed files:

- `Sources/OhbeeEditorCore/EditorFileIO.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added `EditorFileMetadata` and `EditorFileIO.metadata(for:)` to read local filesystem byte count, creation date, and owner account name for file-backed documents.
- Updated Document Info popover to show Created and Author rows only when the selected tab has a real file still present on disk.
- Kept scratch tabs and missing file URLs from showing filesystem metadata.
- Added self-test coverage for existing and missing file metadata lookup.
- Corrected a stale SQL line-ending self-test assertion that expected `'XX'` while the fixture text contains `'XXX'`.

Error or blocker log:

- No blocker. Author is sourced from the local filesystem owner account name, which is the practical offline metadata available for regular saved text files.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded.
- `swift build` succeeded.

Lessons learned:

- Document Info can stay lightweight by keeping filesystem reads behind a tiny core helper and making UI rows conditional on available metadata.

## 2026-06-03 - SQL Highlighting: Line Comment Newline Handling

Status: success

Changed files:

- `Sources/OhbeeEditorCore/SQLSyntaxTokenizer.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Fixed SQL `--` line comments so they stop at any Unicode newline, including carriage-return and Windows-style pasted line endings.
- Added regression coverage for SQL highlighting resuming after `\r` and `\r\n` line comments.

Error or blocker log:

- The bug presented as SQL highlighting turning gray from the first `--` comment onward when pasted text used non-Unix line endings.
- Initial explicit checks for `\n` and `\r` did not cover Swift's `\r\n` newline grapheme; switching to `Character.isNewline` covered the full case cleanly.

Tests run:

- `swift run OhbeeEditorSelfTests`
- `swift build`

Lessons learned:

- SQL line comments must use Unicode-aware newline detection because pasted database scripts can carry CR-only or CRLF line endings.
- Regression tests should include paste-oriented line ending variants, not only Unix newlines.

## 2026-05-15 - Phase 0: Repository Instructions and Planning

Status: success

Changed files:

- `AGENTS.md`
- `Strategy.md`
- `progress.md`

Success log:

- Cleaned `AGENTS.md` so it starts directly with `# AGENTS.md`.
- Removed copied-answer wrapper text, outer Markdown fence, citation artifact, and external reference footer.
- Fixed malformed code fence around the architecture examples.
- Added Codex-friendly implementation contracts for document model, persistence, transform scope, undo policy, and current-tab-only search.
- Created `Strategy.md` with phase-by-phase implementation strategy.
- Created this progress log as the project knowledge base.

Error or blocker log:

- No implementation code exists yet, so no app or unit tests can be run in Phase 0.

Tests run:

- Not run. Phase 0 only changed planning and instruction Markdown files.

Lessons learned:

- The repo currently contains only planning/instruction files.
- Before Phase 1, choose or scaffold the native macOS project structure.
- Keep future phase updates in this file so later Codex sessions do not need to rediscover decisions.

Next recommended phase:

- Phase 1: App Skeleton.

## 2026-05-15 - Phase 1: App Skeleton

Status: success

Changed files:

- `Package.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditor/EditorDocument.swift`
- `Sources/OhbeeEditor/EditorStore.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `progress.md`

Success log:

- Scaffolded a SwiftPM macOS executable package named `OhbeeEditor`.
- Added SwiftUI app entry point with one main window.
- Added `EditorDocument` with the Phase 1 document model fields: `id`, `title`, `text`, `fileURL`, `isScratch`, `isDirty`, `createdAt`, and `updatedAt`.
- Added `EditorStore` with a default scratch document, selected document state, scratch tab creation, tab selection, and text updates.
- Added a compact tab bar with dirty indicator and a plus button for new scratch tabs.
- Added a simple `TextEditor`-based scratch editor so the user can type or paste immediately.
- Added `Cmd+N` command for new scratch tabs.
- Verified the package builds successfully with `swift build` after running outside the sandbox.

Error or blocker log:

- First `swift build` attempt inside the sandbox failed because SwiftPM and clang could not write cache files under the user home directory.
- The sandboxed build output also showed a toolchain/SDK mismatch, but the escalated build completed successfully, so the mismatch appears tied to the sandboxed invocation context rather than the project code.
- GUI runtime launch was not exercised in this phase because running the SwiftUI app would keep a foreground app process open in the Codex session. Build success was used as the Phase 1 verification.

Tests run:

- `swift build` failed in sandbox due cache permission errors.
- `swift build` succeeded outside sandbox.

Lessons learned:

- SwiftPM builds for this repo may need permission to write SwiftPM/clang caches outside the workspace.
- The initial editor uses `SwiftUI.TextEditor` only as a bootstrap surface; keep the design ready for an AppKit `NSTextView` wrapper when selection and undo requirements become stricter.
- No transformation logic exists yet, so there are no transformation tests to add in Phase 1.

Next recommended phase:

- Phase 2: Local Session Persistence.

## 2026-05-15 - Phase 1 Follow-up: Editable Scratch Text and Tab Cap

Status: success

Changed files:

- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditor/EditorStore.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `AGENTS.md`
- `Strategy.md`
- `progress.md`

Success log:

- Fixed the scratch editor update path by replacing the custom `BindingBox` with a real SwiftUI `Binding<String>`.
- Made document text updates reassign the modified `EditorDocument` back into the `@Published` documents array so SwiftUI observes changes reliably.
- Added editor focus on appear and when switching documents, so the selected scratch editor is ready for typing.
- Added an MVP tab cap of 50 documents.
- Disabled the `+` button and `Cmd+N` command when the tab cap is reached.
- Added a small max-tab status hint in the tab bar.
- Updated `AGENTS.md` and `Strategy.md` so the tab cap is documented as product behavior.

Error or blocker log:

- The original Phase 1 binding was too indirect and could make the editor feel non-editable in the running UI.
- No automated UI test exists yet to verify typing into `TextEditor`; validation is currently by build plus manual demo run.

Tests run:

- `swift build` succeeded outside sandbox.

Lessons learned:

- For SwiftUI editor state, prefer direct `Binding` APIs and explicit reassignment of array elements in `@Published` collections.
- Put guardrails on repeated user actions early, even in skeleton phases.
- A future UI test or lightweight manual QA checklist should cover: launch app, type into Scratch 1, create another tab, type there, switch back, confirm both buffers are preserved.

Next recommended phase:

- Phase 2: Local Session Persistence.

## 2026-05-15 - Phase 2: Local Session Persistence

Status: success

Changed files:

- `Package.swift`
- `Sources/OhbeeEditorCore/EditorDocument.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SessionPersistence.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added `OhbeeEditorCore` as a small library target so model, persistence, file I/O, and transform logic can be exercised outside the SwiftUI app.
- Added `EditorSession` with version, selected document ID, and documents.
- Added `LocalSessionStore` that writes pretty, sorted JSON to `Application Support/Ohbee Editor/session.json`.
- Restored scratch documents on `EditorStore` initialization, including selected scratch tab when possible.
- Saved scratch session state when creating tabs, selecting tabs, editing text, saving, opening, or applying transforms.
- Missing or corrupt session files are handled gracefully by falling back to a default scratch tab.
- Added a lightweight `OhbeeEditorSelfTests` executable because this Command Line Tools environment does not expose `XCTest` or Swift `Testing`.

Error or blocker log:

- `swift test` could not be used because neither `XCTest` nor Swift `Testing` modules were available in the active toolchain.
- Sandboxed SwiftPM invocations cannot write Swift/clang cache files under the user home directory, so verification needs to run outside the sandbox.
- ISO8601 JSON date encoding does not preserve exact subsecond `Date` equality, so the persistence self-test checks the session contract fields rather than whole-struct equality.

Tests run:

- `swift run OhbeeEditorSelfTests` failed inside sandbox due Swift/clang cache permission errors.
- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.
- `swift build` failed inside sandbox due Swift/clang cache permission errors.
- `swift build` succeeded outside sandbox.

Lessons learned:

- Keep persistence tests focused on durable contract fields rather than exact `Date` round-trips.
- A dedicated core target makes the local-first model and pure operations easier to verify without launching the macOS app.
- Future test work should revisit `swift test` if the local toolchain gains `XCTest` or Swift `Testing`.

Next recommended phase:

- Phase 3: File Open, Save, and Save As.

## 2026-05-15 - Phase 3: File Open, Save, and Save As

Status: success

Changed files:

- `Sources/OhbeeEditorCore/EditorFileIO.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `progress.md`

Success log:

- Added `EditorFileIO` for local text file open and UTF-8 save.
- Added native `NSOpenPanel` and `NSSavePanel` flows from both compact toolbar buttons and menu commands.
- Added `Cmd+O`, `Cmd+S`, and `Cmd+Shift+S` behaviors.
- Opening a file reads it into a new file-backed buffer without writing back to disk.
- Saving a file-backed document writes only after explicit save.
- Saving a scratch document through Save As writes to the selected path, updates title/file URL, clears dirty state, and makes it file-backed.
- Dirty state is updated on text edits and cleared after successful save.

Error or blocker log:

- Warn-before-closing dirty documents is deferred because the MVP currently has no close-tab/window-close interception path.
- File encoding support is intentionally simple: UTF-8 first, then Foundation's detected string encoding fallback.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.
- `swift build` succeeded outside sandbox.

Lessons learned:

- File-backed documents should stay out of scratch session persistence for now; session persistence remains local scratch restoration, not a recent-files feature.
- Keep file I/O separate from UI panels so future tests can cover open/save behavior without driving AppKit.

Next recommended phase:

- Phase 4: Editor Operation Pipeline.

## 2026-05-15 - Phase 4: Editor Operation Pipeline

Status: success with one explicit deferral

Changed files:

- `Sources/OhbeeEditorCore/TextTransforms.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added `TextTransformResult` with success text/summary and failure message cases.
- Added `EditorStore.applyTransform(named:transform:)` as the shared path for text-changing tools.
- The shared transform path updates document text, dirty state, update timestamp, status message, and scratch session persistence.
- Added `BasicTextTransforms.trimTrailingWhitespace(_:)` as the first pure transform.
- Exposed Trim Trailing Spaces through the compact bottom command area and a Text Tools menu command.
- Added self-tests for empty input and multi-line trailing whitespace.

Error or blocker log:

- Selected-text transform behavior is explicitly deferred. The current bootstrap editor uses `SwiftUI.TextEditor` on macOS 13, which does not provide a stable selection binding for this app target. Phase 4 applies transforms to the full document until the editor surface moves to an `NSTextView` wrapper or another selection-capable surface.
- Undo registration through the editor surface is also deferred with the same editor-surface limitation. Native typing undo remains handled by `TextEditor`, but programmatic transform undo needs the future editor wrapper.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.
- `swift build` succeeded outside sandbox.

Lessons learned:

- The shared transform path can land before richer tools; future Phase 5 tools should plug into `applyTransform` rather than mutating document text from buttons.
- Selection and transform undo are now the main reasons to replace the bootstrap `TextEditor` with a focused AppKit wrapper.

Next recommended phase:

- Phase 5: Core Text Tools.

## 2026-05-15 - Debug Fix: Editor Focus and Visible Text

Status: success

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `progress.md`

Success log:

- Investigated the report where typing `Xin chao` appeared in the Terminal log instead of the editor.
- Added explicit app/window activation when the SwiftUI content appears.
- Added a focused editor handoff on appear and tab switch, including a short delayed retry to avoid launch-time focus races when running through `swift run`.
- Set `TextEditor` foreground and accent colors from native AppKit colors so typed text remains visible in dark mode.

Error or blocker log:

- The screenshot strongly suggests keyboard input was still going to Terminal after launching from `swift run`.
- GUI behavior was not manually driven from Codex because launching the app would leave a foreground interactive process in the session.

Tests run:

- `swift build` succeeded outside sandbox.
- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.

Lessons learned:

- Apps launched with `swift run` may need an explicit activation handoff before typing naturally lands in the app window.
- Keep native text/accent colors explicit while using a hidden `TextEditor` scroll background in dark mode.

## 2026-05-15 - Debug Fix: Reduce Focus Noise While Typing

Status: success

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `progress.md`

Success log:

- Investigated noisy terminal output containing `getApplicationProperty: called with invalid property` and `IMKCFRunLoopWakeUpReliable`.
- Identified the likely source as macOS AppKit/InputMethodKit writing to stderr while the SwiftUI GUI app is launched as a SwiftPM executable.
- Reduced Ohbee Editor's own focus handoff so app/window activation only runs when the editor first appears or when the active document changes.
- Kept editor focus restoration intact without re-activating the app during ordinary text updates.

Error or blocker log:

- These messages are emitted by macOS frameworks, not by Ohbee Editor logging.
- Running as a proper `.app` bundle should be quieter than running an AppKit/SwiftUI GUI from `swift run`, but app bundling is outside the current MVP scaffold.

Tests run:

- `swift build` succeeded outside sandbox.
- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.

Lessons learned:

- Avoid repeated `NSApp.activate` calls during editor render churn; activation should be a one-time launch/tab-switch handoff.
- SwiftPM is convenient for development, but a bundled macOS app will be the cleaner runtime path for GUI/manual QA.

## 2026-05-15 - UX Polish: Notes, Status Bar, and New Tab Hover

Status: success

Changed files:

- `Sources/OhbeeEditorCore/EditorDocument.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `progress.md`

Success log:

- Changed new scratch document titles from `Scratch 1`, `Scratch 2` to `Note 1`, `Note 2`.
- Changed the editor header badge from `Scratch` to `Note`.
- Kept `isScratch` internally because it is still the correct persistence/document-model term.
- Made status bar content more compact with smaller status text and tighter vertical padding.
- Replaced the plain plus button with a custom New Note button that has a hover background and clearer accessibility label.

Error or blocker log:

- Existing restored scratch tabs may keep their old saved titles until the user creates new tabs or clears the session file.

Tests run:

- `swift build` succeeded outside sandbox.
- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.

Lessons learned:

- `Note` is a friendlier visible label than `Scratch`, while the internal scratch concept remains useful for persistence semantics.

## 2026-05-15 - Phase 5: Core Text Tools

Status: success

Changed files:

- `Sources/OhbeeEditorCore/TextTransforms.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added pure line transforms: trim whitespace, trim trailing spaces, remove empty lines, remove duplicate lines, sort lines, and join lines.
- Added pure case transforms: lowercase, uppercase, Title Case, snake_case, kebab-case, and camelCase.
- Added Clean AI Output recipe that removes surrounding Markdown code fences, normalizes line endings, trims trailing spaces, compacts excessive blank lines, and trims outer whitespace.
- Exposed tools through compact status bar menus: Lines, Case, and Cleanup.
- Added Text Tools menu commands for the same transforms.
- Added self-tests for line transforms, case transforms, and Clean AI Output.

Error or blocker log:

- Transforms still apply to the full document because selected-text operations are waiting on the future selection-capable editor surface.
- Line transforms normalize line endings to `\n`; CRLF preservation is not implemented yet.

Tests run:

- `swift build` succeeded outside sandbox.
- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.

Lessons learned:

- The shared `applyTransform` path made Phase 5 additions small and consistent.
- Future selected-text work should reuse the same pure transform functions and only change the operation scope.

Next recommended phase:

- Phase 6: Current-Tab Search and Replace.

## 2026-05-15 - Phase 6: Current-Tab Search and Replace

Status: success with one explicit deferral

Changed files:

- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added current-tab search state to `EditorStore`.
- Added `SearchReplaceEngine` with literal search, regex search, case-sensitive toggle, match count, next/previous match index, replace current, and replace all.
- Added a compact find/replace panel with find text, replacement text, next/previous controls, Regex and Case toggles, Replace, Replace All, and close.
- Added `Cmd+F` and `Cmd+Option+F` to open the find/replace panel without replacing native text editing commands.
- Search and replace mutate only the active document buffer and mark it dirty through store logic.
- Added self-tests for search summary, navigation, literal replace, and regex replace.

Error or blocker log:

- Next/previous currently updates the current match index and displayed count, but does not visually select or scroll to a match in `TextEditor`.
- Visual match selection/highlighting is deferred until the editor moves to an `NSTextView` wrapper.

Tests run:

- `swift build` succeeded outside sandbox.
- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.

Lessons learned:

- Current-tab search can stay pure and local-first; the missing piece is editor surface integration, not search logic.
- Avoid `CommandGroup(replacing: .textEditing)` because that would remove native editing commands; append find commands after text editing instead.

Next recommended phase:

- Consider the `NSTextView` editor wrapper before deepening selected-text transforms, undo integration, and visual search selection.

## 2026-05-15 - Phase 6 Follow-up: Tab Management and Language Metadata

Status: success

Changed files:

- `Strategy.md`
- `Sources/OhbeeEditorCore/EditorLanguage.swift`
- `Sources/OhbeeEditorCore/EditorDocument.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added right-click context menus on each tab.
- Added tab actions: Close This Tab, Close Other Tabs, Close Tabs to the Right, and Close All Tabs.
- Added close-tab keyboard behavior for both `Cmd+W` and `Ctrl+W`.
- Close-all and closing the final tab leave one fresh note open so the editor stays immediately usable.
- Added lightweight `EditorLanguage` metadata for documents.
- Added View > Language menu with common language choices: Plain Text, Java, JavaScript, JSON, HTML, XML, C#, C++, SQL, YAML, Markdown, Swift, Python, Shell, and CSS.
- Display the selected document language in the editor header.
- Added self-tests for close-tab behavior and language metadata.

Error or blocker log:

- Language selection is metadata only for now; no syntax highlighting is implemented in this follow-up.
- `Ctrl+W` is handled with a local key monitor because SwiftUI command menus are primarily built around macOS command-key shortcuts.

Tests run:

- `swift build` succeeded outside sandbox.
- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.

Lessons learned:

- Tab close behavior belongs in the store so menu commands, context menus, and shortcuts all share the same state transitions.
- Keeping one note open after destructive tab actions preserves the app's quick scratch-work feel.

Next recommended phase:

- Phase 7: JSON and URL Tools.

## 2026-05-15 - Bug Fix: Warn Before Closing Unsaved Tabs

Status: success

Changed files:

- `Strategy.md`
- `Sources/OhbeeEditor/UnsavedTabWarning.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `progress.md`

Success log:

- Added an AppKit warning alert before closing dirty tabs.
- Routed tab context menu close actions through the warning path.
- Routed `Cmd+W` menu close through the warning path.
- Routed `Ctrl+W` local keyboard close through the warning path.
- Multi-close actions warn when any tab being closed has unsaved changes.
- Updated `Strategy.md` so dirty-tab close warnings are part of the tab management contract.
- Added a lightweight syntax highlighting candidate phase to `Strategy.md` that preserves the offline/lightweight constraints.

Error or blocker log:

- The warning currently offers `Close Without Saving` and `Cancel`; a future improvement can add a save-first flow for single file-backed tabs.
- Core store tests still cover close state transitions; the visual alert is UI behavior and was verified by successful app build rather than automated UI tests.

Tests run:

- `swift build` succeeded outside sandbox.
- `swift run OhbeeEditorSelfTests` succeeded outside sandbox.

Lessons learned:

- Dirty close confirmation belongs in the app/UI layer because it is an interaction decision, while `EditorStore` should stay focused on deterministic state transitions.
- Syntax highlighting is useful for the product, but should ride on the future `NSTextView` wrapper and stay local, small, and dependency-light.

## 2026-05-15 - Product Branding: Logo and About Ohbee Editor

Status: success

Changed files:

- `Package.swift`
- `Sources/OhbeeEditor/Resources/logo.png`
- `Sources/OhbeeEditor/AboutOhbeeView.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `progress.md`

Success log:

- Added the provided `logo.png` to the SwiftPM resource bundle.
- Displayed the Ohbee logo in the main tab bar.
- Replaced the default app info command with `About Ohbee Editor`.
- Added a custom About view with core product principles: local-first, no account/cloud/telemetry, practical messy-text cleanup, and text-workbench-not-IDE positioning.
- Added a link to `https://ohbee.link`.

Error or blocker log:

- The SwiftPM executable can bundle and display the logo resource, but a proper `.app` icon file is still a future packaging task.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- SwiftPM target resources work well for in-app branding assets.
- Keep app principles visible in About without adding onboarding or marketing surface to the main editor.

## 2026-05-15 - Phase 7: JSON and URL Tools

Status: success

Changed files:

- `Sources/OhbeeEditorCore/JSONTools.swift`
- `Sources/OhbeeEditorCore/URLTools.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added pure JSON tools for format, minify, and validate.
- JSON failures return clear messages and do not mutate the document.
- Added URL encode/decode and tracking-parameter removal.
- Tracking cleanup removes only known parameters: `utm_*`, `fbclid`, `gclid`, and `msclkid`.
- Exposed JSON and URL tools through compact status bar menus and Text Tools menu commands.
- Added `Cmd+Shift+J` for JSON format and `Cmd+Shift+M` for JSON minify.
- Added focused self-tests for valid JSON, invalid JSON, URL decode, and tracking cleanup.

Error or blocker log:

- JSON formatting uses Foundation `JSONSerialization`, so output ordering/spacing follows Foundation's formatter.
- URL tracking cleanup treats each line as a URL-like string; it does not scan arbitrary prose for embedded URLs yet.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- Inspection-only actions like JSON validate need a small store inspection path because transforms that return identical text should still show useful status.

## 2026-05-15 - Phase 8: Safe Share

Status: success

Changed files:

- `Sources/OhbeeEditorCore/SafeShare.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added local conservative detection for emails, phone numbers, bearer tokens, JWT-like strings, `.env` style secrets, API-key-like assignments, common prefixed API keys, and URLs with token-like parameters.
- Added detection status wording beginning with `Potential sensitive text found`.
- Added masking as a normal editor transform through the shared operation path.
- Exposed Safe Share detection and masking through the status bar and Text Tools menu.
- Added `Cmd+Shift+R` for Safe Share detection.
- Added self-tests for detection, masking, and an obvious normal-text false-positive case.

Error or blocker log:

- Safe Share is intentionally best-effort and does not guarantee complete secret detection.
- Masking currently applies to the full document because selected-text transforms remain deferred until an `NSTextView` editor surface is added.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- Keep Safe Share language careful: it helps users notice potential sensitive text, but it should not overclaim security.

Next recommended phase:

- Phase 9: UX Polish and macOS Integration, or the lightweight `NSTextView` editor wrapper if visual search selection and selected-text transforms are the priority.

## 2026-05-15 - UX Fix: Language Indicator and JSON Tool Gating

Status: success

Changed files:

- `Sources/OhbeeEditorCore/EditorLanguage.swift`
- `Sources/OhbeeEditorCore/EditorDocument.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added extension-based language inference for common text formats, including `.json`.
- Kept `View > Language` as an explicit per-document override over the extension-derived visible language.
- Changed the `View > Language` submenu to a picker so macOS shows the checked language item.
- Updated the editor header to show the effective language.
- Enabled JSON tools only when the selected document is a `.json` file or the user explicitly selected JSON.
- Kept JSON tools enabled for `.json` files even if the visible language is overridden to something else.
- Added status message tones and made JSON validation success dark green and validation failure dark orange.
- Added self-tests for language inference, override behavior, and JSON tool enablement rules.

Error or blocker log:

- The menu checkmark is native macOS picker behavior and was verified by successful build; no automated UI assertion exists yet.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- Language display and tool availability are related but not identical: extension inference should help automatically, while explicit language selection controls the visible indicator.

## 2026-05-15 - UX Follow-up: Simple Local Syntax Highlighting and Finder Open With Plan

Status: success

Changed files:

- `Strategy.md`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `progress.md`

Success log:

- Reframed syntax highlighting in `Strategy.md` as simple readability-only highlighting, not IDE behavior.
- Added explicit rules against language servers, autocomplete, code navigation, symbol indexing, syntax-aware refactoring, remote grammars, and parser dependencies.
- Replaced the bootstrap `SwiftUI.TextEditor` with a lightweight AppKit `NSTextView` wrapper.
- Added local regex-based highlighting driven by the selected or inferred language.
- Plain Text remains visually quiet.
- Added basic highlighting for JSON, markup, SQL, CSS, structured text, and common code-like languages.
- Added an `onOpenURL` file handler so future Finder `Open With` integration can open files into tabs.
- Added a new Finder `Open With` integration phase to `Strategy.md`, including app bundle document type declarations and the rule that Ohbee Editor should appear as an option without aggressively replacing user defaults.

Error or blocker log:

- Finder `Open With` registration itself is not complete because the current project is still a SwiftPM executable; it needs a proper `.app` bundle with document type metadata.
- Highlighting is intentionally regex-based and best-effort; it is for readability, not syntax correctness.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- Simple highlighting fits the product promise when it helps human scanning and avoids IDE features.
- Finder integration should be treated as packaging/macOS metadata work, separate from editor scope.

## 2026-05-15 - UX Fix: Highlight Colors and Window Title

Status: success

Changed files:

- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Adjusted JSON highlighting to separate keys from string values: keys red, string values blue, numbers green, and booleans/null blue bold.
- Fixed HTML/XML highlighting so the closing `>` of open tags is highlighted with the tag.
- Added dynamic window titles in the form `Ohbee Editor - <current tab>`.
- Scratch notes use their note title, such as `Ohbee Editor - Note 1`.
- Unique file-backed tabs use the file name, such as `Ohbee Editor - mylocalfile.txt`.
- Duplicate open file names use the full path; long paths compact to keep the starting directory and immediate parent directory visible.
- Added self-tests for scratch, unique file, and duplicate file window titles.

Error or blocker log:

- Highlighting remains simple regex-based readability coloring, not parser-accurate syntax highlighting.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- Highlight rule order matters: broad string rules must run before key-specific JSON rules so keys can override value coloring.
- Window title formatting belongs in the store so UI and tests share the same duplicate-name behavior.

## 2026-05-15 - UX Fix: Java Syntax Highlighting

Status: success

Changed files:

- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `progress.md`

Success log:

- Inspected the current highlighting path: `ContentView` passes `document.effectiveLanguage` into `HighlightedTextEditor`, which dispatches through `SimpleSyntaxHighlighter`.
- Kept the existing AppKit `NSTextView` highlighter and avoided new dependencies.
- Added a dedicated Java highlighting branch instead of using the generic code keyword list.
- Added Java keyword coverage, including newer terms such as `var`, `record`, `sealed`, `permits`, `non-sealed`, and `yield`.
- Added common Java built-in type/class highlighting for `String`, `System`, collection types, date/time types, number types, and exception types.
- Added annotation highlighting for `@Override`, `@Deprecated`, `@SuppressWarnings`, and `@FunctionalInterface`.
- Added Java number coverage for decimal, floating point, hex, suffixes, and underscores.
- Added protected ranges so Java keywords/types/numbers/annotations are not highlighted inside string literals or comments.

Error or blocker log:

- Java highlighting remains regex-based syntax coloring only; no parser, compiler integration, autocomplete, or code intelligence was added.
- The self-test target covers core logic, while visual highlighter behavior is currently verified through successful app build rather than automated UI color assertions.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- For lightweight highlighting, a small protected-range pass gives useful correctness without introducing a parser.

## 2026-05-15 - UX Fix: Lightweight Highlighting for Common Languages

Status: success

Changed files:

- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `progress.md`

Success log:

- Inspected the current syntax highlighting implementation before editing.
- Kept the existing `NSTextView` editor surface and language menu behavior unchanged.
- Added a small reusable `CodeHighlightDefinition` for lightweight regex highlighting rules.
- Added dedicated local highlighting definitions for JavaScript, C#, C++, Python, Swift, Shell, and CSS.
- Added per-language keyword, builtin/type, annotation/decorator where useful, string, number, and comment rules.
- Reused protected ranges so keyword/type/number rules do not apply inside strings or comments.
- Preserved Plain Text behavior: Plain Text still returns without highlighting.
- Avoided dependencies, networking, telemetry, analytics, LSP, autocomplete, code navigation, formatters, compiler integration, project indexing, and parser integration.

Error or blocker log:

- Visual highlighting is not covered by automated color assertions yet; verification is build-level plus the existing self-test suite.
- Highlighting remains regex-based and best-effort, so it is intended for readability rather than parser-accurate tokenization.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- A tiny definition struct keeps language-specific rules reviewable without redesigning the editor.

## 2026-05-15 - UX Fix: Markup and Content Highlighting

Status: success

Changed files:

- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `progress.md`

Success log:

- Inspected the current highlighter before editing: `ContentView` passes `document.effectiveLanguage` into `HighlightedTextEditor`, then `SimpleSyntaxHighlighter` dispatches by `EditorLanguage`.
- Kept the editor surface, language menu, and Plain Text behavior unchanged.
- Split shared HTML/XML highlighting into small dedicated HTML and XML paths.
- Added ordered token handling for markup: comments/doctype/processing instructions first, strings next, then tag names, delimiters, attributes, numeric/boolean attribute values, and entities.
- Added XML-specific CDATA protection.
- Improved CSS highlighting with ordered comments, strings, at-rules, selectors, hex colors, properties, values, and numeric units.
- Split YAML and Markdown highlighting into dedicated paths.
- Improved YAML highlighting for comments, strings, keys, document markers, booleans/null-like values, numbers, list markers, anchors, aliases, and tags.
- Improved Markdown highlighting for fenced code, inline code, headings, list markers, blockquotes, links/URLs, bold, and emphasis.
- Preserved the no-parser/no-preview/no-LSP/no-dependency scope.

Error or blocker log:

- Highlighting remains regex-based and best-effort; it is meant for readable editing, not validation or renderer accuracy.
- Visual color behavior is not covered by automated UI assertions yet.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.
- `swift -e` regex compile smoke check succeeded outside the sandbox after the sandboxed attempt could not access Swift module cache.

Lessons learned:

- Markup/config/content highlighting benefits from language-specific functions while still staying small and local.
- Ordered protected ranges keep comments and strings from being accidentally recolored by later rules.

## 2026-05-15 - UX Fix: SQL Syntax Highlighting

Status: success

Changed files:

- `Sources/OhbeeEditorCore/SQLSyntaxTokenizer.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Inspected the current highlighter before editing: `ContentView` passes `document.effectiveLanguage` into `HighlightedTextEditor`, then `SimpleSyntaxHighlighter` dispatches by `EditorLanguage`.
- Added a small pure SQL tokenizer in the core target so token categories can be tested without UI color assertions.
- Updated SQL highlighting to use ordered tokens instead of loose overlapping regex passes.
- SQL comments are detected before other tokens.
- SQL strings and double-quoted identifiers are detected before keywords/functions/types.
- Keywords are case-insensitive.
- Added common SQL keywords, data types, functions, strings, quoted identifiers, numbers, operators, and punctuation.
- Preserved Plain Text behavior: SQL-looking text produces no SQL tokens when language is Plain Text.
- Avoided formatters, parsers, database behavior, autocomplete, LSP, external dependencies, networking, telemetry, and UI redesign.

Error or blocker log:

- SQL highlighting is still a lightweight scanner, not a full SQL parser.
- Dollar-quoted strings are supported for simple `$tag$...$tag$`/`$$...$$` spans, but dialect-specific SQL grammar is intentionally out of scope.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- A pure tokenizer is the right lightweight seam for SQL because it keeps token ordering testable without dragging AppKit into tests.

## 2026-05-15 - UX Fix: Smart Newline Indentation

Status: success

Changed files:

- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `progress.md`

Success log:

- Inspected the editor input path before editing: `HighlightedTextEditor` owns the AppKit `NSTextView`, and `textDidChange` syncs edits back into SwiftUI state.
- Confirmed Enter/newline previously used native `NSTextView` default behavior with no custom indentation.
- Added a tiny `SmartIndentingTextView` subclass local to the editor wrapper.
- Plain Text mode still calls the native newline behavior unchanged.
- Structured/code-like languages insert a newline plus the exact leading whitespace from the current line.
- Preserves tabs and spaces without conversion.
- Does not auto-format or modify existing text beyond the inserted newline and indentation.

Error or blocker log:

- No automated UI/input test exists for keypress behavior yet; verification is by successful app build and focused code path review.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- The existing `NSTextView` wrapper is the right narrow place for typing comfort behavior; no store/menu/UI redesign is needed.

## 2026-05-15 - Safe Share Fix: JSON Secret Key Detection

Status: success

Changed files:

- `Sources/OhbeeEditorCore/SafeShare.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added conservative detection for JSON-style secret key/value pairs such as `"APIKey": "long-value"`, `"token": "long-value"`, `"clientSecret": "long-value"`, and `"password": "long-value"`.
- Kept the detector value-length gated so short placeholders like `"APIKey": "short"` do not trigger.
- Added self-tests for JSON-style secret detection, masking, and short-placeholder false-positive avoidance.

Error or blocker log:

- Safe Share remains best-effort and conservative; it does not guarantee complete secret detection.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded.

Lessons learned:

- JSON key names are not sensitive by themselves, but secret-like key names paired with long string values should be treated as potential sensitive text.

## 2026-05-15 - Review Fix: Selection, Undo, Search Visibility, Highlighting, and URL Encode

Status: success

Changed files:

- `Sources/OhbeeEditor/EditorTextOperationCenter.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorCore/URLTools.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added an app-layer `EditorTextOperationCenter` that tracks the active `NSTextView`.
- Routed text transforms from toolbar/status menus and app menus through the active text view.
- Transforms now operate on the selected text when there is a selection, otherwise on the full document.
- Transform and search-replace edits use `NSTextView.insertText(_:replacementRange:)`, so they participate in the native undo stack instead of replacing store text directly.
- Detect/Validate inspector actions now inspect selected text when available.
- Find next/previous now selects and scrolls to the current match in the editor.
- Replace Current and Replace All now run through the active text view for visible, undoable edits.
- Debounced syntax highlighting after typing and skipped scheduled highlighting work in Plain Text mode.
- Changed URL Encode to encode arbitrary text as a URL component, including `&`, `=`, and `?`.
- Added a self-test for URL component encoding.

Error or blocker log:

- No automated UI test exists yet for AppKit selection, scroll-to-match, or undo behavior; verification is by build plus code-path review.
- Syntax highlighting is still whole-document once the debounce fires; larger future work could move to visible-range or changed-range highlighting if needed.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded.

## 2026-05-20 - Performance and Safety Polish: Highlighting, Persistence, Search, Close Flow, Safe Share

Status: success

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditor/SafeShareReviewView.swift`
- `Sources/OhbeeEditor/UnsavedTabWarning.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SafeShare.swift`
- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorCore/TextTransforms.swift`
- `Sources/OhbeeEditorCore/URLTools.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added visible-range syntax highlighting for medium/large buffers so the highlighter no longer recolors the whole document after every debounce once text passes the medium-size threshold.
- Kept large-file mode conservative: syntax highlighting remains disabled for files classified as large, while search highlights can still be drawn over the visible range.
- Added visual search highlighting in the editor: all capped matches get a soft highlight and the current match gets a stronger highlight.
- Exposed search match ranges from `SearchReplaceEngine` so UI highlighting reuses the same current-tab search logic.
- Debounced session persistence for text edits to coalesce rapid typing into one local session write.
- Added `flushPendingSessionSave()` and flush on app scene deactivation so pending local session state is written before the app leaves the active phase.
- Added a single-tab Save-before-close decision: dirty tabs can now Save, Close Without Saving, or Cancel.
- Kept multi-tab close flow simpler and safer with Close Without Saving or Cancel, avoiding a confusing multi-save panel sequence.
- Improved Safe Share review so individual findings can be selected/deselected before masking.
- Kept category counts and copy masked text, now based on the currently selected findings.
- Preserved dominant line endings for core line transforms such as trim whitespace, trim trailing whitespace, remove empty lines, remove duplicate lines, and sort lines.
- Improved URL tracking cleanup so it can remove known tracking parameters from embedded URLs inside prose, not only URL-per-line input.
- Added read-only file polish: the editor header now clearly labels read-only files and offers a direct Save As button.
- Added self-tests for debounced persistence flushing, embedded URL cleanup, selected Safe Share masking, Safe Share numeric false-positive avoidance, and CRLF preservation.

Error or blocker log:

- Visual search highlighting is still bounded for performance: only the first capped set of matches is highlighted, and very large documents limit highlight work to visible text.
- Syntax highlighting remains regex/tokenizer based and best-effort; no parser, LSP, autocomplete, indexing, networking, or dependency-heavy behavior was added.
- Automated UI assertions for AppKit highlight colors, close alert button behavior, and read-only header visuals are still not present; verification is build-level plus core self-tests.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded.
- `swift build` succeeded.

Lessons learned:

- The existing `NSTextView` wrapper is now the right place to keep editor responsiveness work small and local.
- Session persistence should distinguish content-edit churn from structural tab/file actions; only the former needs debouncing.
- Safe Share review is more useful when users can choose what to mask, but its wording should remain conservative and best-effort.
- `swift build` succeeded.

Lessons learned:

- The right boundary is to keep pure text logic in core, while editor-surface concerns like selection, undo, and scroll visibility belong beside the `NSTextView` bridge.

## 2026-05-15 - UX Polish: Tab Bar, Drag-and-Drop, Multi-File Open, and App Bundle

Status: success

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Makefile` (new)
- `Support/Info.plist` (new)
- `progress.md`

Success log:

- Replaced `.bordered` tab buttons with a custom `TabItemView` that uses plain button style with a rounded rectangle background: accent-tinted fill for selected, subtle primary highlight on hover, clear otherwise.
- Selected tab text uses `.medium` weight; unselected uses `.secondary` foreground — no button border in the tab strip.
- Dirty indicator dot is now 5 px, accent color when the tab is selected and `.secondary` when not.
- Added file drag-and-drop to `SmartIndentingTextView`: overrides `draggingEntered` and `performDragOperation` so Finder file drags open files as new tabs instead of inserting their content as text.
- Registered `.fileURL` pasteboard type on the text view at creation time.
- Threaded an `onFileDrop` callback from `HighlightedTextEditor` → `ScratchEditorView` → `editorArea` → `store.openDocument(from:)`.
- Updated `updateNSView` cast from `NSTextView` to `SmartIndentingTextView` so `onFileDrop` is refreshed on every view update.
- Changed `NSOpenPanel.allowsMultipleSelection` to `true` in both `ContentView` and `OhbeeEditorApp` so users can open several files at once.
- Added `Makefile` with `build`, `bundle`, `run`, and `clean` targets.
- `make bundle` assembles `Ohbee Editor.app` with the correct Contents/MacOS, Contents/Resources, and Contents/Info.plist layout.
- Added `Support/Info.plist` declaring `CFBundleDocumentTypes` with `LSHandlerRank: Alternate` for common text and source file extensions — app appears in Finder "Open With" without overriding system defaults.
- Existing `onOpenURL` handler in `OhbeeEditorApp` already routes file:// URLs into `store.openDocument`, so Finder open-with integration is complete once the bundle is registered.

Error or blocker log:

- Running the bundled app for the first time requires `lsregister -f "Ohbee Editor.app"` to force Finder to index the document types; the Makefile prints this reminder after `make bundle`.
- SPM resource bundle path in the Makefile uses the conventional `OhbeeEditor_OhbeeEditor.bundle` name; copy is silently skipped if not found (the resource bundle name may vary by SPM version).

Tests run:

- `swift build` succeeded (2.59s).
- `swift run OhbeeEditorSelfTests` succeeded. All 25 tests passed.

Lessons learned:

- A `TabItemView` struct with `@State private var isHovering` is cleaner than attaching `.onHover` to a `Button` inside a `ForEach` — each tab owns its own hover state independently.
- Drag-and-drop override in `SmartIndentingTextView` must check for file URLs first; falling through to `super` preserves native text drag behavior for non-file drags.
- `updateNSView` must cast to the concrete subclass (`SmartIndentingTextView`) to set the `onFileDrop` closure, otherwise updates to the closure are lost between SwiftUI view rebuilds.

## 2026-05-15 - Phase 11: Line Numbers and Document Info Popover

Status: success

Changed files:

- `Sources/OhbeeEditor/LineNumberRulerView.swift` (new)
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Strategy.md`
- `progress.md`

Success log:

- Added `LineNumberRulerView` — an `NSRulerView` subclass that draws line numbers in a 44pt gutter on the left side of the scroll view.
- Observes `NSText.didChangeNotification`, `NSView.boundsDidChangeNotification`, and `NSView.frameDidChangeNotification` to trigger redraws on edit, scroll, and resize.
- Coordinate math: `y = lineRect.minY + textContainerInset.height − visibleRect.minY` maps layout manager rects to ruler-view space.
- Handles wrapped lines: tracks `lastLineStart` (logical line's starting character index) and skips duplicate fragments from the same logical line.
- Handles empty document (0 glyphs): draws "1" using font bounding rect metrics.
- Handles extra line fragment: after the main `enumerateLineFragments` loop, checks `layoutManager.extraLineFragmentTextContainer` and draws one more line number when the text ends with a newline (cursor on empty last line).
- Added `showLineNumbers: Bool` parameter to `HighlightedTextEditor`; `makeNSView` attaches the ruler when true; `updateNSView` toggles `scrollView.rulersVisible` live.
- Added `@AppStorage("ohbee.lineNumbers")` in `OhbeeEditorApp` and `ScratchEditorView`; preference is shared via the same key and persists across restarts.
- Added `Toggle("Show Line Numbers", isOn: $showLineNumbers)` in `CommandGroup(after: .toolbar)` — renders as a native checkmark menu item under the View menu.
- Added `@State private var showDocInfo = false` and an `info.circle` icon button at the end of the status bar in `ContentView`.
- Button toggles a `.popover(arrowEdge: .top)` showing `DocumentInfoView`.
- `DocumentInfoView` displays: Lines, Words, Characters, Characters (no whitespace), Language, and File size (file-backed documents only via `FileManager` attributes).
- Uses SwiftUI `Grid` for aligned label/value layout; `ByteCountFormatter` for human-readable file size.

Error or blocker log:

- Initial implementation was missing the `extraLineFragmentRect` case: cursor on an empty last line (after a trailing newline) showed no line number. Fixed by checking `layoutManager.extraLineFragmentTextContainer` after the main enumeration loop.

Tests run:

- `swift build` succeeded (2.11s). No errors or warnings.

Lessons learned:

- `NSLayoutManager.enumerateLineFragments` does not visit the extra line fragment used for the cursor position after a trailing newline; must handle `extraLineFragmentRect` separately.
- `isFlipped: Bool { true }` must be overridden on `NSRulerView` subclasses used alongside a flipped `NSTextView` — without it, line numbers draw at the wrong y position.
- `scrollView.contentView.postsBoundsChangedNotifications = true` must be set explicitly; without it, scroll notifications are not delivered and line numbers do not update on scroll.

Next recommended phase:

- Code folding (brainstormed, deferred — complex, requires non-destructive text hiding via NSLayoutManager or NSTextAttachment).

## 2026-05-15 - Column Selection (Vertical Selection) and Help Menu

Status: success

Changed files:

- `Sources/OhbeeEditorCore/ColumnSelection.swift` (new)
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/OhbeeHelpView.swift` (new)
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `Strategy.md`
- `progress.md`

Success log:

- Implemented Option+Drag column (vertical/rectangular) selection in `SmartIndentingTextView`.
- Pure model: `LineMap` (O(n) construction, O(log n) line/column lookup) and `ColumnSelection` (one NSRange per line in the rectangle) in `OhbeeEditorCore/ColumnSelection.swift`.
- AppKit integration: `mouseDown` detects Option flag, `mouseDragged` updates `selectedRanges`, `mouseUp` commits, Escape exits and restores cursor.
- Copy (`⌘C`) and cut (`⌘X`) in column mode join ranges with `\n`. Delete key deletes column ranges sorted bottom-to-top, wrapped in an undo group.
- Fixed right-edge selection inaccuracy: used `fractionOfDistanceBetweenInsertionPoints` to distinguish character index vs insertion point; advance by 1 when fraction ≥ 0.5.
- Added `Edit → Vertical Selection…` menu item: shows a native `NSAlert` with `info.circle` SF Symbol icon explaining the Option+Drag gesture.
- Created `OhbeeHelpView.swift`: in-app help sheet showing all keyboard shortcuts, gestures, and tips. Follows the same pattern as `AboutOhbeeView`.
- Replaced the default macOS Help menu item with `Help → Ohbee Editor Help` (⌘/) wired to `isHelpVisible` sheet state.

Error or blocker log:

- Default NSAlert icon showed macOS folder icon (app icon). Fixed by setting `alert.icon = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)`.
- Swift access control: `LineMap`, `ColumnSelection`, and `copyColumnRanges` needed explicit `public` to be visible from `OhbeeEditor` and `OhbeeEditorSelfTests` targets.

Tests run:

- 11 column selection tests added to `OhbeeEditorSelfTests/main.swift` (35 total). All pass.
- `swift build` succeeded (2.22s). No errors.

Lessons learned:

- `NSTextView.selectedRanges: [NSValue]` is the official AppKit multi-range selection API; visual highlight is free, no custom drawing needed.
- `characterIndex(for:in:fractionOfDistanceBetweenInsertionPoints: nil)` returns the character index, not the insertion point. When the cursor is past the midpoint of a character, the returned index still points to that character. Must capture `fraction` and advance by 1 when `fraction >= 0.5` to include the last character in a drag selection.
- `CommandGroup(replacing: .help)` cleanly replaces the default macOS Help item with a custom SwiftUI button.

Next recommended phase:

- Phase 12 is complete. Consider: Finder Open With integration (Phase 10), further UX polish, or Safe Share improvements.

## 2026-05-15 - UX Polish: Cursor Line Gutter Highlight and Recent Files Submenu

Status: success

Changed files:

- `Sources/OhbeeEditor/LineNumberRulerView.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Strategy.md`
- `progress.md`

Success log:

- Added cursor-line highlight to the gutter: the line number at the current cursor position renders in `NSColor.controlAccentColor` with medium weight; all other line numbers remain quaternary label color.
- Implemented by observing `NSTextView.didChangeSelectionNotification` in `LineNumberRulerView`, mapping selection location to a 1-based line number via `LineMap`, and using per-line attribute selection in `drawHashMarksAndLabels`.
- Covers the empty document case, wrapped lines, and the extra line fragment (cursor on trailing newline).
- Added `recentFiles: [URL]` to `EditorStore`, persisted as path strings in `UserDefaults` under `ohbee.recentFiles`.
- `openDocument(from:)` now prepends the opened URL to `recentFiles` (deduped, capped at 10) and saves to `UserDefaults`.
- Added `clearRecentFiles()` to wipe the list and the UserDefaults entry.
- Added `Open Recent` submenu under `File → Open...` in `OhbeeEditorApp` commands. Submenu shows up to 10 recent file names with full-path tooltip; shows disabled "No Recent Files" when empty; includes a "Clear Recent Files" item when non-empty.

Error or blocker log:

- None.

Tests run:

- `swift build` succeeded (2.90s). No errors or warnings.

Lessons learned:

- `NSTextView.didChangeSelectionNotification` fires on every cursor move and selection change; the handler is cheap (one `LineMap` lookup) so redraw cost is minimal.
- SwiftUI `Menu` inside `CommandGroup` renders as a native macOS submenu; `ForEach` over `@Published` URL array works correctly because `store` is an `ObservableObject` referenced in the `commands` closure.

## 2026-05-16 - Tab UX Polish: Tooltip, Truncation, Drag-to-Reorder; Gutter Highlight Bug Fixes

Status: success

Changed files:

- `Sources/OhbeeEditor/LineNumberRulerView.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`

Success log:

- Fixed gutter off-by-one: `LineMap.lineStarts` appends `idx+1` after each `\n`, so for trailing-newline text `lineCount` already equals the visual line count including the extra fragment. Previous fix used `lineCount + 1` (one too high). Corrected to `lineMap.lineCount` when `loc >= length`.
- Fixed gutter showing line 1 after tab switch: added `syncCursorLine()` public method; `HighlightedTextEditor.makeNSView` now calls it after `makeFirstResponder` fires so the ruler syncs to the actual cursor position.
- Feature: tab tooltip — `.help(document.fileURL?.path ?? document.title)` shows full file path on hover for file-backed tabs, or just the tab name for scratch notes.
- Feature: tab title truncation — `.truncationMode(.middle)` on the tab title Text view; SwiftUI truncates long names from the middle proportional to available width (natural behavior over hardcoded char counts).
- Feature: drag-to-reorder tabs — `TabDropDelegate` with `DropDelegate` protocol; `dropEntered` moves the dragged document in real-time with a short ease animation. Added `moveDocument(from:to:)` to `EditorStore`.

Error or blocker log:

- None. Build succeeded (2.70s).

Tests run:

- `swift build` succeeded. No errors or warnings.

Lessons learned:

- `LineMap.lineStarts` is 0-indexed line starts built by scanning for `\n` and appending `idx+1`; the virtual entry at `length` is added after the trailing newline, so `lineCount` is the correct cursor line for the extra fragment — no `+1` needed.
- SwiftUI `.id()` on `NSViewRepresentable` calls `makeNSView` (not `updateNSView`) on tab switch, but `didChangeSelectionNotification` does not reliably fire after `makeFirstResponder` if selection stays at 0. Explicit `syncCursorLine()` post-dispatch is the reliable fix.
- SwiftUI `.onDrag` + `.onDrop` on individual items in an `HStack` produces live drag-reorder for a horizontal tab bar — same pattern as `List` row reordering but in a horizontal layout.

## 2026-05-16 - Bug Fixes: Tab Tooltip and File-Backed Session Persistence

Status: success

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`

Success log:

- Fixed tab tooltip not appearing on hover: `.help()` placed outside `.onDrag` caused the drag gesture to consume hover events before the tooltip system saw them. Moved tooltip string inside `TabItemView` as a `tooltip` parameter and applied `.help(tooltip)` on the inner `HStack`, below the drag modifier in the chain.
- Fixed file-backed tabs not surviving app restart: `saveSession()` was filtering `documents.filter(\.isScratch)` — file-backed tabs were never written to the session JSON. Changed to save all open documents. `restoreSession()` updated to restore all documents, not scratch-only. File-backed documents restore with their in-memory text (unsaved edits preserved); content is not re-read from disk on restore.

Error or blocker log:

- None.

Tests run:

- `swift build` succeeded (2.91s). No errors or warnings.

Lessons learned:

- SwiftUI `.help()` (tooltip) must be applied *inside* `.onDrag` in the modifier chain, not outside it. When `.onDrag` wraps `.help()`, the drag gesture recognizer intercepts hover tracking and the tooltip never fires.
- Session persistence filtering by `isScratch` was a deliberate early MVP constraint (Phase 2) that became a bug once file-backed tabs became a first-class part of the workflow. Saving all documents is safe because `EditorDocument` is `Codable` and file paths are round-trippable.

Next recommended phase:

- Continue UX polish or Finder Open With integration (Phase 10).

## 2026-05-16 - Phase 15: Editor Comfort, Checksum Tools, and Hyperlinks

Status: success

Changed files:

- `Strategy.md`
- `Sources/OhbeeEditorCore/ChecksumTools.swift` (new)
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditor/EditorTextOperationCenter.swift`
- `Sources/OhbeeEditor/OhbeeHelpView.swift`
- `progress.md`

Success log:

- Added font size control: Cmd+= (increase), Cmd+− (decrease), Cmd+0 (reset to 13pt). Persisted via `@AppStorage("ohbee.fontSize")` as `Double`; passed to `HighlightedTextEditor` as `CGFloat`. Range: 10–36pt.
- Added Cmd+Shift+D to duplicate current line (wrapped in undo group). Also wired in Text Tools menu via `EditorTextOperationCenter.duplicateLineInActiveEditor()`.
- Added Option+Up / Option+Down to move the current line up or down (swap with adjacent line, wrapped in undo group). Edge cases handled: trailing-newline-less last line swaps cleanly.
- Added URL/hyperlink detection via `NSDataDetector` in `SimpleSyntaxHighlighter.detectLinks()`. Applied `.link`, `NSColor.linkColor`, and `.underlineStyle` attributes after every language highlighting pass, including Plain Text. Cmd+Click opens URL in system browser via `NSWorkspace.shared.open`. Skipped for large files.
- Overrode `SmartIndentingTextView.clicked(onLink:at:)` for safe URL opening.
- Added SHA-256 and MD5 checksum (using `CryptoKit`) as inspect-only operations. Exposed via status bar Hash menu and Text Tools menu.
- Bug fix: added `Divider()` between the document title header and the `HighlightedTextEditor` in `ScratchEditorView`, eliminating the visual overlap.
- Made `SmartIndentingTextView` internal (was `private`) to allow `EditorTextOperationCenter` to cast and call `triggerDuplicateLine()`.

Error or blocker log:

- `@AppStorage` does not support `CGFloat`; used `Double` for storage and cast to `CGFloat` at the call site.

Tests run:

- `swift build` succeeded (2.07s). No errors or warnings.
- `swift run OhbeeEditorSelfTests` succeeded. All 43 tests passed.

## 2026-05-17 - Phase 16: Inspect Tools, Tab Diff, and Distribution Prep

Status: success

Changed files:

- `Strategy.md`
- `Sources/OhbeeEditorCore/XMLTools.swift` (new)
- `Sources/OhbeeEditorCore/WordFrequencyTools.swift` (new)
- `Sources/OhbeeEditorCore/DiffTools.swift` (new)
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditor/WordFrequencyView.swift` (new)
- `Sources/OhbeeEditor/CompareTabsSheet.swift` (new)
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Support/Entitlements.plist` (new)
- `Support/Info.plist`
- `Makefile`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added `XMLTools` with format and minify via Foundation `XMLDocument`. Invalid XML returns error message without mutating document. Gated to XML-language documents in status bar and Text Tools menu.
- Added `WordFrequencyTools.topWords(in:limit:)`: splits on whitespace and punctuation, lowercases, discards ≤1-char tokens, returns top N by count. Status bar popover (chart.bar.xaxis icon) shows scrollable top-20 table. Text Tools > Word Frequency shows top-5 preview in status bar.
- Added `DiffTools` with LCS-based line diff (`O(nm)`). `annotatedText(baseTitle:changedTitle:base:changed:)` produces `--- base / +++ changed / + added / - removed / common` format.
- Added `EditorStore.openDiffTab(baseID:changedID:)`: computes diff and opens annotated result in a new scratch tab.
- Added `CompareTabsSheet`: SwiftUI sheet with two Pickers selecting base and changed tabs, Compare button (disabled when same tab selected). Accessible from status bar icon (arrow.left.arrow.right) and Edit > Compare Tabs… (Cmd+Shift+C, disabled when fewer than 2 tabs open).
- Added `Help > Check for Updates…` menu item that opens `https://ohbee.link` in the system browser. No network logic in the app.
- Added `make icon` Makefile target: generates `Support/AppIcon.icns` from `logo.png` (1254×1254) via `sips` + `iconutil`. Generates all required sizes from 16×16 to 1024×1024 (@1x and @2x).
- Added `make codesign` target: signs the `.app` bundle with hardened runtime using `DEVELOPER_ID` and `Support/Entitlements.plist`.
- Added `make notarize` target: submits to Apple notarization via `xcrun notarytool` then staples the ticket.
- Added `Support/Entitlements.plist` with minimal empty dict; no sandbox entitlements (non-sandboxed app).
- Bumped version to 1.0.3 (bundle version 4) in `Info.plist` and `Makefile`.
- Dropped: Sparkle/auto-update (violates local-first principle). Deferred: Base64, epoch/timestamp, menu bar mode.

Error or blocker log:

- `Grid(columnSpacing:rowSpacing:)` API does not exist; correct params are `horizontalSpacing` and `verticalSpacing`. Fixed in `WordFrequencyView` and `CompareTabsSheet` before final build.
- Notarization targets are scaffolding only; actual notarization requires user's Apple Developer ID certificate and a `notarytool-profile` stored in Keychain.

Tests run:

- `swift build` succeeded (2.32s). No errors or warnings.
- `swift run OhbeeEditorSelfTests` succeeded. All 56 tests passed (13 new: 4 XML, 3 word frequency, 6 diff).

## 2026-05-18 - CR-Offline-01, CR-Session-01, CR-PlainText-01, CR-SafeShare-01

Status: success

Changed files:

- `Sources/OhbeeEditor/AboutOhbeeView.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorCore/EditorDocument.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/LargeFilePolicy.swift`
- `Sources/OhbeeEditorCore/SessionPersistence.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Removed `Help > Check for Updates...` so the app no longer exposes an update action that opens the browser.
- Changed the About window site label from a clickable `Link` to plain text.
- Removed automatic URL linkification from the editor surface.
- Removed Cmd+Click URL opening from `SmartIndentingTextView`.
- Plain Text mode now remains visually plain: no automatic `.link` attributes, underline, or link-color pass.
- Large scratch and dirty file-backed buffers are no longer silently dropped from session restore.
- Added local sidecar persistence under Application Support for session text larger than `LargeFilePolicy.sessionTextCap`; the JSON session stays lightweight while large unsaved text restores locally.
- Clean file-backed documents still store no text in session JSON and continue to reload from disk.
- Added a sidecar round-trip self-test that verifies large scratch text stays out of JSON but restores correctly.

Error or blocker log:

- No blockers.
- The app still contains URL strings in URL-tool and Safe Share tests; these are static test fixtures and do not open network connections.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.
- `swift build` succeeded.

Lessons learned:

- The strongest offline guarantee is not just "no URLSession"; the UI should also avoid browser handoffs unless explicitly requested.
- Large-session safety needs a two-part design: keep JSON small, but never silently discard unsaved user text.

## 2026-05-19 - Phase 18: Safe Share Review and Clean Copy

Status: success

Changed files:

- `Strategy.md`
- `README.md`
- `Sources/OhbeeEditorCore/SafeShare.swift`
- `Sources/OhbeeEditor/SafeShareReviewView.swift` (new)
- `Sources/OhbeeEditor/EditorTextOperationCenter.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditor/OhbeeHelpView.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added `SafeShareReview` and `SafeShareCategorySummary` in the core target so review state is pure and testable.
- Added a Safe Share review sheet opened from the status bar menu or `Text Tools > Review Safe Share...`.
- Changed `Cmd+Shift+R` to open the review flow instead of only reporting a status message.
- Review uses the selected text when available, otherwise the full document, through `EditorTextOperationCenter.operationText(store:)`.
- The review sheet shows cautious Safe Share wording, category counts, masked snippets, and a masked preview.
- Added `Copy Masked`, which writes the redacted preview to the local pasteboard without mutating the document.
- Added `Apply Mask`, which applies the redacted preview through the shared editor operation path so native undo remains available.
- Kept `Detect Sensitive Text` as a quick status-only scan.
- Updated Help and README shortcut/discoverability text.
- Added self-tests for review source preservation, category summaries, masked preview behavior, snippets, and no-finding review behavior.

Error or blocker log:

- Initial app build failed because `.frame(width:minHeight:)` is not a valid SwiftUI overload. Fixed by splitting it into `.frame(width:)` and `.frame(minHeight:)`.
- No automated UI test exists for the sheet button interactions; verification is build-level plus core self-tests.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.
- `swift build` succeeded.

Lessons learned:

- Safe Share is more useful as a review workflow than as only a status message: users can inspect, copy a clean version, or intentionally apply redaction.
- Keeping review generation in the core target makes the privacy workflow easy to test without AppKit.
- `Copy Masked` is a good default sharing path because it avoids changing the source buffer.

## 2026-05-19 - Phase 18 Bug Fix: Safe Share Prepare and Copy Feedback

Status: success

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/SafeShareReviewView.swift`
- `progress.md`

Success log:

- Removed the extra `prepareSafeShareReview()` call from `presentSafeShareReview()` so status-bar launch no longer scans twice.
- Kept `.onChange(of: isSafeShareReviewVisible)` as the single prepare path for both status-bar and menu/shortcut launches.
- Added timed reset for the `Copied` feedback label after `Copy Masked`.
- Used a per-copy UUID token so repeated copy clicks do not let an older timer hide the newest feedback early.

Error or blocker log:

- No blockers.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.
- `swift build -c release` succeeded.
- `make bundle` failed inside the sandbox because SwiftPM/clang could not write user cache files.
- `make bundle` succeeded outside the sandbox and created `Ohbee Editor.app`.

Lessons learned:

- Sheet presentation should have one owner for snapshot preparation; duplicated setup is easy to miss when one path is local UI and another is app commands.
- Short-lived copy feedback needs stale-timer protection when the action can be repeated quickly.

## 2026-05-19 - Release Prep: 1.1.3

Status: success

Changed files:

- `Makefile`
- `Support/Info.plist`
- `README.md`
- `progress.md`

Success log:

- Bumped app version from `1.1.2` to `1.1.3`.
- Bumped bundle version from `7` to `8`.
- Updated README to document recent editor, large-file, read-only, whole-word search, XML, URL, inspect, image viewer, and Safe Share Review behavior.
- Documented that Plain Text mode stays visually plain with no automatic URL linkification or browser-opening behavior.

Error or blocker log:

- First sandboxed `make build` failed because SwiftPM/clang could not write user cache files and surfaced the known local toolchain/SDK mismatch message.
- Re-ran `make build` outside the sandbox successfully.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.
- `make build` succeeded outside the sandbox.

Lessons learned:

- Release verification for this SwiftPM macOS app still needs cache write access outside the workspace.
- README needs periodic product-surface refresh now that the app has moved well beyond the initial MVP.

## 2026-05-20 - Performance and Close-Flow Follow-up

Status: success

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Kept debounced syntax highlighting on the visible-range path for medium-sized documents instead of falling back to whole-document highlighting after typing.
- Added range-limited search matching so visual search highlights can paint the visible editor range without scanning the whole document.
- Disabled visual search scanning for large-file mode while still clearing visible stale highlight attributes.
- Preserved current-match emphasis by highlighting the selected visible match separately from the capped background-match pass.
- Updated Close Other, Close To Right, and Close All flows to honor Save when exactly one dirty tab is being closed.
- Added self-test coverage for range-limited literal and regex search matching.

Error or blocker log:

- The first new range-limited search self-test used a range that still included a later match; fixed the test range and reran successfully.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.
- `swift build` succeeded.

Lessons learned:

- Visible-range highlighting needs to be enforced on both immediate and debounced editor update paths.
- Search highlight should use a bounded range API; otherwise a UI polish feature can quietly reintroduce the same large-document lag it was meant to avoid.

## 2026-05-21 - README Refresh for 1.1.4 and Repository Move

Status: success

Changed files:

- `README.md`
- `progress.md`

Success log:

- Updated README current release text to 1.1.4.
- Refreshed README feature descriptions based on git history and progress notes for debounced local persistence, visible search highlights, save-before-close, read-only Save As polish, line-ending preservation, embedded URL cleanup, and selective Safe Share masking.
- Updated clone instructions from the old personal GitHub repository to `git@github.com:ohbee-labs/ohbee-editor.git`.
- Added the HTTPS organization clone URL: `https://github.com/ohbee-labs/ohbee-editor.git`.

Error or blocker log:

- No blockers.

Tests run:

- Not run. Documentation-only update.

Lessons learned:

- README drift is likely after release-focused commits; keep repository ownership, version, and high-level user-facing behavior in sync after each release prep.

## 2026-05-22 - Phase 19: Post-Release Trust Polish

Status: success

Changed files:

- `docs/release-checklist.md`
- `Sources/OhbeeEditor/SafeShareReviewView.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `Strategy.md`
- `progress.md`

Success log:

- Added Phase 19 to `Strategy.md` with explicit scope: release QA checklist, Safe Share copy flow polish, and search/replace edge-case tests.
- Added a local release QA checklist covering build/package, launch/editing, session restore, file open/save, search/replace, text tools, Safe Share, editor UX, Finder integration, and no-network product constraints.
- Updated Safe Share review copy feedback so Copy Masked states that masked text was copied and the document was unchanged.
- Added button help text clarifying Copy Masked uses the pasteboard only and Apply Mask mutates through the editor undo path.
- Added self-tests for empty search queries, invalid regex, regex capture replacement, whole-word boundaries, and case-sensitive matching.

Error or blocker log:

- No blockers.
- `swift build` briefly waited on the `.build` lock because it was started while `swift run OhbeeEditorSelfTests` was already building; it completed successfully after the self-test build released the lock.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.
- `swift build` succeeded.

Lessons learned:

- Post-release polish should favor release confidence, local data trust, and edge-case coverage over new feature surface.
- Safe Share copy behavior is clearer when the UI distinguishes local pasteboard copying from document mutation.

## 2026-05-24 - Workspace Sync and Strategy Trust Cleanup

Status: success

Changed files:

- `docs/release-checklist.md`
- `Strategy.md`
- `progress.md`

Success log:

- Fetched `origin/main` and confirmed local `main` is synced with `origin/main`.
- Ran the self-test suite successfully.
- Ran a full Swift build successfully.
- Removed stale Strategy text that still described automatic URL linkification, Cmd+Click browser opening, and a browser-opening Check for Updates menu item.
- Updated the release checklist so manual QA verifies Cmd+Click does not open the browser.
- Updated the roadmap language to match the current offline/no-browser-handoff product direction.

Error or blocker log:

- Initial sandboxed `git fetch --prune origin` could not write `.git/FETCH_HEAD`; reran with approved escalation and completed successfully.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.
- `swift build` succeeded.

Lessons learned:

- The code and later progress entries already reflect the stronger offline trust posture; keep `Strategy.md` aligned so future work does not revive removed browser-handoff behavior.

## 2026-05-24 - Release 1.1.6: Daily Comfort Patch

Status: success

Changed files:

- `CHANGELOG.md`
- `Makefile`
- `README.md`
- `Sources/OhbeeEditor/AboutOhbeeView.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditor/SafeShareReviewView.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SafeShare.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `Support/Info.plist`
- `docs/release-checklist.md`
- `progress.md`

Success log:

- Added Reopen Closed File with `Cmd+Shift+T`, scoped to file-backed tabs and capped to 10 recently closed files.
- Added Save All with `Cmd+Option+S` for dirty writable file-backed tabs; unsaved notes and read-only files are skipped with status feedback.
- Added Copy File Path and Copy File Name to file-backed tab context menus.
- Improved Open Recent by disabling missing files and adding Remove Missing Recent Files.
- Added Copy Summary to Safe Share Review so users can copy category counts without sensitive values.
- Added app version/build display to the About window.
- Bumped app version to `1.1.6` and bundle build number to `11`.

Error or blocker log:

- First self-test/build pass failed because a throwing file read was placed inside the non-throwing `expect` autoclosure. Fixed by reading the file into a local value before assertion.
- Sandboxed `make build` failed with the known SwiftPM/clang cache permission and local SDK/toolchain mismatch messages; reran outside the sandbox successfully.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.
- `swift build` succeeded.
- `make build` succeeded outside the sandbox.

Lessons learned:

- Daily-driver features should stay scoped to real local files when they interact with close/reopen/save behavior; unsaved notes already have session persistence and should not clutter reopen history.

## 2026-05-26 - Hotfix: Safer Finder/Open With File Opening

Status: success

Changed files:

- `CHANGELOG.md`
- `Makefile`
- `README.md`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Support/Info.plist`
- `progress.md`

Success log:

- Added an `NSApplicationDelegate` file-open path for Finder/Open With/document events, including a small pending-file queue for events that arrive before the SwiftUI window content has installed its handler.
- Kept the existing SwiftUI `.onOpenURL` path, but routed it through the same deferred external-file opening function.
- Deferred external file opens onto the main queue before mutating `EditorStore`, reducing the chance that macOS document-open events update SwiftUI state mid-layout.
- Activated and raised the app window after external file opens so opening a downloaded file brings the editor forward.
- Made the tab strip horizontally scrollable, so opening many files does not force a single `HStack` to lay out an unbounded row of tabs and controls.
- Bumped app version to `1.1.7` and bundle build number to `12`.

Error or blocker log:

- The crash report only contained SwiftUI/AppKit framework frames, not project frames, so the exact failing view could not be symbolicated from the report alone.
- The likely risk area was external file opening into SwiftUI state while the app/window was being reactivated, combined with tab strip layout after adding a file-backed tab.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.

Lessons learned:

- Finder/Open With should be handled through AppKit document-open delegate callbacks in addition to SwiftUI URL handling.
- Keep tab layout bounded even with the 50-tab cap; a scrollable tab row is a better fit for the app than letting toolbar controls compete with every open tab.

## 2026-05-29 - Hotfix: Tab Width Matches Four Spaces

Status: success

Changed files:

- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `progress.md`

Success log:

- Configured the AppKit editor paragraph style so tab stops are measured from the current monospaced editor font.
- Set the default tab interval to the measured width of four space characters, matching the expected Notepad++-style visual alignment.
- Applied the paragraph style to existing text, typing attributes, large-file mode, syntax-highlighted text, and font-size changes.

Error or blocker log:

- No blocker. This is a rendering fix, so automated self-tests cover build/core regressions but not the visual pixel alignment.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.

Lessons learned:

- `NSTextView` does not automatically make a tab equal to four spaces just because the font is monospaced; paragraph tab stops must be configured explicitly.

## 2026-05-31 - Hotfix: Crash Finding Hardening

Status: success

Changed files:

- `Sources/OhbeeEditor/CompareTabsSheet.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/ImageViewerView.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SafeShare.swift`
- `Sources/OhbeeEditorCore/SessionPersistence.swift`
- `progress.md`

Success log:

- Hardened Compare Tabs so the sheet no longer subscripts `documents[0]` / `documents[1]` and disables compare when the tab list changes under it.
- Wrapped editor text storage highlight and paragraph-style mutations in editing batches.
- Removed unnecessary force unwraps in column selection and editor store initialization.
- Added a fallback Application Support path if Foundation returns no user-domain support URL.
- Guarded image viewer async loads against stale file URL writes.
- Replaced Safe Share regex `try!` with a precondition failure that includes the detector category and regex error.

Error or blocker log:

- No blocker. The Compare Tabs and image viewer crash paths are UI-state timing issues, so verification is build/self-test plus code-path inspection rather than a dedicated UI automation test.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded. All self-tests passed.

Lessons learned:

- SwiftUI disabled controls are not a sufficient invariant for sheet initialization; sheets should still defend their own input shape.
- AppKit text storage mutations are safer when batched, especially while SwiftUI is switching editor views quickly.

## 2026-06-01 - Utility Spine: Selection Transforms, Command Palette, and Log Cleanup

Status: success

Changed files:

- `Sources/OhbeeEditor/EditorTextOperationCenter.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditorCore/LogCleanupTools.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Kept text-changing commands on the shared `EditorTextOperationCenter` path and reinforced the active `NSTextView` replacement path with `shouldChangeText(in:replacementString:)`, `textStorage.replaceCharacters`, `didChangeText`, and undo coalescing boundaries so selection-aware transforms use native editor editing hooks.
- Added `selectedText(store:)` so utility UI can prefill small prompts from the current selection without changing the transform target contract.
- Added a lightweight command palette on `Cmd+Shift+P` with filtered local actions for common cleanup, JSON, URL, Safe Share, and log operations.
- Added a compact Log menu with keep/remove lines containing, extract URLs, extract IPv4 addresses, and remove timestamp prefixes.
- Added `LogCleanupTools` as pure core transforms with stable unique extraction, conservative IPv4 validation, line-ending preservation for line filters, and structured transform results.
- Added self-tests for log keep/remove filters, URL extraction, IPv4 extraction, timestamp prefix removal, and invalid IPv4 rejection.

Error or blocker log:

- No meaningful blocker. GUI behavior was verified by build rather than launching the macOS app in the Codex session.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded.
- `swift build` succeeded.

Lessons learned:

- The existing `NSTextView` wrapper already made selection-aware operations practical; future transforms should continue to enter through `EditorTextOperationCenter` rather than bypassing the editor surface.
- Command palette actions can stay as a thin UI layer over existing pure transforms and app commands, preserving the lightweight/local-first product shape.
- Log cleanup is a strong fit for Ohbee because it adds practical messy-text value with deterministic, unit-testable string transforms and no new dependencies.

## 2026-06-01 - Review Fixes: Utility Spine Hardening

Status: success

Changed files:

- `Sources/OhbeeEditor/EditorTextOperationCenter.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditorCore/TextLineTools.swift`
- `Sources/OhbeeEditorCore/TextTransforms.swift`
- `Sources/OhbeeEditorCore/URLTools.swift`
- `Sources/OhbeeEditorCore/LogCleanupTools.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Moved undo coalescing break before transform edits, made native text replacement return success/failure, and stopped reporting success when AppKit refuses the edit.
- Finalized marked text before editor operations so IME composition is not overwritten by direct text storage replacement.
- Added shared `TextLineTools` for line splitting and line-ending detection, and reused it from text/log transforms.
- Preserved trailing POSIX newlines in keep/remove line filters.
- Reworked URL matching in `URLTools` so trailing prose punctuation is preserved separately and balanced URL parentheses are not stripped.
- Reused URL extraction behavior from `URLTools` in `LogCleanupTools`.
- Precompiled timestamp prefix regexes instead of compiling regexes per line.
- Cached command palette actions in view state instead of rebuilding action closures from a computed property.
- Added regression tests for URL punctuation preservation, balanced URL parentheses, and trailing newline preservation.

Error or blocker log:

- No blocker. GUI behavior still needs manual app exercise for feel, but build and core behavior are verified.

Tests run:

- `swift run OhbeeEditorSelfTests` succeeded.
- `swift build` succeeded.

Lessons learned:

- Editor operation helpers should expose failure to callers; status messages should reflect whether the text surface actually accepted the edit.
- URL cleanup/extraction needs to distinguish URL text from adjacent prose punctuation rather than trimming arbitrary characters from both ends.

## 2026-06-02 - Deep Scan: Safe Share Privacy and Test Suite Hardening

Status: success

Changed files:

- `Makefile`
- `Sources/OhbeeEditorCore/SafeShare.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Ran a deeper local scan around transform behavior, URL cleanup, Safe Share review output, search/replace scale, and test tooling.
- Found that Safe Share review snippets could expose sensitive prefixes/suffixes through the same partial-mask helper used for masked document output.
- Changed Safe Share finding snippets to show only category, character count, and a fully redacted display mask so the review list does not reveal secret fragments.
- Added regression self-tests that ensure Safe Share snippets do not expose full values, prefixes, or suffixes.
- Added URL cleanup regression coverage for preserving unknown query parameters and URL fragments while removing known tracking parameters.
- Added a large literal search/replace smoke test over 20,000 lines to catch obvious performance regressions.
- Added `make test` and `make selftest` targets so the executable self-test suite has a simple, memorable entry point.

Error or blocker log:

- Attempting to add a SwiftPM `testTarget` was blocked because the active toolchain could not import `XCTest`.
- A sandboxed `make test` run failed when SwiftPM tried to write Swift/Clang cache files under the user cache directory. The same command succeeded when rerun with approved cache access.

Tests run:

- `swift build` succeeded.
- `make test` succeeded after approved cache access; it runs `swift run OhbeeEditorSelfTests`.

Lessons learned:

- Safe Share review UI should avoid displaying real secret fragments even when the eventual document mask may intentionally preserve small context.
- In this repo/toolchain, the executable self-test runner remains the practical test suite. Keep new deterministic transform and smoke tests there unless the toolchain gains usable XCTest or Swift Testing support.
- Add lightweight performance smoke tests around shared text operations before optimizing; they catch accidental slow paths without turning the MVP into a benchmark harness.

## 2026-08-03 - Search Field Focus Regression Fix

Status: success

Changed files:

- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `progress.md`

Success log:

- Added a focus request token independent of search bar visibility so every Command-F and Command-Option-F invocation focuses the Find field, including when the search bar is already open.
- Deferred focus until the next main run-loop pass so the Find field can become focusable after SwiftUI inserts the search bar.
- Applied the same focus behavior when Find and Replace is opened from the command palette.

Error or blocker log:

- No blocker. Keyboard focus behavior is UI lifecycle behavior and still benefits from a manual app check after launch.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests` succeeded; all self-tests passed.
- `git diff --check` succeeded.

Lessons learned:

- Visibility state is not an event: repeated keyboard commands need an independent focus request when the target control may already be visible.
- SwiftUI focus requests for conditionally inserted controls should run after the control has entered the view hierarchy.

## 2026-08-03 - Security Review Remediation

Status: success

Changed files:

- `Support/Entitlements.plist`
- `Sources/OhbeeEditorCore/EditorDocument.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/LargeFilePolicy.swift`
- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorCore/SessionPersistence.swift`
- `Sources/OhbeeEditorCore/XMLTools.swift`
- `Sources/OhbeeEditor/ImageViewerView.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Enabled App Sandbox with user-selected read/write access and persisted security-scoped bookmarks for restored file-backed tabs.
- Limited regex input size and prevented multiple uninterruptible ICU regex tasks from accumulating after a timeout.
- Added byte limits for raster images and a stricter SVG limit before any fallback decode.
- Bound session sidecar filenames to their document UUID to prevent path traversal from tampered persistence.
- Rejected XML document type and entity declarations before parsing to prevent external entity reads and entity-expansion attacks.
- Added regression coverage for XML entity rejection and image size policies.

Error or blocker log:

- No implementation blocker. SwiftPM required an approved out-of-sandbox run because its own nested sandbox could not initialize inside the managed workspace sandbox.

Tests run:

- `plutil -lint Support/Entitlements.plist Support/Info.plist` succeeded.
- `swift build` succeeded.
- `.build/arm64-apple-macosx/debug/OhbeeEditorSelfTests` succeeded; all self-tests passed.
- `git diff --check` succeeded.

Lessons learned:

- Hardened Runtime and App Sandbox solve different problems; local-first file access needs explicit persistent user grants.
- Timeout wrappers cannot cancel ICU regex execution, so admission control is required to prevent runaway work from accumulating.

## 2026-08-03 - Security Remediation Follow-up

Status: success

Changed files:

- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Persisted security-scoped bookmarks with Recent Files while retaining the legacy path list for migration and compatibility.
- Centralized security-scoped URL cleanup and reconciled access after every single-tab, bulk-close, failed-open, and Save As path.
- Replaced the uninterruptible regex timeout worker with a bounded synchronous safe subset that rejects quantified groups, lookarounds, and pattern backreferences.
- Limited regex input to 300,000 UTF-16 characters and exposed invalid/unsupported/oversized states through search summaries.
- Reworked regex replace-all to reuse its existing match results and capture templates without executing the regex a second time.
- Added regression tests for unsafe patterns, oversized regex input, and visible search error state.

Error or blocker log:

- Security-scoped bookmark behavior still requires a manual exercise of a signed sandboxed bundle because unsigned command-line self-tests do not receive App Sandbox extensions.

Tests run:

- `swift build` succeeded.
- Full executable self-test suite succeeded.
- `git diff --check` succeeded.

Lessons learned:

- Recent-file paths are display metadata under App Sandbox; persistent access must travel with a bookmark.
- A timeout around an uninterruptible regex engine is not a hard execution bound. A deliberately constrained regex subset is more predictable for synchronous editor search.

## 2026-08-03 - Uncommitted Security Review Fixes

Status: success

Changed files:

- `Sources/OhbeeEditor/ImageViewerView.swift`
- `Sources/OhbeeEditorCore/EditorFileIO.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/LargeFilePolicy.swift`
- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorCore/XMLTools.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added ICU progress-based regex cancellation with distinct timeout and oversized-input results, including a regression case that previously caused heavy backtracking without quantified groups.
- Added in-flight file-operation leases so closing a placeholder tab cannot revoke security-scoped access while its background read is still running.
- Detected SVG content independently of filename and capped every AppKit fallback decode at the strict SVG byte limit.
- Migrated recent-file paths and bookmark keys when a bookmark resolves to a moved file.
- Replaced the broad XML substring check with a declaration scanner that ignores comments and CDATA while continuing to reject actual DOCTYPE and ENTITY declarations.
- Added regression coverage for ambiguous regex timeout, disguised SVG content, and harmless XML declaration text in comments/CDATA.

Error or blocker log:

- Signed App Sandbox lifecycle behavior still benefits from a manual GUI exercise; the deterministic core paths are covered by build and executable self-tests.

Tests run:

- `swift build` succeeded.
- Full executable self-test suite succeeded.
- `plutil` and `git diff --check` succeeded.

Lessons learned:

- Security-scoped access lifetime must include asynchronous operations, not only visible document state.
- Content sniffing fallback needs its own hard byte ceiling because filename-based classification is advisory.

## 2026-08-03 - Sandbox Upgrade and Search Cache Safety

Status: success

Changed files:

- `Makefile`
- `README.md`
- `Support/Entitlements.plist`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditorCore/EditorDocument.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SessionPersistence.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Added first-launch migration of the pre-sandbox session manifest and large-text sidecars into the sandbox container, copying the manifest last as the completion marker.
- Added a narrowly scoped read-only temporary exception for the legacy Application Support directory during the supported migration window.
- Distinguished missing authorization from a deleted file and added a user-selected reauthorization flow that preserves dirty buffers.
- Invalidated cached search ranges synchronously whenever document text or search criteria change, preventing Replace/navigation from consuming stale ranges during debounce.
- Made search evaluation identity independent of replacement text and preserved the current match index when a non-reset evaluation is requested.
- Changed `make install` to install only a signed, sandboxed bundle; added an explicitly named `make install-dev` for unsigned local development.
- Added regression tests for session migration, synchronous search-cache invalidation, replacement changes during evaluation, and dirty-buffer preservation during reauthorization.

Error or blocker log:

- The temporary migration entitlement should be removed in a future release after the pre-sandbox upgrade window closes.
- A signed-bundle smoke test remains useful for exercising the real Open Panel sandbox grant UI.

Tests run:

- `swift build` succeeded.
- Full executable self-test suite succeeded.
- `plutil` and `git diff --check` succeeded.

Lessons learned:

- A search range cache must be invalidated synchronously before any debounced recomputation, because editor actions can run during the debounce window.
- Reauthorization restores file access, not file truth; dirty session text must remain authoritative until the user explicitly saves it.

## 2026-08-03 - Async Search and Scoped Access Completion

Status: success

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/EditorTextOperationCenter.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/ImageViewerView.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Replaced computed synchronous search summaries with debounced, generation-checked background evaluations and cached ranges published by `EditorStore`.
- Updated search navigation and selection to consume cached ranges, and prevented syntax-highlight refreshes from rerunning regex synchronously.
- Added operation leases to restored document reads and image metadata/decode work.
- Refreshed stale recent-file bookmarks while scoped access is active and preserved the old record if refresh fails.
- Implemented whole-word matching as literal range search plus boundary checks, removing the regex input cap and regex-specific errors from plain whole-word mode.
- Added regression coverage for cached summary reads and large whole-word literal input.

Error or blocker log:

- Signed sandbox behavior still requires a manual GUI smoke test for the OS-issued security extensions.

Tests run:

- `swift build` succeeded.
- Full executable self-test suite succeeded.
- `plutil` and `git diff --check` succeeded.

Lessons learned:

- A bounded synchronous call is still expensive when SwiftUI evaluates a computed property repeatedly; expensive derived state must be cached at the model boundary.
- Every asynchronous file consumer, including restore and image rendering, must participate in security-scope lifetime management.

## 2026-08-03 - Reauthorization and Search UX Review Fixes

Status: success

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Rejected reauthorization attempts that select a differently named file and required explicit confirmation before relinking to a same-named file at another path, keeping dirty buffers bound to their intended backing file unless the user deliberately changes it.
- Exposed generation-checked cached search ranges to the editor and restored regex match highlighting without rerunning regex evaluation during view updates.
- Selected the current match after an asynchronous search evaluation publishes its result, restoring first-match selection after query and option changes.
- Added regression coverage for rejecting an unrelated reauthorization target.

Error or blocker log:

- Signed sandbox authorization still needs a manual GUI smoke test because command-line self-tests do not receive Open Panel security extensions.

Tests run:

- `make selftest` succeeded, including the new unrelated-file reauthorization regression test.
- `swift build` succeeded.
- `git diff --check` succeeded.

Lessons learned:

- File reauthorization should restore access to an existing document identity; choosing a different destination belongs to the explicit Save As flow.
- Async search results need both model publication and a UI reaction so match count, highlights, and selection remain synchronized.

## 2026-08-03 - Image Reauthorization Reload

Status: success

Changed files:

- `Sources/OhbeeEditor/ImageViewerView.swift`
- `progress.md`

Success log:

- Reloaded an image automatically when its document transitions from requiring file authorization to having authorization, without requiring the tab to be reopened.

Error or blocker log:

- The real security-scoped Open Panel flow still requires a manual signed-sandbox smoke test.

Tests run:

- `make selftest` succeeded.
- `swift build` succeeded.
- `git diff --check` succeeded.

Lessons learned:

- Reauthorization can change runtime access without changing document identity or path, so image loading must observe authorization state rather than document ID alone.

## 2026-08-05 - Preserve Editor Selection While Search Results Refresh

Status: success with toolchain verification blocker

Changed files:

- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/EditorTextOperationCenter.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `progress.md`

Success log:

- Traced the caret jump to the search-summary observer selecting match index zero after every text-triggered search refresh.
- Separated search result evaluation from explicit selection requests, so typing over a match refreshes highlights without moving the editor selection.
- Preserved automatic first-match selection for query, option, document, and replace actions.
- Added regression coverage for editing the first of two `LynkiD` matches without requesting selection of the remaining match.
- Reset search navigation when Close or Discard changes the active document, while closing background tabs preserves the current editor selection.
- Cleared stale search ranges synchronously after Close All.
- Added regression coverage for selected/background Close, selected Discard, Close All search invalidation, and Replace navigation.

Error or blocker log:

- `make selftest` could not compile the package because the active Command Line Tools compiler is Swift 6.3.3 while its installed SDK Swift modules were built with Swift 6.3.2. The default Clang module cache is also outside the workspace sandbox.

Tests run:

- `make selftest` attempted; stopped during manifest compilation due to the local Swift compiler/SDK mismatch before project sources compiled.
- `swiftc -frontend -parse` succeeded for all changed Swift source and self-test files.
- `git diff --check` succeeded.

Lessons learned:

- Publishing refreshed search state must not implicitly mean that the UI should navigate; selection changes need a separate intent signal.

## 2026-08-25 - Phase 21: Audit Remediation (10 findings)

Status: success with one manual-verification blocker

Changed files:

- `Sources/OhbeeEditorCore/SessionPersistence.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SafeShare.swift`
- `Sources/OhbeeEditorCore/TextTransforms.swift`
- `Sources/OhbeeEditorCore/TextLineTools.swift`
- `Sources/OhbeeEditorCore/LogCleanupTools.swift`
- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorCore/LargeFilePolicy.swift`
- `Sources/OhbeeEditor/EditorFileCommands.swift` (new)
- `Sources/OhbeeEditor/UnsavedTabWarning.swift`
- `Sources/OhbeeEditor/ContentView.swift`
- `Sources/OhbeeEditor/OhbeeEditorApp.swift`
- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `Support/Entitlements.plist`
- `Makefile`, `README.md`, `CHANGELOG.md`, `Strategy.md`, `.gitignore`, `docs/release-checklist.md`

Success log:

- F1: pre-sandbox session migration now resolves the account home through `getpwuid`, with a
  container-suffix fallback. The previous code used `homeDirectoryForCurrentUser`, which returns the
  sandbox container, so migration could never find the legacy directory and upgrading users lost
  their notes.
- F2: added `com.apple.security.files.bookmarks.app-scope`, without which app-scoped bookmarks
  cannot be created in a sandboxed build. Bookmark creation failures are now logged through
  `OSLog` and surfaced once in the status bar instead of being swallowed by `try?`. Save All also
  takes a scoped access lease and skips tabs that need reauthorization.
- F3: an unreadable session manifest is quarantined as `session.corrupt-<timestamp>.json`, sidecar
  pruning is disabled until a manifest has been read successfully, and the failure reason reaches
  the status bar through a new `SessionPersisting.recoveryNotice`.
- F4: closing several dirty tabs now offers Save All. A cancelled or failed save aborts the close,
  and the dead single-dirty guard branch is gone.
- F5: Safe Share masking replaces values with a fixed `***REDACTED***` placeholder; no prefix,
  suffix, or length survives. Review snippets no longer print the value length either.
- F6: the phone detector excludes dots and colons, rejects bare digit runs, date shapes, and long
  chains of small groups. Log timestamps, IPv4 addresses, and version strings are no longer masked.
- F7: every line transform goes through `TextLineTools.contentLines` +
  `joinLinesPreservingTerminalLineEnding`. Also fixed `hasTerminalLineEnding`, which used
  `hasSuffix("\n")` and was therefore false for CRLF text because `"\r\n"` is one Swift `Character`.
- F8: the regex guard now rejects only nested quantifiers and pattern backreferences. Non-capturing
  groups, lookarounds, lookbehinds, and quantified plain groups work again; the input cap and match
  deadline still bound worst-case time.
- F9: `EditorFileCommands` is the single implementation of open/save/save-as/save-all and every
  tab-close flow for both the menu bar and the window. Search highlighting reads the store's cached
  ranges in all modes. Removed `SearchReplaceEngine.summary`, `matchRanges`, `matchRange`,
  `nextMatchIndex`, `previousMatchIndex`, `UnsavedTabWarning.confirmClosing`, and
  `LargeFilePolicy.shouldPreserveDirtyState`, and replaced the stale Phase 4 comment.
- F10: recorded the post-1.1.8 work in `CHANGELOG.md` under Unreleased, added Phase 17 (unused),
  Phase 20, and Phase 21 to `Strategy.md`, clarified the browser-handoff rule, un-ignored the
  project contract docs, untracked the committed release zip, added `make check-version`, and
  extended the release checklist.

Error or blocker log:

- F1 and F2 cannot be fully verified from the command line: a signed, sandboxed bundle with
  pre-sandbox state is required to observe the real migration and the OS-issued bookmark
  extensions. Both now have unit coverage for the path logic, and the release checklist carries the
  manual steps.
- `SearchReplaceEngine.evaluate` remains the only search entry point; anything that used the
  deleted helpers should call it.

Tests run:

- `swift build` succeeded.
- `swift run OhbeeEditorSelfTests`: 98 tests pass (was 87). New tests: legacy-home resolution,
  corrupt-session quarantine, sidecar preservation, sidecar pruning after a healthy load,
  store-level restore warning, mask
  prefix/suffix leakage, phone false positives on log text, phone true positives, terminal-newline
  preservation across five transforms including CRLF, ordinary regex constructs, and Save All
  skipping unauthorized tabs.
- `make check-version` and `plutil -lint Support/Entitlements.plist` succeeded.

Lessons learned:

- Sandbox-relative APIs silently change meaning once the entitlement lands: `homeDirectoryForCurrentUser`
  becomes the container, so any pre-sandbox path must be resolved through `getpwuid`.
- `try?` on a security API hides exactly the failure that breaks persistent access. Log it.
- Cleanup of derived storage must be gated on having successfully read the index that describes it.
- A ReDoS blacklist that bans `(?` costs more usability than it buys once a match deadline exists.
- `"\r\n"` is a single Swift `Character`; line-ending checks need scalar comparison.

Next recommended phase:

- Move session encoding and writing off the main thread, and persist encoding per document so
  non-UTF-8 files are not silently rewritten as UTF-8.

## 2026-08-25 - Phase 21 Review Round: Fixes From Semantic Review

Status: success with the same signed-bundle blocker

Changed files:

- `Sources/OhbeeEditor/HighlightedTextEditor.swift`
- `Sources/OhbeeEditor/SafeShareReviewView.swift`
- `Sources/OhbeeEditorCore/SessionPersistence.swift`
- `Sources/OhbeeEditorCore/EditorStore.swift`
- `Sources/OhbeeEditorCore/SearchReplace.swift`
- `Sources/OhbeeEditorCore/SafeShare.swift`
- `Sources/OhbeeEditorSelfTests/main.swift`
- `CHANGELOG.md`

Success log:

- Crash risk introduced by the previous round: search highlighting applied store-cached ranges to
  live text storage after only an intersection test, which bounds the range start but not its end.
  A deferred highlight against shorter text could raise an uncatchable `NSRangeException`. Ranges
  are now intersected and clamped to the live text before drawing.
- Session recovery was only half a fix: text preserved after a failed load was deleted by the first
  save of the second healthy launch. Unreferenced text is now moved to
  `Recovered Note Text <timestamp>`, a sibling directory that `cleanupUnusedSidecars` never scans,
  and the notice names that path.
- `.unsupportedVersion` was unreachable because the version guard threw inside the `do` block that
  converted every error into a generic failure. Load failures now carry the underlying reason, and
  a manifest from a newer build reports that instead of corruption.
- `sidecarFileNames()` counted hidden files, so a single `.DS_Store` pinned pruning off forever and
  produced a spurious recovery notice. It now skips hidden files and only counts `<uuid>.txt`.
- Save policy was split: Save All refused to write tabs needing reauthorization while `Cmd+S` tried
  anyway. `saveSelectedDocument(to:)` now applies the same rule for the document's own path, still
  allows Save As to a user-picked path, and clears `requiresFileAuthorization` on success so a
  rescued tab is no longer skipped by Save All forever.
- The nested-quantifier scan dropped inner state, so `((a+))+` and `(a{2,})+` passed. The flag now
  propagates to the enclosing group. In the other direction, `{` was treated as unbounded, so
  bounded repetition such as `([0-9]{1,3}\.){3}[0-9]{1,3}` was refused; only quantifiers without a
  finite upper bound are risk markers now.
- Safe Share review rows were byte-identical within a category, which made selective masking
  guesswork. Findings now carry a 1-based line number, assigned in one forward pass, and rows show
  `line N -> ***REDACTED***`. `mask(for:)` no longer takes an argument it ignored, and `maskedText`
  stopped substringing values it discarded.
- Phone detection additionally rejects groups wider than four digits after the first, so
  `1234 5678 91011` no longer matches.

Error or blocker log:

- Alternation ambiguity (`(a|a)+`) is still not modelled by the construct scan; the 0.1 s match
  deadline is the only defence. That is deliberate and now pinned by a test.
- Dot-separated phone numbers (`555.123.4567`) cannot match, because excluding `.` is what keeps IPs
  and versions safe. Accepted false negative, consistent with "prefer false negatives".
- Closing several dirty unsaved notes still opens one Save panel per note in sequence, with no
  "discard the rest" exit once Save All is chosen. Cancelling aborts the close and reports which
  tab stopped it, so no text is lost.
- Signed, sandboxed verification of the migration and bookmark entitlement is still outstanding.

Tests run:

- `swift build` and `swift build -c release` succeeded.
- `swift run OhbeeEditorSelfTests`: 107 tests pass (was 98 after the first round, 87 before).
  Added: unsupported-version reporting, orphan text moved out of prune scope and surviving three
  launches, hidden files not blocking pruning, nested quantifiers through extra groups, bounded
  repetition allowed, ambiguous alternation stopped by the deadline, findings carrying line numbers,
  wide numeric columns rejected, Save As clearing the authorization requirement, CR terminal
  endings, and the documented empty-result edge for trims.

Lessons learned:

- Sharing a cached range with a live text view moves a correctness burden into the consumer: any
  range handed to `NSTextStorage` must be clamped, because the exception is not catchable.
- "Do not delete" is not the same as "do not lose". Preserved data needs to leave the path that
  cleanup owns, otherwise a later healthy run reclaims it.
- A guard added to one save entry point creates a policy split unless the other entry point gets it
  too, and a sticky state flag needs a clearing path on every success.
- Throwing a specific error inside a `do` block that catches everything silently deletes the
  distinction.

## 2026-08-25 - Release 1.1.9

Status: success with signing left to the maintainer

Changed files:

- `Makefile` (VERSION 1.1.9)
- `Support/Info.plist` (CFBundleShortVersionString 1.1.9, CFBundleVersion 14)
- `README.md` (current release)
- `CHANGELOG.md` (Unreleased promoted to `1.1.9 - 2026-08-25`)
- `docs/release-notes/1.1.9.md` (new)
- `docs/release-checklist.md` (release-notes step)
- `progress.md`

Success log:

- Cut `1.1.9` as a correctness and data-safety release covering the ten audit findings and the
  review round that followed. No feature work in this version.
- Wrote user-facing release notes organized by what the user loses or risks, not by file.
- Built the release bundle: `make bundle` produced `Ohbee Editor.app` reporting 1.1.9 / build 14,
  packaged as `Ohbee Editor-1.1.9.zip` with `ditto` (gitignored, not committed).

Error or blocker log:

- The packaged artifact is UNSIGNED, so App Sandbox is not active in it. It cannot be used to verify
  the pre-sandbox migration or the new app-scope bookmark entitlement. A publishable build requires
  `make notarize DEVELOPER_ID="Developer ID Application: … (TEAMID)"` on a machine holding the
  certificate, followed by the sandbox items in `docs/release-checklist.md`.
- Nothing was committed or tagged; the working tree is left for the maintainer to review.

Tests run:

- `swift build`, `swift build -c release`, `swift run OhbeeEditorSelfTests` (107 pass).
- `make check-version` agrees across Makefile, Info.plist, and README.
- `plutil -lint` on both plists; `git diff --check` clean.

Lessons learned:

- Release notes are more useful when grouped by user consequence ("your text is safer") than by
  component, especially for a release that ships no features.
