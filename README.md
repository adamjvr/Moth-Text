# Moth Text

**Moth Text** is a clean-room, open-source, Swift-native editor intended to
reproduce the speed, command-driven workflow, extensibility, and user-facing
behavior that make Sublime Text distinctive, while providing a modern and open
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
widgets, and optional reusable components such as text surfaces, gutters, search
panels, popups, tabs, split containers, and developer-tool views.

Moth supplies production source buffers, editor transactions, multiple cursors,
commands, projects, workspaces, settings, sessions, syntax, packages, plugins,
language services, and Sublime compatibility.

## Repository relationship

Luna is an independent repository pinned inside Moth at:

```text
Dependencies/Luna-UI
```

The canonical Git repository tracks that path as a submodule. SwiftPM consumes it
as a local package, so each Moth revision records the exact Luna revision it was
tested against.

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
  MothTextCore/       headless source-buffer and editing foundations
  MothEditor/         source-editor semantics and view state
  MothWorkspace/      sheets, groups, projects, sessions, product policy
  MothApplication/    shared Luna/product composition
  MothIPC/            JSON protocol and Unix-domain-socket transport
  MothPluginHost/     out-of-process service/plugin host proof
  MothTextLinux/      thin Linux platform entry point
  MothTextMac/        thin macOS platform entry point

Dependencies/
  Luna-UI/            pinned first-party framework dependency

Tests/                headless module and protocol tests
Resources/            Moth-owned themes, menus, settings, keymaps, syntaxes
```

## Architectural laws

- Luna never depends on Moth.
- `MothTextCore` does not depend on Luna or platform UI frameworks.
- A buffer is separate from any visible editor view.
- Multiple views may share one buffer and retain independent view state.
- Platform executables remain thin host entry points.
- Moth's interior is rendered with Luna rather than SwiftUI, AppKit widgets,
  GTK widgets, Qt, Electron, or web technology.
- Reusable editor-adjacent components may live in optional Luna modules, but
  Moth-specific behavior and compatibility remain in Moth.

## Current status

### M0 — Repository and Luna integration foundation

Implemented:

- SwiftPM-conventional repository layout;
- Luna local-package/submodule path;
- foundational Moth product targets;
- preserved IPC and plugin-host proof;
- initial buffer/view identity distinction;
- product/platform/framework boundary documentation;
- bootstrap and verification scripts.

### M1.1 — Shared buffer and independent editor views

Implemented against Luna Phase 5E.2:

- one authoritative, revisioned Moth source buffer;
- typed UTF-8 offsets, ranges, snapshots, transactions, and dirty state;
- two independent editor views over the same buffer;
- Moth-owned find/replace policy behind Luna presentation contracts;
- a graphical Luna shell that renders and edits real Moth buffer content;
- headless architecture and behavior tests preserving the Moth/Luna boundary.

### M2.1 — First file-backed editor workflow

Implemented against Luna Phase 5F.1:

- Moth-owned file document identity, URL, display name, UTF-8/BOM encoding, saved revision, and known disk state;
- real Open, Save, and Save As through the Luna host-dialog boundary;
- external-change detection without moving filesystem policy into Luna;
- dirty-document Save / Don’t Save / Cancel protection when replacing or closing the current document;
- file-name/path/encoding/dirty/revision projection into the graphical shell;
- command-line file opening plus Linux zenity/yad/kdialog adapters;
- a Moth-owned application theme supplied through Luna's public theme product;
- two independent editor views retained over the file document's one authoritative buffer.

### Next: M2.2 — Editing command depth

The next product slice adds undo/redo transaction grouping, a visible find/replace
panel, fuller command/menu routing and shortcuts, and external-change response UI.

See:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/LUNA_INTEGRATION.md`](docs/LUNA_INTEGRATION.md)
- [`docs/ROADMAP.md`](docs/ROADMAP.md)
- [`docs/SUBMODULE_WORKFLOW.md`](docs/SUBMODULE_WORKFLOW.md)
- [`docs/PAIRED_ITERATION_PROTOCOL.md`](docs/PAIRED_ITERATION_PROTOCOL.md)

## Build

Luna's current Linux development path requires SDL2, HarfBuzz, FreeType, and
`pkg-config`:

```bash
sudo apt update
sudo apt install libsdl2-dev libharfbuzz-dev libfreetype6-dev pkg-config
```

Then:

```bash
./scripts/bootstrap.sh
```

Launch the graphical editor shell with an untitled document:

```bash
swift run MothTextLinux
```

Or open a real file directly:

```bash
swift run MothTextLinux /tmp/moth-test.txt
```

Run the optional plugin-host proof separately with:

```bash
./scripts/smoke-test-plugin-host.sh
```

## License

Moth Text is licensed under the **Mozilla Public License 2.0 (`MPL-2.0`)**, matching Luna-UI. The complete license text is provided in [`LICENSE`](LICENSE). Source files, tests, package manifests, and repository scripts carry concise SPDX identifiers.

The MPL-2.0 applies on a file-level basis: modifications to covered Moth Text files remain available under the MPL-2.0, while the license permits Moth Text to be combined with separately licensed code in a larger work.


## Application and IPC smoke tests

Normal Moth startup must succeed without the optional plugin host:

```bash
swift run MothTextLinux
```

Run the separate plugin-host IPC proof with:

```bash
./scripts/smoke-test-plugin-host.sh
```

The plugin host is exposed as the `MothPluginHost` executable product.

## Current Graphical Shell

`swift run MothTextLinux` now opens a real Luna-rendered resizable window,
accepts an optional file path, and runs until the window is closed. M2.1 renders
and edits a real Moth-owned file document through Luna adapters, supports Open,
Save, Save As, UTF-8 BOM preservation, and dirty-close protection, and keeps the
optional plugin host as a separate smoke test. Visible find UI and undo/redo
arrive in M2.2.
