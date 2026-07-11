#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

socket_path="/tmp/mothtext.sock"
rm -f "$socket_path"

host_log="$(mktemp)"
host_pid=""

cleanup() {
    if [[ -n "$host_pid" ]]; then
        kill "$host_pid" 2>/dev/null || true
        wait "$host_pid" 2>/dev/null || true
    fi
    rm -f "$socket_path" "$host_log"
}
trap cleanup EXIT

echo "==> Starting MothPluginHost"
swift run MothPluginHost >"$host_log" 2>&1 &
host_pid=$!

for _ in {1..50}; do
    if [[ -S "$socket_path" ]]; then
        break
    fi
    if ! kill -0 "$host_pid" 2>/dev/null; then
        cat "$host_log" >&2
        echo "MothPluginHost exited before creating its socket." >&2
        exit 1
    fi
    sleep 0.1
done

if [[ ! -S "$socket_path" ]]; then
    cat "$host_log" >&2
    echo "Timed out waiting for MothPluginHost socket at $socket_path." >&2
    exit 1
fi

echo "==> Running MothTextLinux IPC smoke client"
swift run MothTextLinux --ipc-smoke

echo "Moth plugin-host IPC smoke test passed."
