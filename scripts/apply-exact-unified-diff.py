#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Apply C2.5D2R2 by exact old-hunk matching after baseline SHA guards."""
from __future__ import annotations
import argparse
import dataclasses
import os
from pathlib import Path
import stat
import sys
import tempfile

@dataclasses.dataclass(frozen=True)
class Hunk:
    old_lines: tuple[str, ...]
    new_lines: tuple[str, ...]
    header: str

@dataclasses.dataclass(frozen=True)
class FilePatch:
    old_path: str
    new_path: str
    hunks: tuple[Hunk, ...]

class PatchError(RuntimeError):
    pass

def strip_ab_prefix(path: str) -> str:
    return path[2:] if path.startswith(('a/', 'b/')) else path

def parse_patch(path: Path) -> tuple[FilePatch, ...]:
    raw_lines = path.read_text(encoding='utf-8').splitlines(keepends=True)
    file_patches: list[FilePatch] = []
    index = 0
    while index < len(raw_lines):
        line = raw_lines[index]
        if not line.startswith('--- '):
            index += 1
            continue
        old_path = line[4:].strip().split('\t', 1)[0]
        index += 1
        if index >= len(raw_lines) or not raw_lines[index].startswith('+++ '):
            raise PatchError(f'missing +++ header after {old_path}')
        new_path = raw_lines[index][4:].strip().split('\t', 1)[0]
        index += 1
        hunks: list[Hunk] = []
        while index < len(raw_lines) and not raw_lines[index].startswith('--- '):
            if not raw_lines[index].startswith('@@ '):
                index += 1
                continue
            header = raw_lines[index].rstrip('\n')
            index += 1
            old_lines: list[str] = []
            new_lines: list[str] = []
            while index < len(raw_lines):
                hunk_line = raw_lines[index]
                if hunk_line.startswith('@@ ') or hunk_line.startswith('--- '):
                    break
                if hunk_line.startswith('\\ No newline at end of file'):
                    index += 1
                    continue
                if hunk_line.startswith('+'):
                    new_lines.append(hunk_line[1:])
                elif hunk_line.startswith('-'):
                    old_lines.append(hunk_line[1:])
                elif hunk_line.startswith(' '):
                    payload = hunk_line[1:]
                    old_lines.append(payload)
                    new_lines.append(payload)
                elif hunk_line in ('\n', '\r\n', ''):
                    old_lines.append(hunk_line)
                    new_lines.append(hunk_line)
                else:
                    raise PatchError(
                        f'unsupported line in {old_path} {header}: {hunk_line!r}'
                    )
                index += 1
            if not old_lines:
                raise PatchError(f'empty old body in {old_path} {header}')
            hunks.append(Hunk(tuple(old_lines), tuple(new_lines), header))
        if not hunks:
            raise PatchError(f'no hunks found for {old_path}')
        file_patches.append(FilePatch(
            strip_ab_prefix(old_path),
            strip_ab_prefix(new_path),
            tuple(hunks),
        ))
    if not file_patches:
        raise PatchError(f'no file patches found in {path}')
    return tuple(file_patches)

def all_occurrences(haystack: str, needle: str) -> list[int]:
    positions: list[int] = []
    cursor = 0
    while True:
        found = haystack.find(needle, cursor)
        if found < 0:
            return positions
        positions.append(found)
        cursor = found + 1

def apply_file_patch(repo_root: Path, patch: FilePatch) -> tuple[Path, str]:
    if patch.old_path != patch.new_path:
        raise PatchError(f'renames unsupported: {patch.old_path} -> {patch.new_path}')
    target = repo_root / patch.new_path
    if not target.is_file():
        raise PatchError(f'target file does not exist: {target}')
    original = target.read_text(encoding='utf-8')
    updated = original
    search_cursor = 0
    for ordinal, hunk in enumerate(patch.hunks, start=1):
        old_body = ''.join(hunk.old_lines)
        new_body = ''.join(hunk.new_lines)
        position = updated.find(old_body, search_cursor)
        if position < 0:
            positions = all_occurrences(updated, old_body)
            if len(positions) == 1:
                position = positions[0]
            elif not positions:
                raise PatchError(
                    f'{patch.new_path}: old body for hunk {ordinal} not found '
                    f'({hunk.header})'
                )
            else:
                raise PatchError(
                    f'{patch.new_path}: old body for hunk {ordinal} ambiguous '
                    f'at {positions} ({hunk.header})'
                )
        updated = updated[:position] + new_body + updated[position + len(old_body):]
        search_cursor = position + len(new_body)
    if updated == original:
        raise PatchError(f'{patch.new_path}: patch produced no change')
    return target, updated

def atomic_write(path: Path, content: str) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    fd, temporary_name = tempfile.mkstemp(
        prefix=f'.{path.name}.', suffix='.c25d2r2.tmp', dir=path.parent, text=True
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='') as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo-root', required=True, type=Path)
    parser.add_argument('--patch', required=True, type=Path)
    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    patch_path = args.patch if args.patch.is_absolute() else (repo_root / args.patch)
    try:
        parsed = parse_patch(patch_path.resolve())
        replacements = [apply_file_patch(repo_root, p) for p in parsed]
        for target, content in replacements:
            atomic_write(target, content)
            print(f'applied exact hunks: {target.relative_to(repo_root)}')
        print(f'applied {sum(len(p.hunks) for p in parsed)} exact hunks across {len(parsed)} files')
        return 0
    except (OSError, PatchError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1

if __name__ == '__main__':
    raise SystemExit(main())
