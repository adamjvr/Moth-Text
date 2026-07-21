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
7. Build and test Moth against the pinned Luna commit.
8. Launch and manually smoke-test Moth.
9. Run plugin-host IPC smoke testing when IPC code changes or as a final regression.
10. Commit Moth-owned changes and the Luna gitlink update together.
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
- a checkout different from the recorded gitlink when validating a committed tree;
- merge conflicts or uncommitted files inside Luna;
- failed Moth builds or tests.

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
