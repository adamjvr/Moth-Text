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

The Git submodule pointer is the compatibility lock between the repositories.
Moth must not simultaneously declare a remote SwiftPM dependency for Luna.

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

A paired phase normally proceeds in this order:

1. Implement and test a reusable mechanism in Luna when one is genuinely needed.
2. Otherwise keep Luna source stable and update only permanent convergence docs.
3. Commit and push Luna first.
4. Advance Moth's Luna submodule with `./scripts/update-luna.sh`.
5. Implement Moth-owned product behavior without editing Luna inside Moth.
6. Build and test both repositories.
7. Launch and manually test Moth.
8. Commit Moth-owned changes and the Luna gitlink together.

A paired phase does not require inventing a Luna API merely to manufacture a
framework commit. C2 validates that rule by implementing history entirely in
Moth. C2.1 is the opposite justified case: graphical testing exposed a genuinely
reusable Unicode shaping/rasterization seam, so Luna adds `LunaTextRender` and
Moth consumes it without moving product policy into the framework.

## Layer boundary

Luna may provide reusable:

- editable text-surface geometry and rendering;
- line-number and marker gutters;
- pointer-selection interpretation;
- search-panel presentation;
- completion popups;
- document tab strips and split containers;
- text decorations, diff/log/console, and minimap primitives.

Moth owns:

- production source-buffer implementation;
- document-local Undo/Redo history and grouping;
- dirty-state and saved-checkpoint policy;
- source-editor search and replacement policy;
- multiple cursors;
- file/workspace lifecycle;
- Sublime-compatible commands, settings, keymaps, packages, and sessions;
- syntax and language-service orchestration.

## Convergence C2 compatibility point

Moth C2 requires the Luna C1B public surface or newer. Required seams include:

- `LunaCursorIntent`;
- `LunaPaneContainerInteractionState`;
- `LunaTextSelectionInteractionState` and `LunaTextSelectionInteraction`;
- pane content frames and soft-wrapped text geometry;
- UTF-8-safe clamped hit testing and word/logical-line ranges;
- SDL scene cursor and pointer-capture contracts;
- Phase 5E.2 document/view projection seams;
- the public `LunaTheme` product and host dialog boundary.

Update only through:

```bash
./scripts/update-luna.sh
```

C2 adds no Luna production source API. The Luna commit paired with C2 records the
source freeze and roadmap checkpoint; the required runtime compatibility surface
remains C1B.

Moth maps Luna pane and selection results into its own views. Luna owns geometry,
wrapping, hit testing, click-count interpretation, capture intent, cursor intent,
and autoscroll requests. Moth retains the file document, source buffer, history,
dirty state, caret, selection, preferred column, viewport, and edit meaning.

## Convergence C2.1 compatibility point

Moth C2.1 additionally requires:

- the public `LunaTextRender` product;
- `LunaUnicodeTextRenderer`;
- `LunaFontLocator.bestMonospacedFontPath()`;
- shaped UTF-8 cluster/advance layout;
- cached FreeType glyph-mask painting through LunaRender;
- explicit missing-glyph fallback behavior.

Moth's adapter chooses font size, shell placement, and product colors. Moth does
not import FreeType or HarfBuzz and does not own a duplicate glyph cache.

`LunaDebugBitmapTextRenderer` remains valid for ASCII diagnostics and early
bring-up, but production Moth document text must not call it directly.
