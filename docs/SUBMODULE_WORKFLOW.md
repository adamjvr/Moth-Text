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
