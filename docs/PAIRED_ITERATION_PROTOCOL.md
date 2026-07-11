# Luna UI and Moth Text Paired Iteration Protocol

Moth Text consumes Luna UI through the real Git submodule at `Dependencies/Luna-UI`.

## Required Sequence

```text
1. Implement the Luna change in the Luna-UI repository.
2. Build and test Luna UI.
3. Commit and push Luna UI.
4. Update Moth's Luna submodule checkout.
5. Implement the Moth integration without editing Luna from the Moth delivery.
6. Build and test Moth Text against the pinned Luna commit.
7. Launch and manually smoke-test the Moth application.
8. Run the optional plugin-host IPC smoke test when IPC code changes.
9. Commit Moth-owned changes and the submodule gitlink update.
```

## Updating Luna in Moth

```bash
cd Dependencies/Luna-UI
git switch main
git pull --ff-only
cd ../..

git submodule status
git diff --submodule=log -- Dependencies/Luna-UI
```

## Validation

```bash
./scripts/validate-paired-iteration.sh
```

The validation rejects:

- an uninitialized Luna submodule;
- a Luna checkout at a revision different from the recorded gitlink;
- merge conflicts in the submodule;
- uncommitted files inside Luna;
- failed Moth builds or tests.

## Moth Deliveries

Moth ZIPs are overlays, not complete dependency bundles. They must exclude:

```text
Dependencies/Luna-UI/**
```

Create a safe overlay with:

```bash
./scripts/package-overlay.sh /tmp/Moth-Text-phase-overlay.zip
```

The overlay is extracted into the Moth repository only after the user updates the Luna submodule normally with Git.

## Commit Boundary

A Moth commit may contain:

- Moth-owned sources, tests, resources, scripts, and documentation;
- `Package.swift` changes;
- the `Dependencies/Luna-UI` gitlink update.

A Moth commit must not contain copied or patched files from within Luna UI.


## Application smoke-test gate

After automated validation succeeds, run:

```bash
swift run MothTextLinux
```

Normal application startup must not require the optional plugin host. When IPC or plugin-host code changes, also run:

```bash
./scripts/smoke-test-plugin-host.sh
```

The plugin-host executable product is named `MothPluginHost`.
