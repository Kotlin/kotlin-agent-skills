#!/usr/bin/env python3
"""Validate cross-file invariants for kotlin-language-version-features."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ID_RE = re.compile(r"kt\d{2}-[a-z0-9-]+")
HEADING_RE = re.compile(r"^### id: (kt\d{2}-[a-z0-9-]+)\s*$", re.MULTILINE)
STALE_SKILL_TEXT = (
    "per-file `## Features`",
    "Features tables",
    "Latest stability",
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def status_ids(status_index: Path) -> set[str]:
    ids: set[str] = set()
    for line in read(status_index).splitlines():
        if line.startswith("| `kt"):
            match = re.match(r"\| `(kt\d{2}-[a-z0-9-]+)` \|", line)
            if match:
                ids.add(match.group(1))
    return ids


def capsule_blocks(guide_paths: list[Path]) -> dict[str, list[tuple[Path, str]]]:
    blocks: dict[str, list[tuple[Path, str]]] = {}
    for path in guide_paths:
        text = read(path)
        matches = list(HEADING_RE.finditer(text))
        for index, match in enumerate(matches):
            start = match.start()
            end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
            capsule_id = match.group(1)
            blocks.setdefault(capsule_id, []).append((path, text[start:end]))
    return blocks


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    skill_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parents[1]
    references = skill_dir / "references"
    skill_md = skill_dir / "SKILL.md"
    status_index = references / "status-index.md"
    symbol_map = references / "symbol-map.md"
    guides = sorted(references.glob("kotlin-*-feature-guide.md"))

    indexed = status_ids(status_index)
    capsules = capsule_blocks(guides)
    symbol_ids = set(ID_RE.findall(read(symbol_map)))

    missing_capsules = sorted(indexed - set(capsules))
    if missing_capsules:
        fail("status-index ids missing capsules/stubs: " + ", ".join(missing_capsules))

    extra_capsules = sorted(set(capsules) - indexed)
    if extra_capsules:
        fail("capsules/stubs missing status-index rows: " + ", ".join(extra_capsules))

    missing_symbol_ids = sorted(symbol_ids - indexed)
    if missing_symbol_ids:
        fail("symbol-map ids missing status-index rows: " + ", ".join(missing_symbol_ids))

    for capsule_id, entries in capsules.items():
        canonical_count = 0
        for path, block in entries:
            is_stub = "Canonical capsule:" in block
            has_source = "Source:" in block or "Sources:" in block
            if is_stub:
                continue
            canonical_count += 1
            if not has_source:
                fail(f"capsule {capsule_id} in {path} has no source link")
        if canonical_count != 1:
            fail(f"capsule {capsule_id} has {canonical_count} canonical bodies")

    skill_text = read(skill_md)
    for stale in STALE_SKILL_TEXT:
        if stale in skill_text:
            fail(f"stale SKILL.md text remains: {stale}")

    if "Latest stability" in read(symbol_map):
        fail("symbol-map.md must remain reverse lookup only")

    print("kotlin-language-version-features validation passed")


if __name__ == "__main__":
    main()
