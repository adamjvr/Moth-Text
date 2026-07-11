#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

output="${1:-Moth-Text-overlay.zip}"
case "$output" in
    /*) ;;
    *) output="$repo_root/$output" ;;
esac

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git status --porcelain --untracked-files=all -- Dependencies/Luna-UI | grep -q .; then
        echo "Refusing to package: the Luna-UI submodule path has changes." >&2
        exit 1
    fi
fi

rm -f "$output"

python3 - "$repo_root" "$output" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
excluded_roots = {'.git', '.build', '.swiftpm', 'Dependencies'}
excluded_files = {'.DS_Store'}
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted(root.rglob('*')):
        rel = p.relative_to(root)
        if not rel.parts or rel.parts[0] in excluded_roots:
            continue
        if p.is_dir() or p.name in excluded_files or p.resolve() == out:
            continue
        z.write(p, rel.as_posix())
with zipfile.ZipFile(out) as z:
    bad = [n for n in z.namelist() if n.startswith('Dependencies/Luna-UI/')]
    if bad:
        raise SystemExit('overlay unexpectedly contains Luna-UI paths')
print(out)
PY

echo "Created Moth-owned overlay with Dependencies excluded: $output"
