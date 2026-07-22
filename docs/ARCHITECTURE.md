# Moth Text Architecture

## Product and framework relationship

Moth Text is the flagship application for Luna UI, but the repositories have
separate responsibilities and independent histories.

```text
Moth Text
  product behavior, source buffers, history, editor commands, workspaces,
  projects, settings, packages, compatibility, sessions, language services

Luna UI
  rendering, platform hosts, input, accessibility, themes, general widgets,
  panes, text geometry, and optional reusable document/developer components
```

The governing rule is:

> Luna owns reusable editor anatomy. Moth owns editor meaning, workflow,
> compatibility, and product policy.

Luna never depends on Moth.

## Target graph

```text
MothTextMac -----------+
                       +--> MothApplication --> selected Luna products
MothTextLinux ---------+          |
                                  +--> MothWorkspace
                                  +--> MothEditor
                                  +--> MothTextCore
                                  +--> MothIPC

MothPluginHost ------------------> MothIPC

MothWorkspace --> MothEditor --> MothTextCore
MothTextCore imports Foundation only; no Luna or platform UI framework
```

## Buffer, document, history, and view law

These are four distinct concepts:

```text
MothInMemorySourceBuffer
  authoritative bytes
  monotonic render/search revision
  current and saved logical history-state IDs

MothFileDocument
  file identity + encoding + known disk state
  owns one source buffer
  owns one MothDocumentHistory instance

MothDocumentHistory
  undo and redo groups
  deterministic coalescing policy
  origin-view checkpoints
  bounded retained-memory estimate

MothEditorViewState
  caret + direction-preserving selection + preferred column + viewport
```

One document may have many editor views:

```text
MothFileDocument
  +-- source buffer
  +-- document history
  +-- primary MothEditorViewState
  +-- secondary MothEditorViewState
  +-- future cloned/grouped views
```

The document text and Undo/Redo history are shared. Caret, selection, preferred
column, active-pane status, and viewport remain view-local.

User-facing horizontal movement and deletion operate on extended grapheme-cluster
boundaries while stored coordinates remain absolute UTF-8 offsets. This prevents a
caret or destructive edit from stopping inside a multibyte scalar, combining
sequence, or other Swift `Character` in the current String-backed implementation.

## Revision identity versus history identity

`MothBufferRevision` is a monotonically increasing invalidation generation. Every
content-changing edit, Undo, and Redo advances it so render projections and find
results can detect stale content. It never moves backward.

`MothHistoryStateID` identifies a logical position in Undo/Redo history. Undo moves
to a prior state and Redo moves to a later retained state. A new branch edit always
receives a fresh identity; abandoned redo states are never reused.

```text
isDirty = currentHistoryState != savedHistoryState
```

This separation allows Undo back to disk content to become clean while the buffer
revision continues increasing.

## Primitive edit and history-group law

`MothBufferTransaction` records one UTF-8-safe applied replacement:

- requested and actual replaced ranges;
- removed and inserted text;
- revision and history state before/after;
- resulting caret;
- whether bytes changed.

`MothHistoryGroup` is one user-meaningful Undo unit. It may contain one primitive
edit or many edits, such as ordinary typing, repeated deletion, or Replace All.
Undo replays inverses in reverse order; Redo replays forward edits in original
order.

Production application/workspace edits route through `MothDocumentHistory`.
Low-level raw buffer replacement remains available for storage tests and future
infrastructure, and an architecture regression rejects direct use from
`MothApplication` or `MothWorkspace`.

## Deterministic grouping

Typing and contiguous deletion coalesce only while all semantic preconditions
remain true: same document state lineage, originating view, compatible intent,
contiguous ranges, and coalescing epoch.

The epoch is broken by navigation, pointer selection, pane switching, Save,
Undo/Redo, newline, find/command actions, and capture/focus loss. Grouping does not
depend on elapsed wall-clock time, making behavior deterministic and testable.

## Multi-view history behavior

Each history group records only the originating view's editor meaning before and
after the group:

```text
view ID + caret + direction-preserving selection + preferred UTF-8 column
```

Viewport state is intentionally excluded.

During an edit, Undo, or Redo:

1. every non-origin view transforms caret and selection coordinates through each
   known replacement;
2. the originating view's matching checkpoint is restored when that view still
   exists;
3. every view synchronizes to the new monotonic buffer revision;
4. active-pane ownership and independent viewports remain application state;
5. the active pane may scroll only enough to reveal its own caret.

## Saved checkpoint law

Save and Save As:

1. break the active coalescing run;
2. capture text, revision, and logical history state together;
3. write those captured bytes;
4. mark that exact captured state as saved;
5. preserve retained Undo/Redo groups.

If a newer edit occurs during file I/O, marking the captured state does not
incorrectly clean the newer state.

## Luna adapter boundary

`MothApplication` projects Moth state into Luna's neutral contracts:

```text
Moth source-buffer snapshot
        +--> MothLunaTextStorageAdapter --> LunaTextStorageSnapshot

MothEditorViewState
        +--> MothLunaViewProjection ----> LunaDocumentViewPresentationState

MothFindSession
        +--> MothLunaFindPanelSession ---> LunaFindPanelSession
```

Adapters expose snapshots and presentation state. They do not move source-buffer,
history, dirty-state, file, or replacement policy into Luna.

## Module ownership

### MothTextCore

- source-buffer identity and authoritative storage;
- typed UTF-8 coordinates and ranges;
- immutable snapshots;
- primitive applied transactions;
- monotonic buffer revisions;
- current/saved logical history-state storage.

It remains headless and Luna-free.

### MothEditor

- independent editor-view state;
- edit-based coordinate transformation;
- history groups and inverse replay;
- deterministic coalescing;
- originating-view checkpoint restoration;
- source-editor find and replacement policy;
- future multiple-cursor operations and transaction grouping.

### MothWorkspace

- file-document identity and lifecycle;
- ownership of each document's buffer and history instance;
- saved-history checkpoints;
- windows, groups, sheets, tabs, projects, and sessions.

### MothApplication

- composes Moth and Luna;
- maps pane IDs to Moth views;
- routes Luna pointer/keyboard/text input into Moth actions;
- owns stable Moth command IDs, availability, context projection, and execution;
- projects those commands into Luna menus, key bindings, and quick panels;
- preserves thin platform executable boundaries.

### MothIPC and MothPluginHost

Preserve the out-of-process service boundary. Plugin APIs remain intentionally
unstable until documents, commands, settings, and workspace ownership mature.

## Dependency laws

1. Luna does not import Moth.
2. MothTextCore imports no Luna, SDL, AppKit, Metal, GTK, or plugin runtime.
3. Platform executable targets do not own product state.
4. Moth consumes Luna through public Swift products.
5. Moth themes and compatibility files remain Moth resources.
6. Product history, grouping, dirty state, and editor meaning remain Moth-owned.
7. Reusable behavior is promoted to Luna only when product-neutral and useful to
   another plausible application.

## C2.1 Unicode rendering boundary

`LunaDebugBitmapTextRenderer` is diagnostic-only and must not paint production
Moth document text or user-provided filenames. The production path is:

```text
Moth text / filename / status string
        |
        v
MothUnicodeTextPainter (placement policy)
        |
        v
LunaTextRender.LunaUnicodeTextRenderer
        |
        +--> HarfBuzz UTF-8 clusters and advances
        +--> FreeType glyph masks and glyph cache
        +--> LunaRender CPU framebuffer blitter
```

Moth owns where and why text appears. Luna owns reusable shaping, rasterization,
font discovery, cache behavior, and visible missing-glyph fallback. C2.1 initially
projected one rounded shaped advance into Luna's fixed-cell geometry. C2.2 replaces
that approximation with explicit shaped insertion positions while retaining the
same product/framework ownership boundary. Full bidirectional layout, script
segmentation, and multi-font fallback remain later LunaText work.

Renderer initialization and draw failure are retained as Moth diagnostic state.
The application logs the first failure once, switches permanently to the visible
ASCII diagnostic fallback for that process, and prefixes the status bar with
`TEXT FALLBACK` instead of silently losing Unicode coverage.

Dirty and active-pane state remain Moth policy and are painted as explicit
framebuffer geometry rather than encoded as font glyphs.


## Stabilization S1 validation boundary

GitHub Actions and `scripts/validate-paired-iteration.sh` are two entry points to
the same repository gate. Validation checks native dependencies, the exact staged
Luna gitlink, a clean Luna submodule, every SwiftPM build/test product, a headless
Unicode render bootstrap, and the plugin-host IPC smoke test. The graphical window
remains a separate manual acceptance gate.

## M2.2B1 command authority boundary

Moth composes Luna's product-neutral command runtime rather than duplicating it:

```text
MothCommandID constants
        |
        v
LunaCommandRuntime<MothApplicationShellScene>
        |
        +--> key binding lookup
        +--> menu surface projection
        +--> command-palette projection
        +--> availability query
        +--> one Moth handler
```

`MothCommandSystem` declares the stable IDs and descriptors. The application scene
supplies dynamic availability and performs all file/editor mutations. Luna does
not know what New File, Save, Undo, or Select All means for Moth.

`LunaCommandContext` carries source, current document identity, focused surface,
and active pane identity. It is targeting metadata, not a container for product
objects. Document, buffer, history, and view ownership remain in Moth.

New File is intentionally a single-document replacement before M3A. It reuses the
existing dirty-document decision path, creates fresh product identities, resets
view state, and preserves the Luna pane tree. Real tab/document targeting waits
for the M3A document-sheet model.

A command invocation from a disabled binding is consumed and reported without
mutation. This is required because host text input can otherwise commit the
physical shortcut letter after the keyboard event. Matching disabled quick-panel
items remain searchable, preserving discoverability and the product-owned reason.


## C2.2 exact text geometry and scrolling boundary

The authoritative horizontal path is:

```text
Moth source row + source UTF-8 offsets
        |
        +--> Moth tab-expansion mapping
        |
        v
LunaUnicodeTextLayout
        +--> glyph placements
        +--> grapheme insertion positions in 26.6 pixels
        |
        v
LunaStaticTextRowGeometry
        +--> wrapping
        +--> caret and selection rectangles
        +--> pointer hit testing
        +--> row painting input
```

Moth retains the caret and selection as source-buffer UTF-8 offsets. Presentation
may expand a tab into spaces, but maps every source insertion boundary to the
corresponding shaped rendered boundary. No editor coordinate is derived from
`characterCount * roundedCellAdvance` on the production Unicode path.

The pane surface paints text before the caret. This makes the final caret rectangle
an absolute framebuffer result of the same row geometry and prevents glyph masks
from overwriting it.

Vertical scrolling follows a parallel ownership rule:

```text
Luna host scroll event
        -> reusable visual-row/scrollbar interaction
        -> requested viewport row + fractional remainder
        -> MothEditorViewportState for one pane
```

Wheel and touchpad input target the pane beneath the pointer without changing the
active editing pane. Scrollbar mouse-down may activate the pane because the user is
explicitly operating that pane's control. Moth stores each pane's first logical
line, optional wrapped visual row, and precise-delta remainder. Luna owns event
translation, clamping mechanics, lane paging, and thumb-drag geometry.

C2.2 remains a single-document phase. Document sheets, real tabs, and target-aware
close policy begin in M3A.


## C2.3 input-to-pixel latency boundary

Luna owns bounded platform-event polling, committed-text coalescing, frame timing,
and presentation fairness. Moth receives an ordered platform-neutral event stream
and continues to own buffer transactions, history grouping, caret meaning, and
view synchronization.

Plain printable SDL key-down events do not become editor text. SDL committed text
is authoritative and adjacent committed events may arrive as one string. Moth
applies that string through one history insertion, then performs one caret-visibility
calculation. Commands, navigation, pointer events, resize, and focus changes remain
hard ordering barriers.

Moth's shaped-layout cache is bounded and observational diagnostics are not painted
into the hot editor path. The document model remains single-document until M3A.
