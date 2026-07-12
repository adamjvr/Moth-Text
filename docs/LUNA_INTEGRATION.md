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

## Convergence C1B compatibility point

Moth M2.2A with Convergence C1B requires the matching Luna Convergence C1B revision or newer. The required public seams include `LunaCursorIntent`, `LunaPaneContainerInteractionState`, `LunaTextSelectionInteractionState`, `LunaTextSelectionInteraction`, clamped wrapped-text hit testing, Unicode-aware word/logical-line range helpers, axis-specific divider cursor intent, and the SDL scene cursor/capture contract. Update it only through:

```bash
./scripts/update-luna.sh
```

That Luna revision supplies pane content frames, width-correct soft-wrapped text-view geometry, native cursor/capture behavior, and product-neutral pointer-selection interpretation in addition to the Phase 5E.2 document/view adapters, public `LunaTheme` product, pane mechanics, and application-owned termination veto.

Moth maps Luna pane IDs and Luna selection results to its own primary and secondary editor-view state. Luna owns bounds, clipping, wrapping, visual-row hit testing, click-count interpretation, pointer-capture intent, reusable word/line units, and autoscroll requests. Moth retains one authoritative file document plus independent caret, selection, and viewport state per view. `MothTextCore` remains headless, `MothWorkspace` owns file/document lifecycle, and `MothEditor` owns actual view state, transactions, history, and find/replace policy.

C1B does not move selection storage or document mutation into Luna. It only replaces duplicate application gesture decoding with one reusable mechanism.
