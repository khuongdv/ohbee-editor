# Contributing to Ohbee Editor

Thanks for taking a look. Ohbee Editor is a local-first macOS text workbench for messy, temporary, sensitive text.

The project is intentionally small. Contributions are welcome when they preserve the product shape: fast, local, practical, tab-based, no account, no cloud.

## Product Boundaries

Please keep contributions aligned with these rules:

- No telemetry, analytics, remote config, account/login, cloud sync, or background upload.
- No online AI calls or network-dependent editing features.
- No plugin marketplace, terminal, Git client, LSP, debugger, or full IDE behavior.
- Prefer practical text cleanup, inspection, privacy, and local file workflows.
- Keep the editor usable immediately without creating a project or workspace.
- Preserve the tab-based workbench model: many temporary notes and files should be easy to keep open, switch between, and close safely.

## Good Contributions

Good first areas:

- Text transform edge-case tests.
- Search/replace bug fixes.
- Safe Share false-positive reductions.
- Release/QA/documentation improvements.
- Small UI polish that keeps the editor uncluttered.
- Performance guardrails for larger text buffers.

Larger features should start as a GitHub issue or discussion before implementation.

## Development

Requirements:

- macOS 13 Ventura or later.
- Swift Package Manager through Xcode Command Line Tools or Xcode.

Run the app during development:

```bash
make dev
```

Run self-tests:

```bash
swift run OhbeeEditorSelfTests
```

Build a release app bundle:

```bash
make bundle
```

## Testing Expectations

Before opening a pull request:

- Run `swift run OhbeeEditorSelfTests`.
- Run `swift build`.
- Add or update self-tests for pure transformation/search/Safe Share logic.
- Manually test UI behavior when touching AppKit or SwiftUI views.
- Check `docs/release-checklist.md` when preparing a release.

If you cannot run a test locally, mention that clearly in the pull request.

## Code Style

- Keep logic small and explicit.
- Prefer pure functions in `Sources/OhbeeEditorCore`.
- Keep UI behavior in `Sources/OhbeeEditor`.
- Avoid heavy dependencies.
- Avoid broad rewrites unless they are discussed first.
- Preserve user text unless the user explicitly runs a transform or save action.

## Pull Requests

A useful pull request includes:

- What changed.
- Why it fits Ohbee Editor.
- Tests run.
- Screenshots or short screen recordings for UI changes.
- Known limitations or follow-up work.
