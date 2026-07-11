#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

git submodule update --init --recursive Dependencies/Luna-UI
git -C Dependencies/Luna-UI fetch --all --tags
git -C Dependencies/Luna-UI switch main
git -C Dependencies/Luna-UI pull --ff-only

cat <<'MSG'
Luna-UI has been advanced in the working tree.
Run the Moth build/tests, then commit the updated Dependencies/Luna-UI gitlink.
MSG
