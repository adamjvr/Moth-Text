# Text Geometry and Scrolling

Convergence C2.2 fixes two graphical editor-foundation defects discovered after
M2.2B1: cumulative caret drift on long rapidly typed rows and the absence of normal
wheel/trackpad scrolling.

## Source and presentation coordinates

Moth source buffers, caret positions, selections, and history retain absolute UTF-8
offsets. A pane projects one logical row through `MothUnicodeTextGeometryProvider`.
Tabs may expand to spaces for display, but `MothExpandedTextRun` maps each source
UTF-8 insertion boundary to the matching rendered boundary. Geometry requests
retain the complete logical line and the wrapped source range, so a continuation
row uses the original line-relative tab stops instead of restarting at column zero.

Luna shapes the rendered row and returns 26.6 insertion positions. Moth passes the
result through `LunaStaticTextRowGeometry`; LunaStaticTextView uses that immutable
geometry for wrapping, caret, selection, and hit testing. The pane painter draws
the same rendered row and paints the caret afterward.

Invariant:

```text
caret framebuffer X
    == visible row origin X
     + shaped row insertion X(source UTF-8 caret column)
```

The production Unicode path must never replace this invariant with a rounded cell
width multiplication. Moth retains bounded expanded-line and shaped-layout caches
so repeated layout and paint passes reuse immutable geometry without unbounded
memory growth; cache eviction may reshape deterministically without changing the
coordinate contract.

## Pane-local scrolling

Each `MothEditorViewState` owns:

- first visible logical line;
- optional first wrapped visual row;
- horizontal UTF-8 column reserved for later horizontal scrolling;
- fractional vertical remainder for precise wheel/trackpad devices.

Scroll input targets the pane beneath the pointer. It does not change active-pane
editing ownership. Scrollbar mouse-down is an explicit pane interaction and may
activate that pane. Page Up/Page Down and caret-follow scrolling reset the precise
remainder because they establish a discrete viewport position.

## Deferred behavior

C2.2 implements vertical scrolling for the current soft-wrapped panes. Horizontal
scrolling is not active. Multiple document sheets and real tabs begin in M3A.
Visible Find/Replace follows after M3A so commands and panels can target a stable
active document sheet.

## Focused validation

```bash
swift test --filter MothTextGeometryAndScrollingTests
./scripts/validate-paired-iteration.sh
```

The graphical pass must include rapid input, precomposed and decomposed Unicode,
click placement, selection, wheel and touchpad scrolling over both panes,
scrollbar lane paging, thumb dragging, capture loss, Page Up/Page Down, and
caret-follow scrolling.


## C2.3 latency follow-up

C2.3 leaves the exact C2.2 geometry unchanged. The host now presents between
bounded input batches, so the correct text/caret state reaches the framebuffer
without waiting for an unbounded queue drain. Adjacent committed text is applied
through one Moth insertion transaction and one caret-follow update. The shaped
layout cache uses bounded LRU retention and exposes hit/miss and shaping-time
snapshots for regression diagnostics without drawing a constantly changing status
string that would itself defeat caching.


## C2.4 scheduling correction

Exact C2.2 row geometry and scrolling are unchanged. C2.4 prevents raw input
acquisition chunks from inserting unrelated full-frame presentations before later
clicks or commands. Text, caret, selection, hit testing, wrapping, wheel routing,
and scrollbar behavior remain in the permanent native acceptance gate.
