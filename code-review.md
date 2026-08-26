# Ohbee Editor — Code Review Checklist

Use this checklist when reviewing changes in Ohbee Editor.

Ohbee Editor is a lightweight offline macOS text workbench. The main review principle is:

> Improve the editor without turning it into an IDE.

---

## 1. Product Philosophy

Before reviewing implementation details, check whether the change still fits the product direction.

- [ ] The change supports the core use case: open text, inspect text, edit text, transform text, and leave.
- [ ] The change keeps the app lightweight and fast.
- [ ] The change does not redesign the app unless explicitly requested.
- [ ] The change does not introduce IDE-like complexity without strong justification.
- [ ] The change does not add cloud, account, telemetry, analytics, or network behavior.
- [ ] The change works offline.
- [ ] The feature is useful for everyday developer text workflows: logs, JSON, YAML, Markdown, SQL, `.env`, config files, scratch notes.
- [ ] The feature does not make Plain Text mode behave like a programming editor.

---

## 2. Scope Control

Reject or question changes that are larger than the requested task.

- [ ] No unrelated refactors.
- [ ] No broad architecture rewrite unless the task explicitly requires it.
- [ ] No unnecessary new abstractions.
- [ ] No hidden behavior changes in existing features.
- [ ] No large UI redesign for a small feature.
- [ ] No new dependency unless absolutely necessary.
- [ ] No speculative feature work.
- [ ] No “while we are here” changes.
- [ ] Changed files are explainable and directly related to the task.

Good changes should be local, reviewable, and boring.

---

## 3. macOS / SwiftUI Native Feel

Ohbee Editor should feel like a small native macOS utility.

- [ ] UI follows macOS conventions where possible.
- [ ] Menu items are placed in expected locations.
- [ ] Menu naming follows macOS style.
- [ ] Keyboard shortcuts do not conflict with standard macOS shortcuts.
- [ ] Alerts, popovers, panels, and overlays feel native and lightweight.
- [ ] Toolbar and status bar remain compact.
- [ ] No custom UI component is added when a native SwiftUI/AppKit component is sufficient.
- [ ] Dark mode appearance remains consistent.
- [ ] Light mode, if supported, is not broken.
- [ ] Focus behavior feels natural after opening files, switching tabs, closing overlays, or using menu commands.

---

## 4. Editor Behavior

The editor is the core of the app. Any change here needs extra care.

- [ ] Typing remains smooth.
- [ ] Cursor movement remains correct.
- [ ] Text selection remains correct.
- [ ] Copy, cut, paste, undo, redo still work.
- [ ] Find and replace still work.
- [ ] Scrolling remains smooth.
- [ ] Large files do not become noticeably slower.
- [ ] Existing syntax highlighting still works.
- [ ] Plain Text mode is not highlighted.
- [ ] Switching syntax modes does not corrupt content.
- [ ] Opening files does not unexpectedly modify content.
- [ ] Saving files preserves expected encoding and line endings as much as current behavior allows.
- [ ] Scratch notes still persist across restarts.
- [ ] Closing tabs behaves as expected.
- [ ] Dragging files into the window still works.

---

## 5. Line Numbers / Row Numbers

For the line number feature, check carefully that it improves readability without making the editor feel heavy.

- [ ] Line numbers start at 1.
- [ ] Line numbers update when text changes.
- [ ] Empty documents still show line 1.
- [ ] Line numbers align vertically with editor rows.
- [ ] Line numbers remain aligned after scrolling.
- [ ] Long documents do not cause layout lag.
- [ ] Gutter width adapts reasonably for 1-digit, 2-digit, 3-digit, and larger line counts.
- [ ] Gutter uses muted color and does not visually dominate the editor.
- [ ] Gutter spacing feels compact.
- [ ] Line numbers do not interfere with text selection.
- [ ] Line numbers are not copied as part of editor text.
- [ ] Line numbers work for scratch notes and opened files.
- [ ] Wrapped lines are handled intentionally.
- [ ] Horizontal scrolling, if supported, does not break line number layout.
- [ ] Plain Text mode remains valid and usable.
- [ ] If there is a View → Show Line Numbers menu item, it works consistently.
- [ ] If the setting is persisted, persistence is simple and reliable.
- [ ] If the setting is not persisted, the default behavior is intentional and documented in the PR summary.

Important review question:

> Did we add line numbers, or did we accidentally start building an IDE?

---

## 6. Vertical Selection

Vertical Selection should remain a focused power-user feature, not a full multi-cursor system.

- [ ] Existing Option + Drag behavior still works.
- [ ] Normal drag selection still works.
- [ ] Option + Drag does not interfere with standard macOS text selection unexpectedly.
- [ ] Vertical selection is visually clear.
- [ ] Vertical selection handles variable line lengths safely.
- [ ] Vertical selection handles empty lines safely.
- [ ] Vertical selection handles tabs and spaces predictably.
- [ ] Copying vertical selection produces expected text.
- [ ] Replacing vertical selection does not corrupt surrounding text.
- [ ] Undo works after vertical selection edits.
- [ ] The feature works in Plain Text and structured text modes.
- [ ] The feature does not require internet, plugins, or external libraries.
- [ ] No complex multi-cursor editing is introduced unless explicitly requested.
- [ ] Edge cases are handled gracefully rather than crashing.

For the menu item:

- [ ] Edit → Vertical Selection exists.
- [ ] The menu item improves discoverability.
- [ ] If the feature is gesture-only, the menu item explains “Hold Option and drag to make a vertical selection.”
- [ ] The menu item does not create a fake mode unless a real mode already exists.
- [ ] The menu item does not break existing Edit menu actions.
- [ ] The menu item does not conflict with Copy, Paste, Select All, Find, or Replace.

---

## 7. Status Bar

The status bar should remain useful but not become a control center.

- [ ] Status bar controls are compact.
- [ ] Existing text tools still work.
- [ ] Disabled actions are visibly disabled.
- [ ] Disabled actions have understandable reason, tooltip, or behavior.
- [ ] Safe Share is visually discoverable.
- [ ] Status messages are short and useful.
- [ ] Status messages do not block editing.
- [ ] Status messages do not persist longer than useful.
- [ ] The status bar does not become crowded.
- [ ] New status bar controls are grouped logically.
- [ ] Security-related actions, such as Safe Share, are not hidden among unrelated tools.

---

## 8. Info Button / Text Statistics Overlay

For the `(i)` status bar button and statistics panel:

- [ ] The `(i)` button is visible but subtle.
- [ ] The button placement makes sense in the status bar.
- [ ] Clicking the button opens a lightweight popover or overlay.
- [ ] Clicking outside dismisses the overlay.
- [ ] Clicking the button again dismisses the overlay.
- [ ] Escape dismisses the overlay if supported naturally.
- [ ] The overlay does not steal focus unnecessarily.
- [ ] The overlay does not block normal editing after dismissal.
- [ ] The overlay style matches the current dark UI.
- [ ] Statistics are accurate for the current tab.
- [ ] Statistics update when switching tabs.
- [ ] Statistics update when text changes.
- [ ] Empty documents are handled correctly.
- [ ] Very large text does not cause expensive recomputation on every keystroke.
- [ ] Word count handles normal whitespace reasonably.
- [ ] Line count handles trailing newline correctly.
- [ ] Character count is clearly defined.
- [ ] Character count excluding whitespace is clearly defined.
- [ ] Selected character count is only shown if selection data is reliable.
- [ ] File size is only shown if available and correct.
- [ ] Syntax mode / file type is shown only if already available.
- [ ] No external dependency is added for simple statistics.

Suggested stats:

- Lines
- Words
- Characters
- Characters excluding whitespace
- Selected characters, if reliable
- Syntax mode
- File size, if available

Avoid turning this into a full document analytics panel.

---

## 9. Syntax Highlighting

Syntax highlighting should help reading structured text without becoming a full language server.

- [ ] Plain Text mode does not highlight anything.
- [ ] JSON highlighting still works.
- [ ] YAML highlighting still works.
- [ ] Markdown highlighting still works.
- [ ] HTML/XML highlighting still works if supported.
- [ ] CSS highlighting still works.
- [ ] SQL highlighting still works.
- [ ] Shell highlighting still works.
- [ ] Swift/Python/JavaScript highlighting still works if supported.
- [ ] Highlighting is based on file extension or explicit user selection.
- [ ] User override from the language menu still works.
- [ ] Language menu behavior is not changed unless required.
- [ ] Bad or malformed structured text does not crash the editor.
- [ ] Highlighting remains lightweight.
- [ ] No network-based syntax engine is used.
- [ ] No heavy language-server behavior is introduced.
- [ ] Theme colors remain readable in dark mode.
- [ ] Highlight colors do not reduce readability.

Review principle:

> Highlight enough to read. Do not build Xcode.

---

## 10. Indentation / Newline Behavior

Structured text should feel comfortable, but the editor should not become an IDE.

- [ ] Pressing Enter in Plain Text behaves naturally.
- [ ] Plain Text does not auto-indent unexpectedly.
- [ ] In structured text modes, Enter preserves the previous line’s indentation where appropriate.
- [ ] JSON, YAML, HTML, XML, CSS, Markdown, and SQL indentation behavior is reasonable.
- [ ] Auto-indent does not aggressively reformat user text.
- [ ] Auto-indent does not change existing lines unexpectedly.
- [ ] Tabs and spaces are handled consistently with current app behavior.
- [ ] Pasted text is not unexpectedly reformatted.
- [ ] Undo works after newline / indentation behavior.
- [ ] The implementation avoids complex IDE-like formatting rules.
- [ ] No formatter runs automatically unless the user explicitly chooses a format action.

Good behavior:

> Help the next line start in the right place.

Bad behavior:

> Pretend to be a full code formatter.

---

## 11. Text Tools

Text tools are core to the product. They must be predictable and safe.

- [ ] Sort Lines works.
- [ ] Remove Duplicates works.
- [ ] Remove Empty Lines works.
- [ ] Trim Whitespace works.
- [ ] Join Lines works.
- [ ] Case conversion works.
- [ ] JSON Format works for valid JSON.
- [ ] JSON Minify works for valid JSON.
- [ ] Invalid JSON produces a helpful error and does not destroy content.
- [ ] URL tools work only when applicable.
- [ ] Clean AI Output works as expected.
- [ ] Text tools operate on selection if that is the current behavior.
- [ ] Text tools operate on full document only when expected.
- [ ] Undo works after every text tool operation.
- [ ] Text tools do not silently lose content.
- [ ] Text tools do not require internet.
- [ ] Text tools do not send content anywhere.
- [ ] Disabled text tools have clear behavior or explanation.

Review question:

> Would I trust this tool on a real `.env`, JSON response, SQL dump, or production log?

---

## 12. Safe Share / Sensitive Text Detection

Safe Share is a trust feature. Review it carefully.

- [ ] Detection still works for bearer tokens.
- [ ] Detection still works for JWTs.
- [ ] Detection still works for API keys.
- [ ] Detection still works for `.env` secrets.
- [ ] Detection still works for emails.
- [ ] Detection still works for phone numbers if supported.
- [ ] Masking behavior is predictable.
- [ ] Masking does not reveal too much of the secret.
- [ ] Masking does not accidentally delete unrelated content.
- [ ] Masking can be undone.
- [ ] False positives are tolerable and explainable.
- [ ] False negatives are considered for common secret formats.
- [ ] Detection and masking run locally.
- [ ] No sensitive text is logged.
- [ ] No sensitive text is sent to any service.
- [ ] No telemetry is added around sensitive detection.
- [ ] The UI language is clear: detect before sharing, mask before copying.

Important:

> Safe Share must increase trust. It must never create a new privacy risk.

---

## 13. Files, Tabs, and Scratch Notes

- [ ] Opening a file creates a tab.
- [ ] Creating a scratch note creates a tab.
- [ ] Dragging a file into the window creates a tab.
- [ ] Closing a tab works.
- [ ] Switching tabs preserves content.
- [ ] Scratch notes persist across app restarts.
- [ ] Scratch notes do not require the user to manually manage files.
- [ ] Opened files keep their file identity.
- [ ] Saving an opened file writes to the expected location.
- [ ] Save As behavior, if present, still works.
- [ ] Unsaved changes are handled safely.
- [ ] Tab titles are clear.
- [ ] Duplicate names are handled reasonably.
- [ ] File extension detection still works.
- [ ] Large numbers of tabs remain usable.
- [ ] Session restoration does not restore stale or corrupted state.

---

## 14. Menus and Commands

Menus are part of the macOS experience. Keep them clean.

- [ ] New commands are placed in the correct menu.
- [ ] Edit menu contains editing-related actions only.
- [ ] View menu contains visual toggles.
- [ ] Text Tools menu contains text transformations.
- [ ] File menu contains open/save/export-related actions.
- [ ] Menu item names are short and clear.
- [ ] Keyboard shortcuts are conventional.
- [ ] Gesture-only features are explained clearly if exposed in the menu.
- [ ] Disabled menu items are disabled for a clear reason.
- [ ] Menu commands work on the active tab.
- [ ] Menu commands update when switching tabs.
- [ ] Menu commands do not affect hidden or inactive tabs.
- [ ] Existing menu items are not accidentally removed or renamed.

---

## 15. Performance

Ohbee Editor should stay fast.

- [ ] App launch time is not noticeably worse.
- [ ] Opening small files is instant or near-instant.
- [ ] Opening medium text files remains smooth.
- [ ] Typing latency remains low.
- [ ] Scrolling remains smooth.
- [ ] Syntax highlighting does not block the main thread noticeably.
- [ ] Text statistics do not recompute expensively on every keystroke for large files.
- [ ] Line number rendering does not degrade performance on large documents.
- [ ] Safe Share detection does not freeze the UI on normal files.
- [ ] No background polling is added unnecessarily.
- [ ] No network calls are added.
- [ ] No heavy runtime is introduced.
- [ ] Memory usage remains reasonable.

When reviewing performance-sensitive code, ask:

> Does this run on every keystroke?  
> Does it need to?

---

## 16. Privacy and Offline Guarantees

This app’s trust model is simple: user text stays on the machine.

- [ ] No internet permission is introduced.
- [ ] No analytics are added.
- [ ] No telemetry is added.
- [ ] No crash reporter is added without explicit discussion.
- [ ] No remote configuration is added.
- [ ] No cloud sync is added.
- [ ] No account system is added.
- [ ] No external API call is added.
- [ ] No clipboard content is logged.
- [ ] No file content is logged.
- [ ] No detected secrets are logged.
- [ ] No user-identifying data is collected.
- [ ] No hidden background process is added.
- [ ] Any local persistence is minimal and explainable.

---

## 17. Error Handling

Errors should be useful without being noisy.

- [ ] Invalid JSON shows a helpful error.
- [ ] File open errors are handled gracefully.
- [ ] File save errors are handled gracefully.
- [ ] Permission errors are understandable.
- [ ] Encoding errors do not crash the app.
- [ ] Large file issues, if any, fail gracefully.
- [ ] Text tool errors do not destroy content.
- [ ] Safe Share detection failure does not expose content.
- [ ] Alerts are short and actionable.
- [ ] Errors do not spam the user.
- [ ] Debug logs do not contain user text or secrets.

---

## 18. Accessibility and Usability

Even small tools should be comfortable.

- [ ] Buttons have labels or tooltips.
- [ ] Icon-only buttons are understandable.
- [ ] Keyboard navigation is not broken.
- [ ] Focus states are visible enough.
- [ ] Text contrast is acceptable.
- [ ] Line numbers have sufficient contrast but remain subtle.
- [ ] Popovers are dismissible.
- [ ] Menu commands are discoverable.
- [ ] Important features are not hidden behind unclear icons.
- [ ] The UI remains usable on smaller Mac screens.
- [ ] Font size and line height remain readable.
- [ ] Status messages are understandable.

---

## 19. Build, Tests, and Verification

Before approving:

- [ ] Project builds successfully.
- [ ] Existing tests pass, if available.
- [ ] New tests are added where useful.
- [ ] Manual testing was done for affected features.
- [ ] No warnings were introduced unnecessarily.
- [ ] No generated files are committed accidentally.
- [ ] No local machine paths are committed.
- [ ] No secrets are committed.
- [ ] Git diff is focused and reviewable.

Minimum manual test pass:

- [ ] Create scratch note.
- [ ] Type text.
- [ ] Switch syntax mode.
- [ ] Open a file.
- [ ] Save a file.
- [ ] Use at least one text tool.
- [ ] Use Safe Share detect/mask.
- [ ] Use Find/Replace.
- [ ] Switch tabs.
- [ ] Restart app and verify scratch note persistence.
- [ ] Verify Plain Text mode still behaves normally.

---

## 20. Review Heuristics

Use these questions when unsure.

### Is it lightweight?

If the implementation feels heavy, ask whether there is a smaller approach.

### Is it local?

If the change spreads across many files, ask why.

### Is it discoverable?

If users need to read source code to find the feature, improve menu, tooltip, or status text.

### Is it safe?

If the feature touches user text, secrets, files, clipboard, or save behavior, review twice.

### Is it boring?

For this app, boring is usually good.

### Is it still a workbench?

The app should help developers handle everyday text quickly. It should not become a full IDE, note-taking system, cloud document app, or AI workspace.

---

## 21. Red Flags

Pause review if you see any of these:

- [ ] New network dependency.
- [ ] New telemetry or analytics.
- [ ] New account/login concept.
- [ ] New cloud sync behavior.
- [ ] New heavy third-party framework.
- [ ] Large unrelated refactor.
- [ ] New IDE-like feature not requested.
- [ ] Plain Text mode starts behaving like code mode.
- [ ] Text tools silently mutate content in surprising ways.
- [ ] Safe Share logs or exposes sensitive text.
- [ ] Menu behavior changes without reason.
- [ ] Performance-sensitive code runs on every keystroke without need.
- [ ] UI becomes significantly more crowded.
- [ ] App philosophy becomes unclear.

---

## 22. Approval Standard

Approve when:

- [ ] The change solves the requested problem.
- [ ] The implementation is small and understandable.
- [ ] The UI remains lightweight.
- [ ] Existing editor behavior is preserved.
- [ ] Privacy and offline guarantees are preserved.
- [ ] Performance remains acceptable.
- [ ] The feature feels native to Ohbee Editor.
- [ ] The diff is easy to review.
- [ ] The reviewer can explain the change in one or two sentences.

Final review question:

> Would this make me reach for Ohbee Editor more often without making it feel heavier?

If yes, the change probably belongs.