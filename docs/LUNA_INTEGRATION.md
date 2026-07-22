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
./scripts/validate-paired-iteration.sh
```

## Coordinated development

A paired phase normally proceeds in this order:

1. Implement and test a reusable mechanism in Luna when one is genuinely needed.
2. Otherwise keep Luna source stable and update only permanent convergence docs.
3. Commit and push Luna first.
4. Advance Moth's Luna submodule with `./scripts/update-luna.sh`.
5. Implement Moth-owned product behavior without editing Luna inside Moth.
6. Build and test both repositories with their permanent validation scripts.
7. Require the clean-checkout GitHub Actions jobs to pass.
8. Launch and manually test Moth.
9. Commit Moth-owned changes and the Luna gitlink together.

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


## Stabilization S1 CI contract

Moth's workflow checks out submodules recursively, while the repository validation
script verifies that `Dependencies/Luna-UI` is clean and exactly matches the index
gitlink. After intentionally advancing Luna, stage the gitlink before validation:

```bash
git add Dependencies/Luna-UI
./scripts/validate-paired-iteration.sh
```

The validation gate also runs `MothTextLinux --headless-smoke`. This renders one
frame without opening SDL, requires the Unicode renderer to remain active, and
fails when font discovery, HarfBuzz shaping, FreeType rasterization, or framebuffer
painting falls back to the ASCII diagnostic path.

## M2.2B1 command compatibility point

M2.2B1 requires only Luna APIs already present in the pinned framework revision:

- `LunaCommandID`, descriptors, contexts, availability, and execution results;
- `LunaCommandRuntime` and key-binding matching;
- `LunaKeyboardEvent.lunaCommandKeyStroke` and shortcut suppression hints;
- `LunaMenuBar` model, layout, interaction, and accessibility;
- `LunaQuickPanel` filtering, interaction, layout, and accessibility.

Moth declares stable `moth.*` command IDs, owns availability and handlers, and
renders product text through `MothUnicodeTextPainter`. Integration exposed one
small reusable Luna defect: disabled quick-panel items disappeared from nonempty
searches. Luna now keeps matching disabled items discoverable while retaining
their disabled metadata, allowing products to explain why a command is currently
unavailable without making it vanish.

## Convergence C2.2 compatibility point

C2.2 advances the Luna gitlink for reusable text and host-input mechanics:

- `LunaUnicodeTextLayout.insertionPositions` and UTF-8/X conversion helpers;
- `LunaStaticTextRowGeometry` and `LunaStaticTextGeometryProvider`;
- shaped-geometry soft wrapping, caret, selection, and hit testing in
  `LunaStaticTextView`;
- `LunaScrollEvent` and `LunaHostInputEvent.scroll`;
- SDL wheel/precise-delta translation inside LunaHostSDL;
- `LunaStaticTextScrollInteraction` for wheel accumulation, lane paging, and
  thumb dragging.

Moth supplies a geometry provider that expands tabs while retaining source UTF-8
boundaries, stores pane-local viewport and fractional remainder state, and paints
rows/carets in product order. Luna does not own Moth buffers, caret meaning,
active-pane policy, or document tabs.

The next paired slice is M3A document sheets and real tabs. It should reuse Luna's
existing generic tab strip and workspace mechanics unless implementation exposes a
new product-neutral seam. M2.2B2 then reuses the existing Luna find-panel
presentation against the active Moth sheet.


## Convergence C2.3 compatibility point

C2.3 advances the Luna gitlink for reusable host-runtime behavior rather than
product policy. Luna adds bounded SDL polling, committed-text coalescing,
polling/backlog diagnostics, input-to-present timing, and restored kitchen-sink
demo defaults. Moth consumes the ordered event batches and retains ownership of
buffer mutation, history, caret/view state, and shaped-text cache policy.

The next compatibility point is M3A. Existing Luna tab primitives should be reused;
Luna changes only when Moth exposes a genuinely reusable tab/sheet projection gap.
