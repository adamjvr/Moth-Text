# Luna UI and Moth Text Paired Iteration Protocol

Moth consumes Luna through the Git submodule at `Dependencies/Luna-UI`.

## Required sequence

```text
1. Decide whether the phase exposes a genuinely reusable Luna mechanism.
2. Implement/test that mechanism in Luna, or intentionally keep Luna source frozen.
3. Update permanent Luna checkpoint/roadmap documentation.
4. Commit and push Luna first.
5. Run Moth's scripts/update-luna.sh on the normal Luna main branch.
6. Implement Moth product behavior without editing Luna from the Moth delivery.
7. Stage the intended Luna gitlink and build/test Moth against that exact commit.
8. Run the headless render and plugin-host IPC smoke tests.
9. Require both clean-checkout GitHub Actions jobs to pass.
10. Launch and manually smoke-test Moth.
11. Commit Moth-owned changes and the Luna gitlink update together.
```

Do not add a framework abstraction merely to force every phase to contain Luna
source changes. A documentation-only Luna checkpoint is valid when product work
proves the existing public surface sufficient, as in Convergence C2.

## Updating Luna in Moth

```bash
cd ~/GitHub/Moth-Text
./scripts/update-luna.sh

git -C Dependencies/Luna-UI branch --show-current
git -C Dependencies/Luna-UI log -1 --oneline
git diff --submodule=short Dependencies/Luna-UI
```

The dependency must remain on `main`, not detached.

## Validation

```bash
./scripts/validate-paired-iteration.sh
```

Validation rejects:

- an uninitialized Luna submodule;
- a checkout different from the staged/index gitlink;
- merge conflicts or uncommitted files inside Luna;
- missing SDL2, HarfBuzz, or FreeType development packages;
- failed Moth builds or tests;
- Unicode renderer fallback during the headless render smoke;
- failed plugin-host IPC smoke testing.

## Overlay deliveries

Moth ZIPs are repository overlays, not dependency bundles. They must exclude:

```text
Dependencies/Luna-UI/**
.git/**
.build/**
```

Luna and Moth overlays are always separate. Extract, validate, commit, and push
Luna first; then update the Moth submodule and apply the Moth overlay.

## Commit boundary

A Moth commit may contain:

- Moth-owned sources, tests, resources, scripts, and permanent documentation;
- `Package.swift` changes when required;
- the `Dependencies/Luna-UI` gitlink update.

A Moth commit must not contain copied or patched files from inside Luna.
Temporary validation, extraction, hotfix, delivery, or commit-instruction files do
not belong in either repository.

## Graphical application gate

After automated validation:

```bash
swift run MothTextLinux
```

Verify a real window opens, remains active, renders Luna chrome and Moth text,
resizes correctly, accepts pointer/keyboard interaction, and closes cleanly.
Phase-specific manual checks are performed in addition to this baseline.

Normal startup must not require the optional plugin host. Validate IPC separately:

```bash
./scripts/smoke-test-plugin-host.sh
```

## C2.1 Unicode rendering corrective phase

C2.1 is a real Luna-first source phase rather than a documentation-only
checkpoint. Commit and push Luna's `LunaTextRender` product and tests first, then
advance Moth's submodule and adopt the painter. The Moth delivery must include the
new Package.swift product dependency, MothUnicodeTextPainter, pane/shell adoption,
and graphical regressions.

The C2.1 manual gate has passed. Future paired phases retain accented text,
dirty/active indicators, and Unicode filenames as baseline graphical checks; a
headless UTF-8 storage test alone remains insufficient.

## GitHub Actions gate

The Luna and Moth `CI` workflows run on pushes and pull requests to `main`. The
Moth job initializes submodules, invokes the permanent paired-validation script,
and therefore verifies the same staged-gitlink, headless-render, complete-test, and
IPC contracts used locally. Protect `main` after the first green run and require
these checks before merging.

## M2.2B1 command convergence checkpoint

M2.2B1 reuses Luna's command runtime, menu bar, and quick panel while keeping
Moth command IDs, availability, file lifecycle, editor mutation, and status policy
inside Moth. Integration exposed one product-neutral Luna defect: disabled quick-
panel items disappeared from filtered results. Luna corrects that reusable seam
and adds a focused regression before Moth consumes the new framework revision.

Acceptance requires:

- complete Luna build/test validation at the pinned commit;
- the focused Luna Phase 4A quick-panel regression;
- complete Moth paired validation;
- focused `MothCommandSystemTests`;
- graphical keyboard/menu/palette equivalence;
- clean and dirty New File checks covering Save, Don't Save, and Cancel.

## C2.2 exact geometry and scrolling checkpoint

C2.2 is a Luna-first reusable correction. Luna must be committed and pass:

```bash
swift test --filter LunaTextRenderTests
swift test --filter LunaUIPhase5F2ATests
swift test --filter LunaHostSDLApplicationTests
./scripts/validate-iteration.sh
```

After Moth advances the gitlink, acceptance additionally requires:

```bash
swift test --filter MothTextGeometryAndScrollingTests
./scripts/validate-paired-iteration.sh
```

The graphical gate must exercise rapid long-line typing, combining characters,
wheel and touchpad input over each pane, Page Up/Page Down, scrollbar lane paging,
thumb dragging, capture loss, and caret-follow scrolling. The caret must remain on
the shaped insertion position after every operation.

The next paired slice is M3A document sheets and real tabs. M2.2B2 visible
Find/Replace follows after the active-document targeting model exists.


## C2.3 input-to-pixel latency checkpoint

Commit and validate Luna first:

```bash
swift build
swift test --filter LunaHostPhase5C1Tests
swift test --filter LunaHostSDLApplicationTests
swift test --filter LunaUIPhase5CTests
swift test
./scripts/validate-iteration.sh
git diff --check
```

Graphically run both Luna modes:

```bash
swift run LunaUITestApp
swift run LunaUITestApp --editor
```

After advancing the Moth gitlink, run:

```bash
swift test --filter MothInputLatencyTests
./scripts/validate-paired-iteration.sh
swift run MothTextLinux
./scripts/smoke-test-plugin-host.sh
git diff --check
```

The C2.3 baseline was 115 tests, but C2.3 failed graphical responsiveness acceptance. C2.4 expects 116 tests and must pass native interaction before the paired audit. M3A remains blocked until that audit is reviewed.


## C2.4 interactive runtime checkpoint

Validate and commit Luna first with the focused scheduler and complete gates. Then
advance the exact Luna gitlink and run:

```bash
swift build
swift test --filter MothInputLatencyTests
swift test
./scripts/validate-paired-iteration.sh
swift run MothTextLinux
./scripts/smoke-test-plugin-host.sh
git diff --check
```

Graphically test immediate clicks, menus, shortcuts, navigation, text repeat,
scrolling, pane and scrollbar dragging, resize, and dirty-document dialogs. The
expected Moth total is 116 tests. After acceptance, stop for the A1 paired audit.
