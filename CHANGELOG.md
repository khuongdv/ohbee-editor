# Changelog

All notable user-facing changes to Ohbee Editor are tracked here.

This project follows small, practical releases. Version numbers are maintained in `Makefile`, `Support/Info.plist`, and `README.md`; run `make check-version` to confirm the three agree before tagging.

## 1.1.9 - 2026-08-25

A correctness and data-safety release. No new features. Everything here came out of a full audit of
the documentation and the source, and most of it protects text you have not saved yet.

### Fixed — data safety

- Fixed pre-sandbox session migration, which resolved the legacy Application Support path against the sandbox container and therefore never ran. Upgrading from an unsandboxed build no longer drops restored notes.
- Fixed silent loss of unsaved notes when the session file could not be read. The unreadable manifest is now quarantined as `session.corrupt-<timestamp>.json`, note text that no readable manifest references is moved to a `Recovered Note Text <timestamp>` folder that cleanup never touches, and both paths appear in the status bar.
- Stopped pruning session text files before the app has successfully read the manifest that references them.
- A session written by a newer version of Ohbee Editor is now reported as an unsupported format instead of as a corrupt file.
- Closing several tabs with unsaved changes now offers Save All instead of only Close Without Saving or Cancel.
- Save All now takes the same scoped file-access lease as Save, skips tabs whose file access must be restored first, and reports them.
- Save now refuses to write back to a path whose file access was revoked, pointing at Save As instead, and a successful save clears the tab's pending-access state so Save All stops skipping it.

### Fixed — privacy

- Safe Share masking no longer keeps the first and last characters of a detected value. Masked output and Copy Masked now use a fixed `***REDACTED***` placeholder that reveals neither content nor length.
- Tightened phone-number detection so log timestamps, IP addresses, version strings, bare order numbers, dates, and wide numeric columns are no longer masked as phone numbers.
- Safe Share review rows now show the line of each finding, so two findings of the same category can be told apart before choosing what to mask.

### Fixed — text tools

- Sort Lines, Trim Whitespace, Trim Trailing Spaces, Remove Empty Lines, and Remove Duplicate Lines now preserve a terminal newline instead of moving it to the top of the document or dropping it.
- Fixed terminal line-ending detection for CRLF text, which also affected the log cleanup tools.

### Fixed — search

- Regex mode no longer rejects ordinary patterns. Non-capturing groups, lookarounds, and quantified plain groups such as `(ab)+` work again; nested quantifiers such as `(a+)+` and pattern backreferences remain refused, and the input cap plus match deadline still bound matching time.
- Search highlighting now reads the same published match ranges as the match counter for every search mode, so highlights and counts cannot disagree, and each range is clamped to the live text before drawing.
- Regex mode now allows bounded repetition such as `([0-9]{1,3}\.){3}[0-9]{1,3}`, which matters for log inspection, while still refusing nested unbounded quantifiers including `((a+))+`.

### Added — security

- Added the `com.apple.security.files.bookmarks.app-scope` entitlement, without which the sandboxed build could not create the bookmarks that keep file-backed tabs, Open Recent, and Reopen Closed File working across launches. Bookmark failures are now logged and surfaced instead of silently ignored.
- Earlier post-`1.1.8` security work now recorded here: ReDoS and TOCTOU mitigations, owner-only session file permissions, App Sandbox adoption for `make install`, asynchronous search evaluation, and detection of tabs whose original file was deleted.

### Changed

- File open, save, and tab-close commands share one implementation between the menu bar and the in-window controls.
- Removed unused search-engine and policy helpers that no longer had a caller.

### Release

- Bumped app version to 1.1.9.
- Bumped bundle build number to 14.
- Added `make check-version` so `Makefile`, `Support/Info.plist`, and `README.md` cannot drift apart.

## 1.1.8 - 2026-06-15

### Added

- Added a command palette for quick access to common local editor actions.
- Added selection-aware text operations so supported transforms act on selected text first, with full-document fallback.
- Added log cleanup tools for deterministic local cleanup of messy pasted logs.
- Added a Wrap Text preference and menu toggle for switching between wrapped reading and horizontal scrolling.
- Added file metadata to the Document Info popover.

### Fixed

- Fixed Safe Share review snippets so they no longer expose sensitive prefixes or suffixes.
- Fixed SQL `--` line comment highlighting for pasted text with `CR` and `CRLF` line endings.
- Fixed editor tab rendering so one tab visually matches four monospaced spaces.
- Hardened editor UI crash paths around compare, image viewer, Safe Share, session restore, and tab/document state.
- Fixed Wrap Text relayout so disabling wrap restores horizontal scrolling for long lines.

### Improved

- Improved shared editor operation handling for selected text, native undo, and status reporting.
- Improved URL cleanup and extraction behavior around embedded URLs, unknown parameters, fragments, and punctuation.
- Added convenience `make test` and `make selftest` targets for the executable self-test suite.
- Added regression and smoke coverage for Safe Share snippets, URL cleanup, large search/replace, SQL line comments, and file metadata.

### Release

- Bumped app version to 1.1.8.
- Bumped bundle build number to 13.

## 1.1.7 - 2026-05-26

### Fixed

- Fixed Finder/Open With file-opening reliability by handling macOS document-open events through an AppKit application delegate.
- Deferred external file opens onto the main queue before updating editor state.

### Improved

- Made the tab strip horizontally scrollable so opening many files keeps toolbar layout bounded.

### Release

- Bumped app version to 1.1.7.
- Bumped bundle build number to 12.

## 1.1.6 - 2026-05-24

### Added

- Added Reopen Closed File with `Cmd+Shift+T`, limited to the 10 most recently closed file-backed tabs.
- Added Save All with `Cmd+Option+S` for dirty file-backed tabs.
- Added Copy File Path and Copy File Name actions for file-backed tab context menus.
- Added Copy Summary to Safe Share Review so findings category counts can be copied without copying sensitive values.
- Added app version and build number to the About window.

### Improved

- Improved Open Recent by disabling missing files and adding Remove Missing Recent Files.
- Kept Reopen Closed File scoped to local files only; unsaved notes are not kept in the reopen stack.

### Release

- Bumped app version to 1.1.6.
- Bumped bundle build number to 11.

## 1.1.5 - 2026-05-22

### Added

- Added a release QA checklist for manual pre-release testing.
- Added search/replace edge-case coverage for empty queries, invalid regex, regex captures, whole-word matching, and case-sensitive search.

### Improved

- Improved Safe Share Review copy feedback.
- Copy Masked now clearly communicates that masked text is copied to the local pasteboard and the document remains unchanged.
- Added clearer button help text for Copy Masked and Apply Mask.

### Release

- Bumped app version to 1.1.5.
- Bumped bundle build number to 10.

## 1.1.4 - 2026-05-20

### Added

- Added visible search highlighting with capped match drawing for responsiveness.
- Added selective Safe Share masking from the review sheet.
- Added read-only file polish with a direct Save As affordance.

### Improved

- Improved syntax highlighting performance for medium and large buffers.
- Debounced local session persistence during rapid typing and flushes pending state on scene deactivation.
- Added save-before-close flow for single dirty tabs.
- Preserved dominant line endings for core line transforms.
- Improved URL tracking cleanup for embedded URLs inside prose.

## 1.1.3 - 2026-05-19

### Added

- Added Safe Share review sheet with categorized findings, masked preview, Copy Masked, and Apply Mask.
- Added conservative JSON-style secret detection.

### Improved

- Kept Safe Share wording cautious and best-effort.
- Review works on selected text with full-document fallback.

## 1.1.2 - 2026-05-18

### Improved

- Improved session handling for large buffers and file-backed documents.
- Refined large-file policy behavior around persisted session text.

## 1.1.1 - 2026-05-17

### Added

- Added C language metadata/highlighting support.
- Added local image viewer for common image formats.
- Added whole-word search support.

### Improved

- Improved readonly file behavior and editor performance guardrails.

## 1.1.0 - 2026-05-17

### Release

- First `1.1.x` release line.

## 1.0.1 - 2026-05-15

### Added

- Initial public MVP release.
- Multi-tab local text editor with scratch notes, local session restore, open/save, search/replace, text transforms, JSON/URL tools, and Safe Share detection.
