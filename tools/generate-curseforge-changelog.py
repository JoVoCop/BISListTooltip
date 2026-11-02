#!/usr/bin/env python3
"""Combine the newest changelogs into output/curseforge-changelog.md for the CurseForge upload."""

import re
import sys
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
CHANGELOGS_DIR = REPO_DIR / "changelogs"
OUTPUT_FILE = REPO_DIR / "output" / "curseforge-changelog.md"
ENTRIES_TO_KEEP = 4
SEPARATOR = "\n\n---\n\n"
VERSION_FILE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)\.md$")


def version_key(path: Path) -> tuple[int, int, int]:
    match = VERSION_FILE.match(path.name)
    if match is None:
        raise ValueError(f"not a vMAJOR.MINOR.PATCH.md changelog: {path.name}")
    major, minor, patch = match.groups()
    return int(major), int(minor), int(patch)


def newest_changelogs(changelogs_dir: Path, count: int = ENTRIES_TO_KEEP) -> list[Path]:
    # Sorting by name would put v1.9.0 after v1.10.0.
    candidates = [path for path in changelogs_dir.iterdir() if VERSION_FILE.match(path.name)]
    return sorted(candidates, key=version_key, reverse=True)[:count]


def combine(changelogs_dir: Path) -> str:
    return SEPARATOR.join(path.read_text(encoding="utf-8") for path in newest_changelogs(changelogs_dir))


def main() -> int:
    if not CHANGELOGS_DIR.is_dir():
        print(f"Error: {CHANGELOGS_DIR} does not exist", file=sys.stderr)
        return 1
    text = combine(CHANGELOGS_DIR)
    if not text:
        print(f"Error: no vX.Y.Z.md changelogs in {CHANGELOGS_DIR}", file=sys.stderr)
        return 1
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
