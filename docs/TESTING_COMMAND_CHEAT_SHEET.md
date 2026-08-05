# Moth Text Testing and Command Cheat Sheet

This is the quick-reference sheet for manual Moth Text testing on Linux.

## Launching Moth Text

Launch the installed application:

```bash
moth-text
```

Open a file with the installed application:

```bash
moth-text --open /path/to/file.txt
```

Launch the SwiftPM development build:

```bash
cd "$HOME/GitHub/Moth-Text"
swift run MothTextLinux
```

Open a file with the development build:

```bash
cd "$HOME/GitHub/Moth-Text"
swift run MothTextLinux --open /path/to/file.txt
```

## File and Tab Commands

| Command | Linux shortcut | Expected behavior |
|---|---:|---|
| New File / New Tab | `Ctrl+N` or `Ctrl+T` | Append and activate a fresh untitled document tab |
| Open File | `Ctrl+O` | Open a file in a new tab, or activate it if already open |
| Save | `Ctrl+S` | Save the active document |
| Save As | `Ctrl+Shift+S` | Save the active document under another path |
| Close Tab | `Ctrl+W` | Close only the active tab; dirty tabs request Save, Don't Save, or Cancel |
| Next Tab | `Ctrl+Tab` or `Ctrl+PageDown` | Activate the next document tab |
| Previous Tab | `Ctrl+Shift+Tab` or `Ctrl+PageUp` | Activate the previous document tab |
| Select Tab 1–9 | `Alt+1` through `Alt+9` | Activate a document tab by position |

## Pane Commands

| Command | Linux shortcut | Expected behavior |
|---|---:|---|
| Next Pane | `Ctrl+Alt+Tab` | Move editing focus to the next editor pane |
| Previous Pane | `Ctrl+Alt+Shift+Tab` | Move editing focus to the previous editor pane |

Document tabs and editor panes are separate:

- `Ctrl+Tab` changes documents.
- `Ctrl+Alt+Tab` changes views of the active document.

## Editing Commands

| Command | Linux shortcut | Expected behavior |
|---|---:|---|
| Undo | `Ctrl+Z` | Undo in the active document only |
| Redo | `Ctrl+Shift+Z` or `Ctrl+Y` | Redo in the active document only |
| Cut | `Ctrl+X` | Copy then remove the focused selection as one Undo group |
| Copy | `Ctrl+C` | Copy the focused editor or Find-field selection |
| Paste | `Ctrl+V` | Paste system plain text into the focused surface as one editor Undo group |
| Select All | `Ctrl+A` | Select the complete active document |
| Command Palette | `Ctrl+Shift+P` | Open Moth's searchable command surface |
| Find / Replace | `Ctrl+F` | Open the sheet-aware Find/Replace panel |
| Find Next | `Enter` in panel, `Ctrl+G`, or `F3` | Select and reveal the next match |
| Find Previous | `Shift+Enter` in panel, `Ctrl+Shift+G`, or `Shift+F3` | Select and reveal the previous match |

## Pointer and Workspace Checks

- Click a document tab to activate it.
- Click a tab close control to close only that document.
- Click an **Open Files** sidebar row to activate the matching tab.
- Drag the pane divider and confirm both panes reflow.
- Click or drag inside either pane and confirm selection remains pane-local.
- Scroll the pane beneath the pointer without changing the active editing pane.
- Create enough tabs to expose overflow behavior, then narrow the window.
- Confirm the active tab remains visible while traversing overflowed tabs.

## Focused Automated Tests

Run the M3A document-sheet tests:

```bash
cd "$HOME/GitHub/Moth-Text"
swift test --filter MothM3ADocumentSheetTests
```

Run command-routing tests:

```bash
swift test --filter MothCommandSystemTests
```

Run history tests:

```bash
swift test --filter MothApplicationHistoryTests
```

Run Unicode and dirty-indicator rendering tests:

```bash
swift test --filter MothUnicodeRenderingTests
```

Run every paired Luna/Moth validation gate:

```bash
./scripts/validate-paired-iteration.sh
```

Run the M3A integration verifier:

```bash
./scripts/verify-m3a-integration.sh
```

Run the plugin-host IPC smoke test:

```bash
./scripts/smoke-test-plugin-host.sh
```

## Generate Large Test Files

Generate a 5,000-line fixture:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path("/tmp/moth-5000-lines.txt")
path.write_text(
    "".join(f"{i:05d}  Moth Text 5K manual test line\n" for i in range(1, 5001)),
    encoding="utf-8",
)
print(path)
PY
```

Generate a 50,000-line fixture:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path("/tmp/moth-50000-lines.txt")
path.write_text(
    "".join(f"{i:05d}  Moth Text 50K manual test line\n" for i in range(1, 50001)),
    encoding="utf-8",
)
print(path)
PY
```

Launch them:

```bash
moth-text --open /tmp/moth-5000-lines.txt
moth-text --open /tmp/moth-50000-lines.txt
```

## M3A Manual Acceptance

### Tabs and document ownership

1. Open the 5,000-line file.
2. Create several tabs with `Ctrl+T`.
3. Type different text in at least two tabs.
4. Switch with `Ctrl+Tab` and `Ctrl+Shift+Tab`.
5. Confirm each tab restores its own text, undo history, caret, selection, and viewport.
6. Open the same canonical file twice and confirm Moth activates the existing tab.
7. Make one tab dirty and close it.
8. Test **Cancel**, then test **Don't Save**.
9. Confirm only the targeted tab is affected.
10. Close the final tab and confirm Moth creates a fresh untitled tab.

### Sidebar and overflow

1. Click several **Open Files** rows.
2. Confirm each row activates the matching document tab.
3. Create enough tabs to trigger overflow.
4. Narrow and resize the window.
5. Confirm the active tab stays visible and close targets remain correct.

### Large-document regression

1. Open the 50,000-line fixture.
2. Scroll normally and rapidly.
3. Type, delete, undo, and redo.
4. Use arrows, Page Up, Page Down, Home, and End.
5. Drag the scrollbar thumb.
6. Resize the window.
7. Create a small second tab.
8. Switch repeatedly between the small tab and the 50K tab.
9. Confirm the 50K caret and viewport restore correctly.
10. Confirm no lockup or noticeable input delay.

## Linux Icon Checks

The installed launcher should reference the custom icon:

```bash
grep -E '^(Name|Exec|Icon|StartupWMClass)='   "$HOME/.local/share/applications/io.github.adamjvr.MothText.desktop"
```

Confirm the installed icon exists:

```bash
ls -lh   "$HOME/.local/share/icons/hicolor/256x256/apps/io.github.adamjvr.MothText.png"
```

Refresh desktop and icon caches:

```bash
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
```

A terminal-launched SDL test window may temporarily receive the desktop environment's
generic application icon even when the installed launcher icon is correct. Treat that
as a Linux application-identity/window-icon integration issue, not as loss of the
checked-in icon asset.

## Repository State Checks

```bash
printf '\n=== MOTH ===\n'
git -C "$HOME/GitHub/Moth-Text" branch --show-current
git -C "$HOME/GitHub/Moth-Text" log -1 --oneline
git -C "$HOME/GitHub/Moth-Text" status --short

printf '\n=== LUNA ===\n'
git -C "$HOME/GitHub/Luna-UI" branch --show-current
git -C "$HOME/GitHub/Luna-UI" log -1 --oneline
git -C "$HOME/GitHub/Luna-UI" status --short
```

Never use `git reset --hard` or `git clean` during an unfinished paired iteration.

## M2.2B2 Clipboard and Find/Replace Acceptance

1. Copy multiline Unicode text from Moth into another desktop application.
2. Copy external text and paste it into both Moth editor panes.
3. Confirm Cut and Paste each reverse with exactly one Undo.
4. Confirm a failed clipboard write leaves the selected document text intact.
5. Open several tabs and verify clipboard edits affect only the active sheet.
6. Open Find/Replace with `Ctrl+F`; test field caret movement and Shift-selection.
7. Copy, Cut, Paste, and Select All inside both panel fields without mutating the editor.
8. Test Next, Previous, Replace, and Replace All; Replace All must undo once.
9. Enable regex, enter an invalid expression, and confirm visible non-destructive feedback.
10. Switch tabs while the panel is visible and confirm independent queries/options restore.
11. Repeat ordinary, 5K, and 50K launch checks and confirm the custom Moth icon.
