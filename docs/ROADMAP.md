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

Paired with Luna Phase 5E.

- define the first real Moth source-buffer protocol and implementation;
- establish typed offsets and conversions;
- move production editor state out of Luna proof models;
- support two independent views over one shared buffer;
- define document dirty state and revision ownership;
- define Moth find-session policy behind Luna search-panel presentation;
- add headless transaction, selection, and view-state tests.

Exit condition:

> Two Moth editor views can share one buffer while retaining independent selection,
> caret, and viewport state, with no Luna dependency in MothTextCore.

## M2 — First Luna-rendered Moth application slice

- attach platform entry points to supported Luna hosts;
- open and save a plain-text document;
- render one Moth editor view through Luna;
- add one product-owned theme resource;
- connect commands, menu descriptions, status information, and find UI;
- retain native platform services only behind Luna host contracts.

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

**Status:** implemented in this iteration, pending local graphical smoke test.

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
