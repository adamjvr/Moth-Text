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
git submodule update --init --recursive
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

## Phase 5E.2 compatibility point

Moth M1.1 is validated against Luna commit:

```text
debc3bbc548ce3cdffcfd549cea9062d4b9dd2a1
feat(document): add Luna Phase 5E.2 adapter seams
```

That Luna revision supplies stable document/view identities, immutable UTF-8 text
snapshots, content revisions, independent presentation state, revision invalidation,
injected find-panel session contracts, and a public CPU bitmap text renderer.

Moth consumes those contracts only from `MothApplication`. `MothTextCore` owns the
authoritative text and revisions, while `MothEditor` owns view and find/replace
policy. Advancing past this Luna revision requires rerunning both repositories'
headless suites and the Moth graphical and IPC smoke checks.
