#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

requested_sha="${1:?usage: update-luna-exact.sh <40-character-luna-sha>}"
[[ "$requested_sha" =~ ^[0-9a-f]{40}$ ]] || {
  echo "error: Luna SHA must be exactly 40 lowercase hexadecimal characters" >&2
  exit 2
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
luna="$repo_root/Dependencies/Luna-UI"
cd "$repo_root"

git submodule sync -- Dependencies/Luna-UI
git submodule update --init --checkout Dependencies/Luna-UI
if ! git -C "$luna" diff --quiet || ! git -C "$luna" diff --cached --quiet; then
  echo "error: Dependencies/Luna-UI contains tracked local changes" >&2
  exit 1
fi

git -C "$luna" fetch --prune origin c2.5g-runtime-attribution
remote_sha="$(git -C "$luna" rev-parse origin/c2.5g-runtime-attribution)"
[[ "$remote_sha" == "$requested_sha" ]] || {
  echo "error: remote C2.5G branch is $remote_sha, not requested $requested_sha" >&2
  exit 1
}

git -C "$luna" cat-file -e "$requested_sha^{commit}"
git -C "$luna" checkout --detach "$requested_sha"
checked_out="$(git -C "$luna" rev-parse HEAD)"
[[ "$checked_out" == "$requested_sha" ]] || exit 1

git add Dependencies/Luna-UI
staged="$(git ls-files --stage Dependencies/Luna-UI | awk '{print $2}')"
[[ "$staged" == "$requested_sha" ]] || {
  echo "error: staged gitlink is $staged, not $requested_sha" >&2
  exit 1
}

printf 'requested Luna: %s\nremote branch:  %s\nchecked out:    %s\nstaged gitlink: %s\n' \
  "$requested_sha" "$remote_sha" "$checked_out" "$staged"
