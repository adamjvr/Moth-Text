# Submodule Workflow

## Updating Luna intentionally

```bash
./scripts/update-luna.sh
./scripts/test-all.sh
git status --short
git add Dependencies/Luna-UI
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
