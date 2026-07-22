# Submodule Workflow

## Updating Luna intentionally

```bash
./scripts/update-luna.sh
git add Dependencies/Luna-UI
./scripts/validate-paired-iteration.sh
git status --short
# Add related Moth changes, then commit them together.
```

## Inspecting the pinned revision

```bash
git submodule status Dependencies/Luna-UI
git -C Dependencies/Luna-UI log -1 --oneline
```

## Avoiding common mistakes

- Do not develop inside a detached submodule checkout without first creating or
  switching to a Luna branch.
- Do not commit Moth while Luna contains uncommitted changes that Moth requires.
- Do not advance the gitlink merely to track Luna `main`; advance it for a tested
  compatibility reason.
- Do not place Moth resources or product policy inside the Luna submodule.


## CI interpretation

GitHub Actions checks out the committed gitlink. Local paired validation checks the
index gitlink so a newly advanced Luna revision can be tested before the Moth commit
exists. If validation reports a mismatch after `update-luna.sh`, stage only the
gitlink with `git add Dependencies/Luna-UI` and rerun validation.

## M2.2B1 Luna checkpoint

M2.2B1 advances the Luna gitlink for one reusable quick-panel correction plus
permanent checkpoint documentation. Matching disabled commands remain searchable
so Moth can present an unavailable command and its reason instead of returning an
empty palette result.

Commit and push the validated Luna revision first. Then run
`./scripts/update-luna.sh`, stage only the gitlink, and validate Moth normally.


## C2.2 Luna checkpoint

C2.2 advances the Luna gitlink for exact shaped-row insertion geometry and normal
vertical scrolling mechanics. Commit and push the Luna revision only after the
focused text-render, Phase 5F.2A, SDL-host, and complete validation gates pass.

Then update Moth normally:

```bash
./scripts/update-luna.sh
git add Dependencies/Luna-UI
swift test --filter MothTextGeometryAndScrollingTests
./scripts/validate-paired-iteration.sh
```

The Moth overlay must not contain files below `Dependencies/Luna-UI`; only the git
submodule pointer is committed. C2.4 is the current compatibility checkpoint; the paired audit follows before M3A.


## C2.3 Luna checkpoint

C2.3 advances Luna for frame-fair SDL polling, ordered committed-text coalescing,
input-to-present timing, and the restored default kitchen-sink demo. Commit Luna,
wait for its CI, run `./scripts/update-luna.sh`, stage `Dependencies/Luna-UI`, and
only then run Moth's paired validation. That checkpoint failed graphical
responsiveness acceptance and is retained only as historical context; C2.4 supersedes
its scheduler policy, and A1 is the next paired checkpoint after acceptance.


## C2.4 Luna checkpoint

C2.4 advances Luna from the rejected stateless polling/presentation policy to the
persistent semantic scheduler. Commit and validate Luna first, run native demo
acceptance, advance the Moth gitlink, and then run the 116-test paired gate. The
next checkpoint is the A1 audit, not an automatic M3A implementation.
