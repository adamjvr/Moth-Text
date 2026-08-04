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

**Status: complete and accepted.**

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

### Convergence C2.1 — Unicode text painting and visible-state correction

**Status: complete and graphically validated.**

Delivered:

- optional Luna `LunaTextRender` dependency in MothApplication;
- shaped and cached Unicode painting for editor rows and user-facing shell text;
- monospaced shaped advance projected into Luna text-view metrics;
- explicit visible fallback for missing glyphs;
- geometric dirty and active-pane indicators;
- regressions that fail when accented text paints as an advanced blank;
- source guards preventing the Unicode bullet-marker regression.

Exit condition:

> Precomposed and decomposed accents, common UI punctuation, Greek, Cyrillic,
> filenames, and status messages paint visibly in the graphical Moth shell while
> the accepted 74-test C2.1 baseline remains green, plugin-host IPC passes, and
> dirty/active indicators stay visible.

Deferred:

- Ctrl/Cmd+N: completed in M2.2B1 through the unified command runtime;
- real tabs, multiple open documents, clickable Open Files rows, and folders: M3;
- complete bidi/script segmentation and multi-font fallback: later LunaText work.

### Stabilization S1 — Paired CI, diagnostics, and grapheme boundaries

**Status: complete and accepted.**

- Ubuntu CI for Luna and Moth;
- recursive submodule checkout plus exact staged-gitlink verification;
- full SwiftPM build/test and plugin-host IPC validation;
- headless application/render smoke mode;
- visible and logged Unicode diagnostic fallback state;
- extended-grapheme horizontal navigation and deletion;
- regression tests for decomposed accents across editor, history, and shell input;
- 86 accepted tests after the 12 stabilization regressions were added.

S1 exit condition:

> A fresh Ubuntu runner builds and tests both repositories from their recorded
> commits, Moth verifies the exact Luna gitlink, the headless Unicode render smoke
> passes without fallback, and grapheme editing regressions remain green.

### M2.2B1 — Unified command authority and New File

**Status: complete and accepted.**

- stable namespaced Moth command IDs;
- Luna command runtime reused without moving product policy into Luna;
- one availability/execution route for keyboard, menu, command palette, and tests;
- real menu-bar and dropdown interaction;
- searchable command palette;
- New File with Save / Don't Save / Cancel protection;
- Open, Save, Save As, Undo, Redo, Select All, and pane traversal convergence;
- visible disabled Find command reserving the M2.2B2 route;
- 17 command regressions and 103 expected total tests.

M2.2B1 exit condition:

> Every implemented product command has one stable ID, one availability rule, and
> one execution handler regardless of initiating surface. New File cannot discard
> dirty content without an explicit decision, and failed/cancelled Save As leaves
> the current document intact.

### Convergence C2.2 — Exact text geometry and vertical scrolling

**Status: implemented in this revision.**

- stable shaped grapheme insertion positions retained in 26.6 coordinates;
- one row geometry for soft wrap, caret, selection, hit testing, and painting;
- source/rendered UTF-8 mapping for tab expansion;
- caret painted after glyphs;
- platform-neutral scroll events and SDL wheel/trackpad translation;
- pane-local precise-delta accumulation;
- wheel targeting by hovered pane without active-pane theft;
- scrollbar lane paging, captured thumb dragging, and viewport clamping;
- eight new Moth regressions and an expected 111-test total.

C2.2 exit condition:

> Rapid long-line input cannot produce cumulative caret drift; caret, selection,
> hit testing, wrapping, and painted text agree on shaped insertion positions.
> Wheel, precise touchpad, Page Up/Page Down, scrollbar paging, and thumb dragging
> update only the intended pane and never exceed legal wrapped visual rows.

### Convergence C2.3 — Input-to-pixel latency and demo restoration

**Status: partially retained; scheduling policy rejected after graphical acceptance.**

- bounded host polling by raw event count and elapsed monotonic time;
- rejected behavior: presentation between arbitrary raw polling batches;
- committed-text authority for printable input;
- adjacent text-event coalescing with semantic ordering barriers;
- input-to-present, polling, merge, and shaping-cache diagnostics;
- bounded LRU shaped-layout retention;
- restored default Luna kitchen-sink demo and 340-row scroll corpus;
- four regressions and a 115-test baseline retained.

C2.3 exit condition:

> Sustained rapid typing and normal OS key repeat cannot build a growing visible
> backlog. Text and caret appear in the same presented state, semantic events are
> never reordered or dropped, and the layout cache cannot retain unbounded edited
> line prefixes.

### Convergence C2.4 — Interactive runtime and presentation scheduling

**Status: ordinary interaction accepted; large-document scalability failed.**

- persistent Luna semantic scheduler across raw acquisition passes;
- pointer/text coalescing retained across passes;
- clicks, commands, navigation, resize, focus/capture loss, and quit as barriers;
- text dispatch on source idle, byte threshold, or monotonic latency deadline;
- raw polling limits explicitly forbidden from defining frame boundaries;
- VSync/presentation ownership separated from input acquisition;
- generation-based Moth shaped-layout cache without linear hit-time order maintenance;
- nine focused Luna scheduler regressions and one new Moth cache regression;
- expected Moth total: 116 tests.

C2.4 exit condition:

> Native clicks, menus, commands, navigation, text repeat, scrolling, resizing, and
> dialogs remain prompt under input backlogs. No raw acquisition boundary creates
> an intermediate frame, no semantic event is reordered, and stable cache hits do
> not perform linear maintenance.

Native result: this condition passed for the ordinary Moth graphical shell. It
does not claim large-document acceptance. The generated roughly 500-line document
froze or became unusably slow, and the Luna animated demos remained sluggish.

### Convergence C2.5 — Scalable presentation and bounded damage

C2.5A–E established reusable presentation, wrap/index primitives, bounded damage,
and semantic dispatch fairness. The first C2.5E native matrix rejected total-document
scaling and exposed that the Moth checkpoint had not committed the intended live
shell source.

### Convergence C2.5F — Virtualized document presentation

**Historical corrective phase; completed by the accepted C2.5J baseline.**

- Luna shapes visible rows plus bounded overscan through an opt-in revision context.
- Moth builds one projection per document revision and shares it across both panes
  and minimap metadata.
- Width, line, segment, and revision caches have explicit retention limits.
- The minimap performs height-bounded sampling and no text shaping.
- The real Moth shell consumes bounded damage and the exact Luna C2.5F gitlink.

Exit requires usable native 50-, 500-, 5,000-, and 50,000-line fixtures with no
force quit and operation counts that remain viewport bounded.

### M3A — Document sheets and real tabs

**Current product phase — unblocked by accepted C2.5J.**

- Moth-owned `MothDocumentSheetID` and document-sheet collection;
- one active sheet projected to the existing editor panes;
- Ctrl/Cmd+N appending a new untitled sheet instead of replacing the current one;
- Open reusing an already-open canonical file or appending a new file-backed sheet;
- real tab projection, activation, close targeting, and per-sheet dirty prompts;
- Ctrl/Cmd+Tab reassigned from pane traversal to document-tab traversal;
- Open Files projection from the same sheet collection.

M3A exit condition:

> Multiple clean or dirty documents remain open simultaneously, every visible tab
> targets one stable Moth sheet, and New File never discards or replaces another
> document. Closing a dirty tab affects only its targeted sheet.

### M2.2B2 — Visible Find/Replace convergence

**Immediately after M3A.**

- visible Luna find/replace panel backed by history-aware Moth mutation;
- Find Next and Find Previous command routing;
- Replace and Replace All command routing;
- Replace All retained as one Undo group;
- overlay focus ownership and Escape return to the active editor pane;
- keyboard, menu, palette, and panel actions sharing the M2.2B1 command authority;
- commands targeting the active document sheet introduced by M3A.

### M2.2B3 — External-change and session groundwork

- external-change reload/conflict presentation;
- recent-file model;
- first session metadata schema before broader M3 editor-group and restoration work.

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

## M3A execution update after C2.5J {#M3A_EXECUTION_UPDATE_AFTER_C25J}

C2.5G–J closed the measured large-document blocker: runtime attribution, lazy line
metadata, event-scoped then persistent interaction snapshots, and narrower damage
were accepted with usable 5,000- and 50,000-line native fixtures. Performance is
now a regression gate rather than the purpose of every iteration.

The execution order remains:

1. **M3A — Document sheets and real tabs** (current);
2. **M2.2B2 — Visible Find/Replace**;
3. **M2.2B3 — External-change and session groundwork**;
4. remaining M3 workspace/editor-group/session phases;
5. M4 interaction core;
6. M5 syntax and ecosystem foundations.

Moth product milestones drive work. Luna receives supporting changes only when the
current Moth feature demonstrates a generic requirement or a confirmed framework
problem.
