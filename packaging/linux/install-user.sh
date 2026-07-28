#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -e

REPO="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PREFIX="${HOME}/.local"
BIN_DIR="${PREFIX}/bin"
APP_DIR="${PREFIX}/share/applications"
ICON_ROOT="${PREFIX}/share/icons/hicolor"

if [[ ! -f "${REPO}/Package.swift" ]]; then
    printf 'error: Moth repository not found: %s\n' "${REPO}" >&2
    exit 1
fi

printf 'Building release MothTextLinux...\n'
cd "${REPO}"
swift build -c release --product MothTextLinux
BIN_PATH="$(swift build -c release --show-bin-path)/MothTextLinux"

install -d "${BIN_DIR}" "${APP_DIR}"
install -m 0755 "${BIN_PATH}" "${BIN_DIR}/moth-text"
install -m 0644 \
    "${REPO}/packaging/linux/io.github.adamjvr.MothText.desktop" \
    "${APP_DIR}/io.github.adamjvr.MothText.desktop"

while IFS= read -r -d '' icon; do
    rel="${icon#${REPO}/packaging/linux/hicolor/}"
    target="${ICON_ROOT}/${rel}"
    install -d "$(dirname "${target}")"
    install -m 0644 "${icon}" "${target}"
done < <(find "${REPO}/packaging/linux/hicolor" -type f -name '*.png' -print0)

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APP_DIR}" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "${ICON_ROOT}" >/dev/null 2>&1 || true
fi

printf 'Installed Moth Text launcher and icon for %s.\n' "${USER}"
printf 'Binary:  %s\n' "${BIN_DIR}/moth-text"
printf 'Desktop: %s\n' "${APP_DIR}/io.github.adamjvr.MothText.desktop"
