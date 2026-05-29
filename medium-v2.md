# Building Ohbee Editor: Engineering Lessons From 15 Commits That Shaped a Local-First Workbench

Subtitle: From May 16 to May 26, 2026, Ohbee Editor went through a run of small releases that touched large files, session restore, AppKit and SwiftUI boundaries, Safe Share, Finder Open With, and one product rule that kept showing up in the code: fast, local, practical, no cloud, no AI, no IDE drift.

---

Some apps do not need to become platforms.

Ohbee Editor started from a very ordinary need: a place to paste messy, temporary, sensitive text that does not deserve a project. A long log. A broken JSON blob. A URL full of tracking parameters. AI output wrapped in Markdown fences. A `.env` file that needs to be masked before sharing.

That framing matters. Ohbee Editor is not an IDE, not a VS Code clone, not a note-taking app, and not an AI writing assistant. It is a local-first text workbench for macOS:

> The editor you open when the text is messy, temporary, sensitive, or not worth creating a project for.

Between May 16 and May 26, 2026, the repo accumulated 15 meaningful commits, from `b2f22d3` to `7eedf03`. On the surface, those commits moved the app from early 1.0.x builds to release 1.1.7. Underneath, they told a better engineering story: how to keep a small app fast and trustworthy while adding practical daily-driver behavior.

This is not a changelog. These are the findings and improvements that were worth extracting from the code.

## 1. Product Constraints Are Engineering Tools

The first finding is simple: scope creep arrives quickly in a small editor.

Once you have syntax highlighting, autocomplete starts to sound reasonable. Once you can open files, a project tree feels nearby. Once you can diff tabs, Git integration is tempting. Once you can detect sensitive text, AI-powered secret detection starts whispering from the hallway.

Each idea can sound reasonable in isolation. Together, they bend the product into something else.

Ohbee Editor uses a strong set of constraints:

- no cloud sync
- no account or login
- no telemetry
- no remote config
- no online AI calls
- no language server
- no Git integration
- no terminal
- no plugin marketplace

Those constraints did not diminish the app. They made implementation decisions easier to judge:

> Does this help someone handle messy, temporary, sensitive text faster on their own machine?

For example, commit `3b6a99f` added XML tools, word frequency, tab diff, and distribution prep. Tab diff could have become the first step toward Git integration. It did not. The implementation stayed inside the product frame: compare two open tabs, generate an annotated scratch tab, and stop there. No repository model. No index. No branches. No commits.

That is a useful product pattern: take the real job to be done, not the entire ecosystem of a larger tool.

## 2. Small Apps Still Need a Large-File Policy

Commit `8419ced` was one of the most important changes in the whole run: large-file mode with async open, guardrails, and session-safe text capping.

Every text editor eventually meets a large file. If the app is not ready, one log file can expose several problems at once:

- syntax highlighting scans the full document after typing
- line-number rendering gets expensive
- search highlighting creates too many ranges
- session JSON grows because it stores the whole buffer
- file opening freezes the UI

The improvement was not just "add a size limit." It separated multiple risks:

- `LargeFilePolicy` classifies buffers.
- Large-file mode disables or reduces expensive full-document work.
- Session JSON stays lightweight.
- Later, large unsaved text is persisted through a local sidecar file in Application Support instead of being silently dropped.

Commit `f94c8e3` fixed an especially important trust issue. If the app only caps text stored in session JSON, it can protect performance while losing unsaved user text. For a local-first editor, losing text is worse than having a large session file.

The lesson:

> Large-file support should not only mean "do not crash." It should protect both responsiveness and user data.

## 3. SwiftUI Is a Good App Shell. NSTextView Is the Editing Surface.

The app could bootstrap with SwiftUI `TextEditor`, but the later commits made one thing clear: a serious macOS text surface eventually needs AppKit.

The move to `HighlightedTextEditor`, an `NSViewRepresentable` wrapping `NSTextView`, unlocked three core behaviors that shaped the rest of the app.

First, transforms could finally respect selection. Text tools now operate on selected text when possible and fall back to the full document otherwise.

Second, programmatic edits could participate in the native undo stack. Instead of mutating store text directly from menu actions, the app routes edits through the active `NSTextView` using `insertText(_:replacementRange:)`.

Third, search became visible. Find next and previous could select, scroll to, and highlight the current match instead of only updating a counter in app state.

Other editor capabilities also came from the same boundary: line numbers through `NSRulerView`, Option+Drag column selection through `selectedRanges`, smart indentation, and Finder file drag-and-drop. But the main architectural point is smaller:

> Pure transform logic belongs in core. Selection, undo, scrolling, and AppKit text semantics belong near the editor surface.

That boundary kept the core testable without pretending text editing is just string replacement.

## 4. Performance Polish Often Means Revisiting "Nice" Features

Commit `6376594`, the 1.1.4 release, focused on performance, search highlights, save flow, Safe Share, and line endings.

One useful finding: features that make the UI feel polished can quietly become expensive.

Search highlighting is a good example. Highlighting every match in a document sounds harmless until the user pastes a long log or runs a regex with thousands of matches.

The fix was not a rewrite. It was a set of boundaries:

- expose match ranges from the search engine so UI and search logic stay aligned
- cap the number of visual highlights
- highlight only the visible range for medium and large buffers
- avoid visual search scanning in large-file mode
- debounce syntax highlighting and keep it on the visible-range path

Session persistence received a similar treatment. A local-first app still should not write session JSON on every keystroke. The store now debounces edit-driven session saves and flushes pending state when the scene deactivates.

The lesson:

> Local-first does not mean write-to-disk-first after every change. Structural state and edit churn need different persistence behavior.

## 5. Line Endings Are a Small Detail With Large Trust Value

"Trim whitespace" sounds simple until it changes a CRLF file into LF.

For logs, copied Windows text, config files, and generated output, line endings are part of the user's input. If a cleanup operation changes them unexpectedly, the transform starts to feel destructive even when the visible text looks correct.

Release 1.1.4 added dominant line-ending preservation for core line transforms:

- trim whitespace
- trim trailing whitespace
- remove empty lines
- remove duplicate lines
- sort lines

The finding:

> Text transforms should not only preserve content. They should respect the texture of the text.

That is the difference between a demo tool and a daily utility. Good utilities avoid surprising the user.

## 6. Safe Share Should Be a Review Workflow, Not a "Redact Everything" Button

Safe Share fits Ohbee Editor's product frame naturally. Users paste logs, tokens, URLs, emails, phone numbers, `.env` files, and API responses. Those snippets are often shared into Slack, support tickets, GitHub issues, or AI chats.

Commit `788713d`, the 1.1.3 release, added a Safe Share review sheet:

- categorized findings
- masked snippets
- masked preview
- Copy Masked
- Apply Mask
- selected-text input with full-document fallback

Later commits refined the workflow:

- copy feedback says the document was not changed
- button help text distinguishes local pasteboard copy from document mutation
- users can select which findings to mask
- Copy Findings Summary copies category counts without copying sensitive values

The key UX/security finding:

> For sensitive text, "review before mutate" is safer than one-click magic.

`Copy Masked` is a good default because it leaves the source buffer untouched. `Apply Mask` still exists, but it goes through the shared editor operation path so the change remains undoable.

The wording also matters. The app says "Potential sensitive text found." It does not claim "All secrets detected." That is not just copywriting; it is a security boundary. A best-effort detector should not overclaim.

## 7. Offline Is Not Just the Absence of API Calls

One of the best findings came from the May 18 offline review.

Earlier builds had behaviors such as:

- Help > Check for Updates opening a website
- a clickable link in About
- automatic URL linkification
- Cmd+Click URL opening

None of these were telemetry. None uploaded user text. But they were still network-adjacent behaviors, and they made the app feel less quiet than its local-first promise.

Commit `f94c8e3` removed those handoffs:

- Check for Updates was removed
- the About site label became plain text
- Plain Text mode stopped linkifying URLs
- Cmd+Click URL opening was removed

The product lesson is sharp:

> An offline guarantee does not only live in the networking layer. It lives in the whole interaction model.

If an app is positioned as a safe place for sensitive local text, it should avoid surprising the user by pushing them toward a browser.

## 8. Finder Open With Requires Metadata and Lifecycle Engineering

Finder Open With sounds like packaging work. In practice, it reaches into the lifecycle boundary between AppKit and SwiftUI.

The relevant commits formed a small arc:

- `b2f22d3`: app bundle, drag-and-drop, multi-file open, document type declarations
- `5b3ca6c`: keep external file opens in the single main window
- `7eedf03`: stabilize Finder file opening with an AppKit delegate, early-event queue, main-queue mutation, and bounded tab-strip layout

The late hotfix came from a concrete risk: document-open events can arrive before SwiftUI content has installed its handler. If `.onOpenURL` is the only path, the app can miss an event or mutate SwiftUI state during a fragile reactivation or layout window.

The 1.1.7 fix added:

- an `NSApplicationDelegate` document-open path
- a pending-file queue for early events
- a shared deferred external-open function for both delegate events and `.onOpenURL`
- main-queue deferral before updating `EditorStore`
- window activation after external open

The tab strip also became horizontally scrollable to prevent layout from breaking when many files opened at once.

The lesson:

> On macOS, Finder integration is not just `Info.plist`. It is document metadata, app delegate callbacks, SwiftUI scene readiness, and layout guardrails working together.

## 9. Daily Comfort Features Need Product Boundaries Too

Release 1.1.6 (`2c6a385`) looked modest compared with large-file mode or Safe Share. It added:

- Reopen Closed File with `Cmd+Shift+T`
- Save All with `Cmd+Option+S`
- Copy File Path / Copy File Name from tab context menus
- Open Recent cleanup for missing files
- version/build display in About

At first glance, this is just comfort work. But the interesting decision is what the app refused to include.

Reopen Closed File only applies to file-backed tabs, capped at the 10 most recently closed files. It does not include unsaved notes.

That boundary matters. Unsaved notes already have session restore. Putting them into a browser-like reopen stack would create two overlapping models for "where did my temporary text go?" File-backed tabs and scratch notes have different lifecycles, so they should not be forced into the same recovery behavior.

Save All follows a similar rule. It saves dirty writable file-backed documents and skips unsaved notes and read-only files with status feedback. Again, the command respects the document model instead of flattening every open tab into the same category.

The finding:

> Daily-driver features are best when they are small, bounded, and aligned with the document model.

Comfort is not the same as copying familiar shortcuts everywhere. Sometimes the more trustworthy feature is the narrower one.

## 10. When the Standard Test Framework Is Unavailable, Keep Testing Anyway

The project uses SwiftPM, but the local toolchain did not expose XCTest or Swift Testing for this target. Instead of skipping tests, the repo uses `OhbeeEditorSelfTests`, a lightweight executable test target.

Across the commit run, test coverage grew around the parts where correctness matters most:

- large-file policy and session behavior
- text transforms
- literal, regex, whole-word, case-sensitive, and invalid-regex search
- XML format/minify
- word frequency
- diff generation
- Safe Share detection, review, and masking
- URL encode/decode and tracking cleanup
- CRLF preservation
- range-limited search
- recent/reopen/save-all logic

The pragmatic lesson:

> If the ideal test framework is blocked, a small test harness that actually runs is better than no tests.

The more important architectural decision was extracting `OhbeeEditorCore`. Pure tools such as `SearchReplace`, `TextTransforms`, `URLTools`, `SafeShare`, `DiffTools`, `WordFrequencyTools`, and `SQLSyntaxTokenizer` can be verified without launching the macOS UI.

## Conclusion

Ohbee Editor did not become better by adding as many features as possible. It became better by adding the right features inside the right boundaries.

The 15 commits from May 16 to May 26 show a pattern worth keeping:

- start with a crisp product promise
- treat local-first as an engineering constraint
- keep pure logic in a testable core
- let AppKit handle the text editing semantics it is good at
- put guardrails around expensive UI work
- preserve user text instead of merely processing it
- polish trust, not just features

If I had to compress the whole thing into one sentence:

> A small text editor does not need smaller ambition. It needs ambition aimed at the right problem.

That is the direction Ohbee Editor is taking: Notepad++ spirit, Mac-native taste, Ohbee privacy discipline.

Fast. Local. Practical. No account. No cloud. No nonsense.

---

## Appendix: Current Shape

After this commit run, the app has a simple but useful architecture:

- `OhbeeEditorCore`: document model, file I/O, persistence, transforms, search, Safe Share, URL/JSON/XML/diff/word tools
- `OhbeeEditor`: SwiftUI app shell plus AppKit editor bridge
- `OhbeeEditorSelfTests`: executable self-tests
- `Support/Info.plist`: bundle metadata and file type associations
- `Makefile`: build, bundle, install, and release helpers

The important boundary is not the file list. It is the split of responsibilities:

- Core logic is pure and testable.
- UI keeps AppKit semantics: selection, undo, drag-and-drop, scroll, alerts.
- Persistence remains local-only in Application Support.
- Bundle metadata integrates with macOS without forcing Ohbee Editor to become the default handler.

## Appendix: Commit Timeline

| Date | Commit | Role |
|---|---:|---|
| 2026-05-16 | `b2f22d3` | Phase 13-14, tab UX, app bundle, drag/drop, multi-file open |
| 2026-05-16 | `8419ced` | Large-file mode, async open, guardrails, session text capping |
| 2026-05-17 | `80048d7` | Font size, duplicate/move line, checksum, header fix |
| 2026-05-17 | `3b6a99f` | XML tools, word frequency, tab diff, distribution prep |
| 2026-05-17 | `575a83b` | Release 1.1.0 |
| 2026-05-17 | `f14a2e0` | C language, image viewer, readonly, whole-word search, perf/transforms |
| 2026-05-18 | `f94c8e3` | Release 1.1.2, offline trust cleanup, large session sidecar |
| 2026-05-19 | `788713d` | Safe Share review, Copy Masked, Apply Mask, release 1.1.3 |
| 2026-05-20 | `6376594` | Perf, search highlights, save-before-close, Safe Share selection, line endings |
| 2026-05-21 | `f130042` | README refresh |
| 2026-05-22 | `b9b431b` | Release 1.1.5 trust polish, QA checklist, search edge tests |
| 2026-05-22 | `c14263a` | README date/version polish |
| 2026-05-22 | `c2e6d13` | Open source hygiene: changelog, contributing, license, security |
| 2026-05-22 | `5b3ca6c` | Keep external file opens in one main window |
| 2026-05-24 | `2c6a385` | Release 1.1.6 daily comfort: reopen closed file, save all, copy path/name |
| 2026-05-26 | `7eedf03` | Release 1.1.7 hotfix: Finder/Open With stability, pending queue, scrollable tabs |
