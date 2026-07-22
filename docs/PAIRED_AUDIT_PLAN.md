# Post-C2.4 Paired Audit Plan

C2.4 native validation accepted ordinary Moth interaction scheduling: the first
`MothTextLinux` graphical run was snappy and rendered smoothly. The same validation
found two separate release-blocking scalability failures:

- the default Luna kitchen-sink and proof-oriented demos were sluggish;
- a generated roughly 500-line Moth document froze or became unusably slow.

Do not begin M3A and do not implement a speculative optimization before this audit
is reviewed. The large generated document and animated Luna demo remain permanent
regression probes.

## A1.1 — Reproduce and measure

Use deterministic fixtures with 50, 500, 5,000, and 50,000 logical lines. Include
short lines, long soft-wrapped lines, tabs, blank lines, precomposed/decomposed
Unicode, Greek, Cyrillic, and punctuation.

Run:

- one pane;
- two panes at equal widths;
- two panes at unequal widths;
- wrapping off and soft wrapping on;
- initial open, idle render, scroll, scrollbar drag, typing, deletion, navigation,
  selection, pane resize, and window resize.

Record both wall-clock timings and architecture-stable operation counts for:

- source-buffer snapshots;
- Moth-to-Luna snapshot projection;
- logical lines scanned;
- wrap plans and visual segments created;
- HarfBuzz layout requests, hits, misses, and evictions;
- visible rows materialized and painted;
- minimap projections;
- framebuffer clears, copies, and bytes presented;
- CPU render duration;
- SDL upload/presentation duration;
- oldest semantic-event-to-present latency.

## A1.2 — Runtime and presentation ownership

Review SDL acquisition, Luna semantic scheduling, scene invalidation, VSync and
software pacing, full-frame CPU rendering, static-frame restoration, animation
composition, and presenter uploads. Preserve C2.4's accepted rule that raw polling
limits never define frame boundaries.

## A1.3 — Text and document scalability

Audit `LunaStaticTextView` complete-document segment construction, repeated
scrollbar-width wrap passes, overlapping suffix shaping, revision invalidation,
line/wrap indexing, pane geometry sharing, Moth snapshot construction, minimap
projection, and shaping-cache behavior.

Required invariants:

```text
normal frame work scales primarily with visible rows plus bounded overscan
one frame does not shape every document line
one document revision is not reprojected independently for every pane
identical revision/width/font/wrap geometry is reusable across panes
scrolling one viewport does not rebuild unrelated rows
editing one logical line does not invalidate every unaffected line
```

## A1.4 — Swift/API and ownership quality

Review Luna/Moth responsibility boundaries, value versus reference semantics,
large value copies, per-frame allocations, lock scope, `@unchecked Sendable`,
mutation ownership, protocol/public API shape, errors, optionals, collection
complexity, UTF-8 safety, and testability seams.

## A1.5 — Tests and documentation

Classify tests as behavioral, architectural, integration, performance,
graphical/manual, or implementation-detail. Add missing end-to-end invariants and
operation-count tests. Reconcile READMEs, roadmaps, status, iteration protocol,
architecture, runtime, geometry, test counts, and phase labels.

## Audit report and decision

Classify every finding as:

```text
Critical — blocks M3A and all new editor features
High — resolve before or during the next corrective phase
Medium — schedule before visible Find/Replace
Low — later cleanup
Accepted Debt — deliberate, bounded, and documented with rationale
```

The report must distinguish measured facts from inference and recommend whether the
next implementation is C2.5 virtualized text layout/demo composition or another
smaller correction. Reconvene before changing source code.
