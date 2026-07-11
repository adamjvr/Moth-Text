# Moth Text Architecture

## Product and framework relationship

Moth Text is the flagship application for Luna UI, but the repositories have
separate responsibilities and independent histories.

```text
Moth Text
  product behavior, source buffers, editor commands, workspaces, projects,
  settings, packages, compatibility, sessions, and language services

Luna UI
  rendering, platform hosts, input, accessibility, themes, general widgets,
  and optional reusable document/developer-tool components
```

The governing rule is:

> Luna owns reusable editor anatomy. Moth owns editor meaning, workflow,
> compatibility, and product policy.

## Repository relationship

`Dependencies/Luna-UI` is the pinned Luna checkout consumed by SwiftPM through a
local package path. The canonical Git repository should track this path as a
submodule so every Moth commit records the exact Luna revision it expects.

```text
Moth-Text/
  Dependencies/Luna-UI/   pinned Git submodule
  Sources/                Moth product modules
  Tests/                  headless product tests
  Resources/              Moth themes, keymaps, menus, settings, syntaxes
```

Luna never depends on Moth.

## Initial target graph

```text
MothTextMac -----------+
                       +--> MothApplication --> selected Luna products
MothTextLinux ---------+          |
                                  +--> MothWorkspace
                                  +--> MothEditor
                                  +--> MothTextCore
                                  +--> MothIPC

MothPluginHost ------------------> MothIPC

MothTextCore
  imports Foundation only; no Luna or platform UI framework
```

## Buffer and view law

A source buffer is not a visible editor view. M1.1 implements this distinction
as an executable contract rather than only an identity model.

```text
MothInMemorySourceBuffer
  text + revision + saved revision
  +-- MothEditorViewState A
  |     caret + selection + preferred column + viewport
  +-- MothEditorViewState B
        independent caret + selection + preferred column + viewport
```

Edits are Moth-owned transactions applied to the shared buffer. Each view observes
the new revision and clamps its own presentation state without inheriting the
other view's caret, selection, preferred column, or scroll position.

This distinction exists before split panes, cloned views, transient sheets, or
durable workspace sessions are implemented.

## Luna adapter boundary

`MothApplication` is the only layer that projects production Moth state into Luna's
product-neutral document/view contracts.

```text
MothTextCore source buffer
        |
        +--> MothLunaTextStorageAdapter --> LunaTextStorageSnapshot

MothEditorViewState
        |
        +--> MothLunaViewProjection ----> LunaDocumentViewPresentationState

MothFindSession
        |
        +--> MothLunaFindPanelSession ---> LunaFindPanelSession
```

The adapters expose immutable snapshots and presentation state. They do not move
source-buffer ownership, transactions, dirty-state policy, or replacement policy
into Luna. `MothTextCore` and `MothEditor` remain usable headlessly.

## Module ownership

### MothTextCore

Owns pure editor-domain primitives:

- source-buffer identity and authoritative storage;
- typed UTF-8 text coordinates and ranges;
- immutable source-buffer snapshots;
- edit transactions and revision tracking;
- saved-revision and dirty-state ownership.

Undo/redo history and cursor-set policy remain subsequent Moth work.

It must remain headless and should not import Luna.

### MothEditor

Owns source-editor semantics:

- independent editor-view state and revision synchronization;
- command-oriented insert/delete/replace behavior;
- literal and regular-expression find/replace sessions over Moth buffers;
- future multiple-cursor operations and transaction grouping;
- completion insertion policy;
- syntax and diagnostic interpretation;
- decorations mapped into Luna presentation primitives.

### MothWorkspace

Owns product workspace policy:

- windows and editor groups;
- sheets and tabs;
- active-view targeting;
- transient and pinned behavior;
- split placement;
- sessions and restoration;
- projects and folders.

Luna may supply generic tab strips and split containers, but it does not decide
what closing, pinning, previewing, or activating a Moth sheet means.

### MothApplication

Composes the product and Luna. Platform executables remain thin launch boundaries.
They must not construct Moth's interior using SwiftUI, AppKit widgets, GTK widgets,
Qt, Electron, or a web hierarchy.

### MothIPC and MothPluginHost

Preserve the existing out-of-process service boundary. Plugin APIs should not be
stabilized until buffers, commands, documents, and workspace ownership are stable.

## Dependency laws

1. Luna does not import Moth.
2. MothTextCore does not import Luna, SDL, AppKit, Metal, GTK, or plugin runtimes.
3. Platform executable targets do not own product state.
4. Moth application code consumes Luna through public Swift products.
5. Moth themes and compatibility files remain in Moth resources.
6. A reusable capability may be promoted into an optional Luna component only
   when its API is product-neutral and useful to another plausible application.

## Licensing Baseline

Moth Text and Luna-UI are independently maintained repositories licensed under the Mozilla Public License 2.0 (`MPL-2.0`). The Luna-UI submodule retains its own license notices and history. Moth source files remain covered by the Moth repository's MPL-2.0 license; importing or linking Luna through SwiftPM does not merge the two repositories or their ownership boundaries.
