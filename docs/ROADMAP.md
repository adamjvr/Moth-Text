# Moth Text Roadmap

## M0 — Repository and Luna integration foundation

**Status: complete.**

- conventional `Sources/` and `Tests/` layout;
- Moth-owned target names;
- pinned `Dependencies/Luna-UI` Git submodule;
- preserved IPC/plugin-host proof;
- documented product/framework boundary.

## M1 — Buffer/view and document ownership

**Status: M1.1 complete.**

Delivered:

- typed UTF-8 offsets and ranges;
- one authoritative Moth source buffer;
- immutable snapshots and primitive transactions;
- independent caret, selection, preferred-column, and viewport state per view;
- Moth-owned find/replace policy behind Luna presentation contracts;
- tests proving two views can share one buffer without sharing presentation.

## M2 — First file-backed Luna-rendered application slice

### M2.1 — File workflow

**Status: complete.**

- UTF-8/BOM open, atomic Save, and Save As;
- document path, encoding, and known disk state;
- external-change detection;
- dirty-close Save / Don't Save / Cancel policy;
- Linux dialog helpers outside Luna;
- Moth-owned theme and graphical status projection.

### M2.2A — Pane-bound editor views

**Status: complete.**

- two Luna pane leaves mapped to independent Moth editor views;
- width-correct soft wrapping and clipping;
- independent logical-line and visual-row viewport state;
- active-pane routing and Ctrl+Tab traversal;
- divider resize/reflow.

### Convergence C1A — Cursor and divider interaction

**Status: complete.**

- product-neutral Luna cursor intent;
- native SDL cursor mapping;
- forgiving divider geometry and hover/drag feedback;
- captured divider drag ownership.

### Convergence C1B — Mouse selection

**Status: complete.**

- click and Shift-click;
- captured character drag;
- Unicode-aware word and logical-line selection;
- wrapped-row selection and edge autoscroll;
- independent pane-local selection over one document.

### Convergence C2 — Document-owned undo/redo

**Status: implemented in this revision.**

Delivered:

- `MothHistoryStateID` separated from monotonic `MothBufferRevision`;
- document-local `MothDocumentHistory` with bounded undo/redo stacks;
- forward and inverse edit replay;
- deterministic grouping for typing, Backspace, and Delete;
- explicit grouping boundaries for navigation, pointer actions, pane changes,
  Save, newline, commands, Undo/Redo, and capture loss;
- redo invalidation with fresh branch state identities;
- origin-view caret, selection, and preferred-column checkpoints;
- edit-based coordinate transformation for non-origin views;
- direction-preserving selection synchronization;
- atomic selection replacement and history-aware Find Replace/Replace All;
- exact saved-history checkpoints that can become clean through Undo or Redo;
- Save/Save As preserving history while sealing the current typing group;
- Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z, and Ctrl+Y application routing;
- status diagnostics for revision, history state, dirty state, and group counts;
- architecture tests preventing application/workspace raw mutation bypass.

C2 exit condition:

> Undo and Redo operate on the shared Moth document regardless of active pane,
> preserve independent viewports and active-pane ownership, restore the
> originating view's editor state, keep revisions monotonic, and report clean
> exactly when logical history returns to the saved checkpoint.

### M2.2B — Command and visible find convergence

**Next.**

- typed Moth command IDs and command availability;
- one command path shared by keyboard, menus, command palette, and context menus;
- visible Luna find/replace panel backed by history-aware Moth mutation;
- Undo/Redo menu and palette presentation;
- fuller keyboard-navigation command coverage;
- external-change reload/conflict presentation;
- recent-file/session groundwork.

## M3 — Workspace fundamentals

- document sheets and editor groups;
- real tabs and dirty-state policy;
- split placement and cloned views;
- close/save prompts;
- session persistence starter.

## M4 — Sublime interaction core

- configurable key bindings and context evaluation;
- command palette and Goto Anything providers;
- multiple cursors and occurrence selection;
- line operations, indentation, bracket matching, and navigation;
- settings-layer precedence.

## M5 — Syntax and ecosystem foundations

- syntax definitions and incremental parsing;
- color schemes and theme import adapters;
- snippets and completion providers;
- project indexing;
- static package resources;
- plugin runtime/API work only after command, document, and workspace contracts
  stabilize.

## Long-term direction

Later phases add navigation, visible find/replace depth, syntax/theme/snippet
compatibility, real workspaces, advanced Sublime-style editing, compatibility
importers, packages, plugins, build systems, and Moth-specific tools beyond the
Sublime baseline.

Compatibility formats translate into native Moth/Luna structures; they do not
become the internal architecture.
