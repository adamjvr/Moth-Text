# Moth Text

**Moth Text** is a clean-room, open-source, Swift-native editor intended to
reproduce the speed, command-driven workflow, extensibility, and user-facing
behavior that make Sublime Text distinctive while providing a modern and open
foundation for additional capabilities.

Moth is not a Sublime Text fork and does not copy Sublime's proprietary internals.
Compatibility is implemented through Moth-owned models and adapters.

## Luna UI relationship

Moth is the flagship application for **Luna UI**, a custom-rendered Swift desktop
UI framework. Luna exists under the pressure of Moth's editor-class requirements,
but remains reusable for unrelated applications and optional document/developer
components.

```text
Luna owns reusable editor anatomy.
Moth owns editor meaning, workflow, compatibility, and product policy.
```

Luna supplies rendering, platform hosts, input, accessibility, themes, general
widgets, panes, text-surface geometry, cursor/capture behavior, and reusable
pointer-selection interpretation.

Moth supplies production source buffers, document history, editor transactions,
multiple cursors, commands, projects, workspaces, settings, sessions, syntax,
packages, plugins, language services, and Sublime compatibility.

## Repository relationship

Luna is an independent Git repository pinned inside Moth at:

```text
Dependencies/Luna-UI
```

The canonical repository tracks that path as a Git submodule. SwiftPM consumes it
as a local package, so each Moth revision records the exact Luna revision against
which it was built and tested.

Clone with:

```bash
git clone --recurse-submodules <moth-repository-url>
cd Moth-Text
./scripts/bootstrap.sh
```

For an existing clone:

```bash
git submodule update --init Dependencies/Luna-UI
./scripts/test-all.sh
```

## Current module structure

```text
Sources/
  MothTextCore/       headless source-buffer primitives and monotonic revisions
  MothEditor/         editor views, history groups, undo/redo, find policy
  MothWorkspace/      file documents, saved checkpoints, workspace policy
  MothApplication/    shared Luna/product composition and input routing
  MothIPC/            JSON protocol and Unix-domain-socket transport
  MothPluginHost/     out-of-process service/plugin host proof
  MothTextLinux/      thin Linux platform entry point
  MothTextMac/        thin macOS platform entry point

Dependencies/
  Luna-UI/            pinned first-party framework dependency

Tests/                headless module, history, integration, and protocol tests
Resources/            Moth-owned themes, menus, settings, keymaps, syntaxes
```

## Architectural laws

- Luna never depends on Moth.
- `MothTextCore` does not depend on Luna or platform UI frameworks.
- A source buffer is separate from a file document and from every visible view.
- Multiple views may share one document while retaining independent caret,
  direction-preserving selection, preferred-column, and viewport state.
- Buffer revisions are monotonic invalidation generations; undo history states
  are separate logical identities that can move backward and forward.
- Production application and workspace edits pass through the document-owned
  history authority rather than mutating the raw buffer directly.
- Platform executables remain thin host entry points.
- Moth's interior is rendered with Luna rather than SwiftUI, AppKit widgets,
  GTK widgets, Qt, Electron, or web technology.

## Current status

### M0 — Repository and Luna integration foundation

Implemented:

- SwiftPM-conventional repository layout;
- Luna local-package/submodule path;
- foundational Moth product targets;
- preserved IPC and plugin-host proof;
- buffer/view identity distinction;
- product/platform/framework boundary documentation;
- bootstrap and paired-repository verification scripts.

### M1.1 — Shared buffer and independent editor views

Implemented against Luna Phase 5E.2:

- one authoritative, revisioned Moth source buffer;
- typed UTF-8 offsets, ranges, snapshots, and primitive transactions;
- two independent editor views over the same buffer;
- Moth-owned find/replace policy behind Luna presentation contracts;
- a graphical Luna shell backed by real Moth text;
- headless architecture and behavior tests preserving the Moth/Luna boundary.

### M2.1 — First file-backed editor workflow

Implemented against Luna Phase 5F.1:

- Moth-owned file-document identity, URL, display name, UTF-8/BOM encoding, and
  known disk state;
- real Open, Save, and Save As through the Luna host-dialog boundary;
- external-change detection without moving filesystem policy into Luna;
- dirty-document Save / Don't Save / Cancel protection;
- command-line file opening plus Linux zenity/yad/kdialog adapters;
- a Moth-owned application theme supplied through Luna's public theme product.

### M2.2A — Pane-bound editor-view integration

Implemented against Luna Phase 5F.2A:

- two real Luna pane leaves mapped to Moth's primary and secondary views;
- independent caret, selection, logical-line, and wrapped visual-row state;
- width-correct soft wrapping and clipping inside each pane;
- active-pane pointer/edit routing and Ctrl+Tab traversal;
- divider resizing that reflows both views without changing document ownership.

### Convergence C1A — Native cursor and divider interaction

Implemented against Luna C1A:

- native I-beam and resize cursor intent;
- forgiving semantic divider controls with thin visible rules;
- hover/active feedback and pointer capture through mouse-up;
- shared Luna pane interaction state rather than duplicate Moth drag logic.

### Convergence C1B — Foundational mouse selection

Implemented against Luna C1B:

- click, Shift-click, captured drag, Unicode-aware word selection, and logical-line
  selection;
- wrapped-row tracking and visual-row edge autoscroll;
- safe capture-loss cancellation;
- independent pane-local selection/caret/viewport state over one document;
- selection replacement and removal through Moth editor transactions.

### Convergence C2 — Document-owned undo/redo

Implemented in Moth while Luna's C1B source API remains stable:

- document-local undo and redo stacks made of user-meaningful history groups;
- inverse edit replay with monotonically increasing buffer revisions;
- separate logical history-state identity for correct saved-state tracking;
- deterministic typing, Backspace, and Delete coalescence with explicit semantic
  boundaries instead of wall-clock timing;
- redo invalidation and fresh branch identities after a new edit;
- initiating-view caret/selection/preferred-column restoration;
- edit-based coordinate transformation for all other views without rewinding
  their viewports;
- atomic selection replacement and history-aware Find Replace/Replace All paths;
- Save and Save As move an exact saved-history checkpoint without clearing Undo;
- a bounded per-document history-memory budget;
- Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z, and Ctrl+Y routing in the graphical shell.

### Convergence C2.1 — Unicode text painting and visible-state correction

Implemented after graphical C2 validation exposed that Moth was still painting
production document text through Luna's ASCII-only debug bitmap renderer:

- MothApplication consumes Luna's optional `LunaTextRender` product;
- HarfBuzz-shaped UTF-8 runs and cached FreeType glyph masks paint editor rows,
  filenames, paths, status messages, and tab titles;
- the shaped monospaced cell advance feeds the existing Luna text-view metrics so
  painting, wrapping, caret placement, selection rectangles, and hit testing use
  one cell width;
- unsupported glyphs display an explicit fallback box instead of an invisible
  advanced cell;
- dirty and active-pane indicators are Moth-owned framebuffer geometry rather
  than Unicode bullet characters;
- focused regressions cover accented text and visible dirty-state geometry.

C2.1 deliberately does not implement Ctrl+N, multiple documents, real tabs, or
folder-row activation. Ctrl+N remains M2.2B command scope; real documents/tabs and
project navigation remain M3 workspace scope.

### Next: M2.2B — Command and visible find convergence

The next product slice connects Moth's typed command authority to Luna menus,
shortcuts, quick panels, and visible find/replace presentation. It also begins
external-change reload/conflict presentation and recent-file/session groundwork.

See:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/LUNA_INTEGRATION.md`](docs/LUNA_INTEGRATION.md)
- [`docs/ROADMAP.md`](docs/ROADMAP.md)
- [`docs/SUBMODULE_WORKFLOW.md`](docs/SUBMODULE_WORKFLOW.md)
- [`docs/PAIRED_ITERATION_PROTOCOL.md`](docs/PAIRED_ITERATION_PROTOCOL.md)

## Build

Luna's Linux development path requires SDL2, HarfBuzz, FreeType, and `pkg-config`:

```bash
sudo apt update
sudo apt install libsdl2-dev libharfbuzz-dev libfreetype6-dev pkg-config
```

Then:

```bash
./scripts/bootstrap.sh
swift test
```

Launch with an untitled document:

```bash
swift run MothTextLinux
```

Or open a real file directly:

```bash
swift run MothTextLinux /tmp/moth-test.txt
```

Run the optional plugin-host proof separately:

```bash
./scripts/smoke-test-plugin-host.sh
```

## Current graphical shell

`swift run MothTextLinux` opens a real Luna-rendered resizable window and accepts
an optional file path. Both pane-bound views share one file document while
retaining independent presentation state. Open, Save, Save As, UTF-8 BOM
preservation, dirty-close protection, native cursor/divider behavior, captured
mouse selection, and document-owned Undo/Redo remain active together.

C2 development diagnostics expose the monotonic buffer revision, logical history
state, dirty state, active pane, and retained Undo/Redo group counts in the status
bar. C2.1 paints document and user-facing text through LunaTextRender and uses
geometry for dirty/active indicators. The visible Edit menu is still
presentation-only; unified command/menu/palette routing is deferred to M2.2B.

## License

Moth Text is licensed under the **Mozilla Public License 2.0 (`MPL-2.0`)**,
matching Luna-UI. The complete license text is provided in [`LICENSE`](LICENSE).
