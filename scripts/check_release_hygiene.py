#!/usr/bin/env python3
"""Fail CI when release branches contain abandoned or editor-generated files."""

from __future__ import annotations

import fnmatch
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IGNORED_DIRECTORIES = {".git", "build", "DerivedData"}
BANNED_NAMES = {".DS_Store", "Thumbs.db"}
BANNED_PATTERNS = ("*.bak", "*.orig", "*.rej", "*.swp", "*.tmp", "*~")


def main() -> int:
    violations: list[str] = []

    for path in ROOT.rglob("*"):
        relative_parts = path.relative_to(ROOT).parts
        if any(part in IGNORED_DIRECTORIES for part in relative_parts):
            continue
        if path.is_dir() and path.name == "xcuserdata":
            violations.append(f"{path.relative_to(ROOT).as_posix()}: user workspace data")
            continue
        if not path.is_file():
            continue
        if path.name in BANNED_NAMES or any(
            fnmatch.fnmatch(path.name, pattern) for pattern in BANNED_PATTERNS
        ):
            violations.append(f"{path.relative_to(ROOT).as_posix()}: temporary file")

    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    for abandoned_marker in ("CFBundleTypeIconFiles", "UTTypeIcons:"):
        if abandoned_marker in project:
            violations.append(
                f"project.yml: abandoned icon attempt remains ({abandoned_marker})"
            )

    legacy_icons = ROOT / "KeyHollow" / "Resources" / "DocumentIcons"
    if legacy_icons.exists() and any(legacy_icons.iterdir()):
        violations.append(
            "KeyHollow/Resources/DocumentIcons: unused legacy icon assets remain"
        )

    if violations:
        print("Release hygiene violations:", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    print(
        "Release hygiene passed: no editor debris, temporary files, or abandoned "
        "document-icon implementations are present."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
