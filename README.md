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
- the first integration feeds a shaped monospaced advance into Luna text-view
  metrics; C2.2 later replaces this fixed-cell approximation with exact shaped
  insertion positions;
- unsupported glyphs display an explicit fallback box instead of an invisible
  advanced cell;
- dirty and active-pane indicators are Moth-owned framebuffer geometry rather
  than Unicode bullet characters;
- focused regressions cover accented text and visible dirty-state geometry.

C2.1 deliberately did not implement Ctrl+N, multiple documents, real tabs, or
folder-row activation. Ctrl/Cmd+N is now implemented by M2.2B1; real documents,
tabs, and project navigation remain M3 workspace scope.

C2.1 is now graphically accepted at this repository head. The 74-test C2.1
baseline and plugin-host IPC smoke test passed on Linux before Stabilization S1.

### Stabilization S1 — Repository trust and grapheme correctness

Implemented in this revision:

- clean-checkout Ubuntu GitHub Actions for Moth and the pinned Luna submodule;
- exact staged-gitlink verification for paired Luna updates;
- a noninteractive `--headless-smoke` render/bootstrap mode used by CI;
- persistent Unicode-renderer diagnostics with a visible status-bar fallback warning;
- one-time renderer failure logging rather than silent degradation;
- extended-grapheme navigation, selection, Backspace, and Delete behavior;
- regression coverage for decomposed accents through editor, history, and application paths;
- an expanded accepted automated total of 86 tests, up from the 74-test C2.1 baseline.

### M2.2B1 — Unified command authority and New File

Implemented in this revision:

- stable `moth.*` command identifiers backed by Luna's product-neutral command runtime;
- one availability and execution path shared by keyboard shortcuts, real menu rows,
  the command palette, and programmatic tests;
- dynamic Save, Undo, Redo, and Select All availability;
- real Luna menu-bar/dropdown interaction replacing decorative menu text;
- a visible, searchable Luna command palette opened with Ctrl/Cmd+Shift+P, with Escape returning input to the editor;
- Ctrl/Cmd+N New File with Save / Don't Save / Cancel protection;
- fresh document, buffer, history, and view identities after New File while the
  current pane geometry is preserved;
- Open, Save, Save As, Undo, Redo, Select All, and pane traversal routed through
  the same command dispatcher;
- disabled Find presentation that preserves Ctrl/Cmd+F for M2.2B2 without
  inserting shortcut text into the document;
- 17 new command regressions, bringing the expected Moth total to 103 tests.

See [`docs/COMMANDS.md`](docs/COMMANDS.md) for the command contract.

### Convergence C2.2 — Exact text geometry and vertical scrolling

Implemented after graphical M2.2B1 validation exposed cumulative caret drift on
long rapidly typed rows and the absence of normal wheel/trackpad input:

- Luna's shaped UTF-8 insertion positions, retained in HarfBuzz 26.6 coordinates,
  now drive soft wrapping, caret placement, selection rectangles, and hit testing;
- Moth paints each visible row from the same rendered row text and paints the
  caret after glyphs so the insertion indicator cannot be covered;
- tab expansion preserves source UTF-8 offsets while using rendered-space shaped
  positions;
- platform-neutral wheel and trackpad events route to the pane beneath the pointer
  without changing the active editing pane;
- precise scroll deltas retain a pane-local fractional visual-row remainder;
- scrollbar lane clicks page, thumb dragging captures the pointer, and all
  viewport requests clamp to legal wrapped visual rows;
- Page Up/Page Down, caret-follow scrolling, selection-edge autoscroll, Unicode
  fallback diagnostics, and independent pane view state remain intact;
- eight Moth regressions bring the expected total to 111 tests, while Luna adds
  focused shaping, geometry, SDL wheel, and scrollbar coverage.

C2.2 deliberately does not implement multiple documents or real tabs. New File
continues to replace the current single document through the protected M2.2B1
lifecycle until M3A installs document sheets.

### Convergence C2.3 — Input-to-pixel latency and demo restoration

C2.3 followed C2.2 exact geometry and attempted to reduce rapid-input lag.
Retained results:

- plain printable key-down events defer to authoritative committed text input;
- adjacent committed text remains ordered around commands, navigation, pointer,
  resize, and focus barriers;
- Luna frame timing records input-to-present latency and merge diagnostics;
- LunaUITestApp again defaults to the complete kitchen-sink demo, including the
  animated square and a deterministic 340-row scrolling corpus;
- four regressions established the 115-test baseline.

Rejected result: presenting after bounded raw polling batches. Native testing
showed that this delayed clicks and commands behind repeated full-frame draws.
C2.4 replaces that scheduling policy.

### Convergence C2.4 — Interactive runtime and presentation scheduling

C2.3's kitchen-sink restoration and diagnostics remain, but its raw polling batch
policy failed graphical acceptance by delaying clicks and commands behind repeated
full-frame presentations. C2.4 consumes Luna's persistent semantic scheduler:
coalescing survives native acquisition passes, clicks and fresh/modified keys
request prompt dispatch, and sustained text, repeat, scroll, and resize streams are
bounded by idle state, semantic thresholds, or a latency deadline rather than by
arbitrary polling limits.

Moth replaces the array-maintained layout LRU hit path with dictionary lookup plus
an access-generation update. Least-recently-used scans occur only during bounded
insertion-time eviction. One new regression brings the expected Moth total to
**116 tests**.

C2.4 does not implement tabs. Native validation accepted ordinary Moth interaction:
the first graphical run was snappy and visually smooth. The generated large-document
run exposed a separate Critical scalability failure: roughly 500 soft-wrapped rows
could freeze or make the program unusably slow, while the Luna kitchen-sink demos
remained sluggish. A1.1 measured layout/composition analysis is now the next phase;
M3A begins only after the paired audit is reviewed.

### Deferred until after audit: M3A — Document sheets and real tabs

The next product slice introduces a Moth-owned document-sheet collection and
projects it through Luna's existing tab mechanics. Ctrl/Cmd+N will append and
activate a new untitled sheet instead of replacing the current document. Visible
Find/Replace follows after the multi-document targeting model is established.

See:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/LUNA_INTEGRATION.md`](docs/LUNA_INTEGRATION.md)
- [`docs/ROADMAP.md`](docs/ROADMAP.md)
- [`docs/SUBMODULE_WORKFLOW.md`](docs/SUBMODULE_WORKFLOW.md)
- [`docs/PAIRED_ITERATION_PROTOCOL.md`](docs/PAIRED_ITERATION_PROTOCOL.md)
- [`docs/TEXT_GEOMETRY_AND_SCROLLING.md`](docs/TEXT_GEOMETRY_AND_SCROLLING.md)
- [`docs/INPUT_LATENCY.md`](docs/INPUT_LATENCY.md)
- [`docs/TESTING_COMMAND_CHEAT_SHEET.md`](docs/TESTING_COMMAND_CHEAT_SHEET.md)

## C2.5F — Virtualized document presentation

C2.5E semantic dispatch fairness passed automated validation, but its native
large-document matrix was rejected: 500 lines were sluggish and the 5,000- and
50,000-line fixtures required force quit. The committed checkpoint also contained
patch artifacts rather than the intended live Moth source integration.

C2.5F repaired the live shell and introduced bounded virtualized presentation.
C2.5G–J then completed attribution, lazy metadata, persistent interaction reuse, and
narrower damage. The accepted 5,000- and 50,000-line C2.5J matrix closes the M3A
scalability gate.

## Build

Luna's Linux development path requires SDL2, HarfBuzz, FreeType, and `pkg-config`:

```bash
sudo apt update
sudo apt install libsdl2-dev libharfbuzz-dev libfreetype6-dev pkg-config
```

Then run the complete local equivalent of the GitHub Actions gate:

```bash
./scripts/validate-paired-iteration.sh
```

For the focused M2.2B1 command suite:

```bash
swift test --filter MothCommandSystemTests
```

For the shorter bootstrap-only path:

```bash
./scripts/bootstrap.sh
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
geometry for dirty/active indicators. S1 reports Unicode-renderer failure in that
status bar, logs the retained error once, and keeps the visible ASCII diagnostic
fallback usable. Horizontal movement and deletion step across extended grapheme
clusters.

M2.2B1 replaces decorative menu labels with interactive command surfaces. C2.2
makes shaped insertion geometry authoritative and adds normal pane-local vertical
scrolling. C2.4 keeps raw acquisition separate from semantic scheduling and presentation,
then removes linear ordering-array maintenance from shaped-layout cache hits. Ctrl/Cmd+N
still safely replaces the single current document for now. C2.4 ordinary interaction was followed by the measured C2.5A–J scalability
sequence. C2.5J is accepted, and M3A real document tabs is now the active product
phase.

## License

Moth Text is licensed under the **Mozilla Public License 2.0 (`MPL-2.0`)**,
matching Luna-UI. The complete license text is provided in [`LICENSE`](LICENSE).

## M3A — Document sheets and real tabs {#M3A_PRODUCT_PHASE_CURRENT}

**Current product phase after accepted C2.5J.** Moth now drives normal iteration.
Luna changes are made only when a Moth feature exposes a reusable component gap,
framework defect, platform-boundary problem, or measured Luna-owned regression.

M3A replaces the single-document lifecycle with a Moth-owned ordered document-sheet
workspace projected through Luna's existing product-neutral tab layout, overflow,
hit-testing, close-target, and accessibility mechanics. New File appends a tab,
Open reuses canonical files, each sheet retains independent document/history/view
state, the sidebar projects the same sheets as clickable Open Files rows, and dirty
close policy targets only the selected sheet.

Visible Find/Replace remains M2.2B2 and follows M3A so commands and panel state can
target a stable active document sheet.

## M2.2B2 — Clipboard and Visible Find/Replace {#M22B2_CURRENT_PHASE}

**Current product phase after accepted M3A.** Moth now exposes native system
Copy, Cut, and Paste through a Luna host clipboard boundary and integrates the
existing Moth-owned, history-aware find engine with Luna's visible Find/Replace
panel. Clipboard and search commands target the focused Find field or the active
pane of the active document sheet; inactive tabs cannot be mutated.

Replace All is one atomic Moth history group, invalid regular expressions remain
visible and non-destructive, search highlights stay viewport-bounded, and each
M3A sheet retains independent query/replacement/options/result state. The Linux
SDL host also receives explicit application identity so normal, 5K, and 50K
launches match the installed Moth desktop icon.

See [`docs/M2.2B2_CLIPBOARD_AND_FIND_REPLACE.md`](docs/M2.2B2_CLIPBOARD_AND_FIND_REPLACE.md).
