# Moth Command Authority

M2.2B1 establishes one product-owned command path for Moth Text.

```text
keyboard shortcut ─┐
menu row ──────────┤
command palette ───┼──> LunaCommandID ──> Moth availability ──> Moth handler
programmatic test ─┘
```

Luna supplies reusable command descriptors, key matching, availability projection,
menu mechanics, and quick-panel mechanics. Moth owns command IDs, product state,
file/editor policy, and execution.

## Stable identifiers

The first command vocabulary is:

```text
moth.file.new
moth.file.open
moth.file.save
moth.file.saveAs
moth.edit.undo
moth.edit.redo
moth.edit.selectAll
moth.find.show
moth.view.nextPane
moth.view.previousPane
moth.tools.commandPalette
```

These strings are persistence-facing API. Future keymaps, menus, packages,
plugins, and Sublime-compatibility adapters may refer to them. Renaming one
requires an explicit compatibility migration.

## Command context

Every invocation carries a `LunaCommandContext` containing:

- the initiating source, such as `keyboard`, `menu`, `palette`, or `programmatic`;
- the current Moth document identity;
- the focused product surface;
- the active Luna pane identity projected as context metadata.

The context identifies the target. It does not move Moth documents, views, or
workspace objects into Luna.

## Availability

Availability is resolved from current product state immediately before display or
execution:

- Save is enabled for dirty documents and untitled documents that require Save As;
- Undo and Redo follow the document-owned history stacks;
- Select All is disabled for an empty document;
- Find is visible but disabled until M2.2B2 installs the visible find panel;
- unknown commands are rejected without mutating product state.

Disabled keyboard bindings are still consumed. This prevents shortcut letters,
such as Ctrl/Cmd+F, from arriving later as committed editor text. Luna quick-panel
filtering keeps matching disabled commands searchable, so the palette can retain
focus and display Moth's disabled reason instead of hiding the command.

## New File lifecycle

Before M3, Moth owns one current document. `moth.file.new` therefore performs a
safe document replacement:

1. end the current history coalescing run;
2. when dirty, request Save / Don't Save / Cancel;
3. complete any required Save or Save As before replacement;
4. install a new clean untitled document;
5. create fresh document, buffer, history, and editor-view identities;
6. reset the active pane to the primary view;
7. preserve the existing pane tree and split geometry.

Cancel or failed Save As preserves the complete current document and view state.
This replacement behavior remains intentionally transitional through C2.2. M3A
replaces it with document sheets: `moth.file.new` will append and activate an
untitled sheet, and close commands will target one stable sheet without replacing
or discarding unrelated documents.

## Surface law

A command surface may choose presentation and supply context, but it must not
implement product behavior independently.

```text
menu item != save implementation
shortcut != undo implementation
palette row != new-file implementation
```

All surfaces resolve and execute the same registered Moth command. The command
palette owns committed text only while open; Escape dismisses it and returns the
next committed text input to the active editor view.

## Validation

Focused command validation:

```bash
swift test --filter MothCommandSystemTests
```

Complete paired validation:

```bash
./scripts/validate-paired-iteration.sh
```

The graphical acceptance gate must additionally verify menus, disabled rows,
command-palette filtering, focus return, and the dirty New File decision paths.


## C2.2 command interaction note

C2.2 does not add new product commands, but it strengthens the surfaces on which
commands operate. Keyboard navigation and editing now reveal the caret through
exact shaped geometry, and wheel/scrollbar interaction mutates pane-local viewport
state outside the command dispatcher. Page Up/Page Down remain editor input
operations until a later configurable key-binding phase promotes them to stable
commands.

After M3A, Ctrl/Cmd+Tab becomes document-tab traversal. Pane traversal will receive
a distinct command and binding so the command vocabulary does not overload one
shortcut with two product meanings.


## C2.3 input batching note

Command events are hard committed-text coalescing barriers. A sequence such as
text, shortcut, text is delivered to Moth in that order and can never become one
text transaction around the command. The same rule applies to navigation,
pointer, resize, capture-loss, and focus-related host events. Disabled shortcuts
remain consumed by the command authority and retain the existing one-shot text
suppression path.
