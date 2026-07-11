# Luna UI Integration

## Submodule contract

Moth uses Luna from:

```text
Dependencies/Luna-UI
```

SwiftPM resolves it with:

```swift
.package(path: "Dependencies/Luna-UI")
```

The Git submodule pointer is the compatibility lock between the two repositories.
Moth should not simultaneously declare a remote SwiftPM dependency for Luna.

## Clone and bootstrap

```bash
git clone --recurse-submodules <moth-url>
cd Moth-Text
./scripts/bootstrap.sh
```

For an existing clone:

```bash
git submodule update --init Dependencies/Luna-UI
./scripts/test-all.sh
```

## Coordinated development

A paired change normally proceeds in this order:

1. Implement and test the reusable mechanism in Luna.
2. Commit and push the Luna branch.
3. Integrate that API in Moth.
4. Run Moth and Luna tests.
5. Commit Moth source changes and the advanced Luna gitlink together.

Never commit a Moth submodule-pointer update without recording what Luna behavior
or API the new revision is required for.

## Layer boundary

Luna may provide optional reusable document and developer-tool components:

- editable text surfaces;
- line-number and marker gutters;
- search-panel presentation;
- completion popups;
- document tab strips;
- split containers;
- text decorations;
- diff, log, console, and minimap primitives.

Moth owns:

- production source-buffer implementation;
- source-editor search and replacement policy;
- multiple cursors;
- undo grouping;
- file and workspace lifecycle;
- Sublime-compatible commands, settings, keymaps, packages, and sessions;
- syntax and language-service orchestration.

## Phase 5F.1 compatibility point

Moth M2.1 requires the Luna Phase 5F.1 revision committed and pushed immediately
before this Moth overlay is tested. Update it only through:

```bash
./scripts/update-luna.sh
```

That Luna revision supplies the Phase 5E.2 document/view adapters, the public
`LunaTheme` product, reusable pane/tab mechanics, and an application-owned SDL
termination veto. Moth uses the termination veto to keep dirty-close Save / Don’t
Save / Cancel policy in the product while Luna remains neutral.

Moth consumes Luna contracts only from `MothApplication` and platform entry points.
`MothTextCore` remains headless, `MothWorkspace` owns file/document lifecycle, and
`MothEditor` owns view and find/replace policy.
