# Ohbee Editor Release QA Checklist

Use this before tagging a release. Keep the pass focused on local-first editor trust: text should stay on device, user buffers should not be lost, and destructive edits should be explicit or undoable.

## Build and Package

- [ ] Run `swift build`.
- [ ] Run `swift run OhbeeEditorSelfTests`.
- [ ] Run `make bundle` when preparing a user-facing build.
- [ ] Confirm `Ohbee Editor.app` launches from Finder.
- [ ] Confirm the About window shows the intended app version.

## First Launch and Editing

- [ ] Launch with no prior session and confirm one editable note appears.
- [ ] Paste multi-line plain text immediately after launch.
- [ ] Type, undo, redo, select text, copy, cut, and paste.
- [ ] Create new notes until ordinary tab interactions feel responsive.
- [ ] Confirm the 50-tab cap still prevents runaway new-tab creation.

## Session Restore

- [ ] Create at least two unsaved notes, quit, relaunch, and confirm text and selected tab restore.
- [ ] Edit a file-backed tab without saving, quit, relaunch, and confirm unsaved text and dirty state restore.
- [ ] Open a clean file-backed tab, quit, relaunch, and confirm the app does not treat it as dirty.
- [ ] Confirm large-file tabs do not make relaunch noticeably slow.

## File Open and Save

- [ ] Open one local text file through File > Open.
- [ ] Open multiple local text files in one picker action.
- [ ] Drag a text file from Finder into the editor and confirm it opens as a tab.
- [ ] Save edits to a file-backed tab only after explicit Save.
- [ ] Save an unsaved note through Save As.
- [ ] Try closing a dirty single tab and confirm Save, Close Without Saving, and Cancel behave correctly.
- [ ] Try closing multiple dirty tabs and confirm the warning does not silently write files.

## Search and Replace

- [ ] Search current tab only; verify next/previous selection and scroll-to-match.
- [ ] Toggle case-sensitive search and verify counts change correctly.
- [ ] Toggle whole-word search and verify partial words are excluded.
- [ ] Try an invalid regex and confirm the UI reports an invalid pattern without mutating text.
- [ ] Replace Current and Replace All, then undo.
- [ ] Search a medium or large file and confirm visible highlights do not freeze the editor.

## Text Tools

- [ ] Apply each line tool to selected text and full-document fallback.
- [ ] Apply case conversion tools to selected text and full-document fallback.
- [ ] Run Clean AI Output on fenced Markdown and excessive blank lines.
- [ ] Confirm CRLF-heavy text keeps dominant line endings after line transforms.
- [ ] Run JSON format/minify/validate on valid and invalid JSON.
- [ ] Run XML format/minify on valid XML and confirm invalid XML reports an error.
- [ ] Run URL encode/decode and embedded tracking-parameter cleanup.

## Safe Share

- [ ] Review Safe Share with selected text and with full-document fallback.
- [ ] Confirm cautious wording: "Potential sensitive text found." or "No obvious sensitive patterns found."
- [ ] Select and deselect individual findings.
- [ ] Click Copy Masked and confirm the pasteboard receives masked text while the document remains unchanged.
- [ ] Click Apply Mask and confirm the document changes through native undo.
- [ ] Confirm obvious normal support text does not produce noisy false positives.

## Image Viewer

- [ ] Open a PNG, JPEG, or GIF file and confirm it renders without a text editor.
- [ ] Confirm image tabs are read-only (no edit or save actions available).
- [ ] Confirm closing an image tab does not prompt for unsaved changes.

## Editor UX

- [ ] Toggle line numbers and confirm the setting persists.
- [ ] Move the cursor and confirm the gutter highlights the correct line.
- [ ] Change font size with Cmd+=, Cmd+-, and Cmd+0.
- [ ] Duplicate and move the current line, then undo.
- [ ] Cmd+Click a URL and confirm the editor does not open the system browser.
- [ ] Use Option+Drag vertical selection, copy, cut, delete, and Escape.
- [ ] Compare two tabs and confirm a new diff note is created.
- [ ] Open the Help sheet and confirm shortcuts match the app.

## Finder and Distribution

- [ ] Register or launch the bundled app and confirm Finder Open With includes Ohbee Editor for text-like files.
- [ ] Open a file via Finder Open With and confirm it appears in a tab.
- [ ] Confirm recent files appear under File > Open Recent.
- [ ] Confirm no cloud, telemetry, account, remote AI, or network-dependent feature was added.
