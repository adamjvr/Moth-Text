#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -e

PREFIX="${HOME}/.local"
rm -f "${PREFIX}/bin/moth-text"
rm -f "${PREFIX}/share/applications/io.github.adamjvr.MothText.desktop"
find "${PREFIX}/share/icons/hicolor" \
    -type f \
    -path '*/apps/io.github.adamjvr.MothText.png' \
    -delete 2>/dev/null || true

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${PREFIX}/share/applications" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "${PREFIX}/share/icons/hicolor" >/dev/null 2>&1 || true
fi

printf 'Removed the current-user Moth Text launcher, binary, and icons.\n'
