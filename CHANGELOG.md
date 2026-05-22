# Changelog

All notable user-facing changes to Ohbee Editor are tracked here.

This project follows small, practical releases. Version numbers are currently maintained manually in `Makefile`, `Support/Info.plist`, and `README.md`.

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
