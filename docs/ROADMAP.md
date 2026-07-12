# Moth Text Roadmap

## M0 — Repository and Luna integration foundation

**Status: implemented in this repository revision.**

- adopt conventional `Sources/` and `Tests/` layout;
- rename IPC and plugin targets with Moth-owned names;
- add `MothTextCore`, `MothEditor`, `MothWorkspace`, and `MothApplication`;
- consume the pinned Luna checkout through `Dependencies/Luna-UI`;
- remove SwiftUI/GTK application-shell assumptions;
- preserve the working Unix-domain-socket IPC proof;
- add bootstrap, test, submodule-verification, and Luna-update scripts;
- establish buffer identity separately from editor-view identity;
- document the product/framework boundary.

## M1 — Buffer/view and document ownership

**Status: M1.1 implemented and validated against Luna Phase 5E.2.**

Paired with Luna Phase 5E.

- define the first real Moth source-buffer protocol and implementation;
- establish typed offsets and conversions;
- move production editor state out of Luna proof models;
- support two independent views over one shared buffer;
- define document dirty state and revision ownership;
- define Moth find-session policy behind Luna search-panel presentation;
- add headless transaction, selection, and view-state tests.

Delivered in M1.1:

- typed UTF-8 offsets, ranges, and monotonic buffer revisions;
- a Moth-owned source-buffer protocol and thread-safe in-memory implementation;
- insert, replace, backward-delete, and forward-delete transactions;
- saved-revision and dirty-state ownership in the buffer;
- independent caret, selection, preferred-column, and viewport state per view;
- literal and regular-expression find/replace policy in MothEditor;
- neutral Luna snapshot, view-projection, and find-session adapters in MothApplication;
- a Luna-rendered shell backed by real Moth text rather than placeholder bars;
- tests proving two views retain independent state while observing one shared buffer.

Exit condition achieved:

> Two Moth editor views can share one buffer while retaining independent selection,
> caret, and viewport state, with no Luna dependency in MothTextCore.

## M2 — First file-backed Luna-rendered Moth application slice

**Status: M2.2A implemented and validated against Luna Phase 5F.2A.**

Delivered in M2.1:

- Moth-owned file-document identity, URL, filename, UTF-8/BOM encoding, and known disk state;
- local UTF-8 open, atomic save, Save As identity migration, and BOM preservation;
- external-change detection through a Moth-owned filesystem controller;
- Open, Save, Save As, and unsaved-changes decisions through Luna host dialog contracts;
- native-window termination veto so Cancel genuinely keeps a dirty document open;
- command-line file opening and Linux zenity/yad/kdialog adapters outside Luna;
- a Moth-owned theme supplied through Luna's public `LunaTheme` product;
- filename/path/encoding/revision/dirty state rendered in the live shell;
- one file document retaining one authoritative buffer and two independent editor views;
- regression coverage for file lifecycle, dialog routing, dirty-close policy, and shared-view ownership.

Delivered in M2.2A:

- two Luna pane leaves mapped to Moth's primary and secondary editor views;
- independent caret, selection, logical-line scroll, and wrapped visual-row scroll state;
- width-correct soft wrapping and clipping inside each pane's content bounds;
- active-pane pointer and edit routing plus Ctrl+Tab pane traversal;
- divider resizing that reflows both views without changing document ownership;
- regression coverage for independent wrapping, pane activation, divider reflow, and focus traversal.

M2.2B remains:

- undo/redo transaction grouping;
- visible find/replace panel integration;
- fuller command/menu routing and keyboard shortcuts;
- external-change response and reload/conflict presentation;
- recent-file/session groundwork.

M2.2A exit condition achieved:

> Two Moth editor views can share one real file document while clipping, wrapping,
> scrolling, focusing, and editing independently inside Luna-owned pane geometry.

## M3 — Workspace fundamentals

Paired with Luna tab-overflow and split-container work.

- document sheets and editor groups;
- tabs and dirty-state policy;
- split placement and active-pane routing;
- cloned views;
- close/save prompts;
- session persistence starter.

## M4 — Sublime interaction core

- command registry and context evaluation;
- configurable key bindings;
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
- plugin runtime/API work only after command, document, and workspace contracts stabilize.

## Phase M0.1 — MPL-2.0 License Alignment

**Status:** complete.

Moth Text now uses the Mozilla Public License 2.0 (`MPL-2.0`), matching Luna-UI. The previous project license has been replaced with the complete MPL-2.0 text, and concise SPDX identifiers have been added to the Swift package manifest, source files, tests, and repository scripts.

This keeps the flagship application and its UI framework under the same file-level copyleft licensing baseline while preserving their independent repositories and histories.

---

## Phase M0.2 — Real Luna Application Shell

**Status:** complete in the preceding iteration.

MothTextLinux now consumes LunaHostSDL's public application runner instead of
printing a bootstrap message and returning immediately.

Deliverables:

- real resizable `Moth Text` window;
- Luna-owned Linux host lifecycle and event loop;
- Moth-owned platform-neutral shell scene;
- custom-rendered menu, tab, sidebar, editor, minimap, caret, and status regions;
- pointer interaction that visibly changes the accent state;
- process lifetime tied to the window lifetime;
- plugin IPC retained as a separate optional smoke test;
- headless tests for resize invalidation, interaction state, and shell pixels.

Definition of done:

- `swift run MothTextLinux` opens a visible window;
- the shell stays active until the window is closed;
- resizing redraws the entire shell correctly;
- clicking changes the visible accent state;
- closing the window returns control to the terminal with exit code zero;
- automated Moth tests pass against the pinned Luna revision.
