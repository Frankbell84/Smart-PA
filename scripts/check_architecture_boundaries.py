#!/usr/bin/env python3
"""Fail CI when platform UI or remote-service concerns leak into the core."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "KeyHollow"

PRESENTATION_FILES = {
    "KeyHollow/App/KeyHollowApp.swift",
    "KeyHollow/Photos/SecurePhotoPicker.swift",
    "KeyHollow/Photos/VaultGalleryView.swift",
}
PRESENTATION_PREFIXES = ("KeyHollow/UI/",)

UI_FRAMEWORKS = {"SwiftUI", "UIKit", "Photos", "PhotosUI", "UniformTypeIdentifiers"}
REMOTE_SDKS = {
    "AWSCore",
    "AWSS3",
    "Alamofire",
    "AppCenter",
    "Firebase",
    "GoogleSignIn",
    "Mixpanel",
    "RevenueCat",
    "Sentry",
    "Segment",
    "Supabase",
}
CORE_PREFIXES = (
    "KeyHollow/Security/",
    "KeyHollow/Session/",
    "KeyHollow/Storage/",
    "KeyHollow/Transfer/",
)
CORE_PHOTO_FILES = {
    "KeyHollow/Photos/VaultPhotoModels.swift",
    "KeyHollow/Photos/VaultPhotoStore.swift",
}


def relative(file: Path) -> str:
    return file.relative_to(ROOT).as_posix()


def is_presentation(path: str) -> bool:
    return path in PRESENTATION_FILES or path.startswith(PRESENTATION_PREFIXES)


def imports(source: str) -> set[str]:
    return set(re.findall(r"(?m)^import\s+([A-Za-z0-9_]+)\s*$", source))


def main() -> int:
    violations: list[str] = []
    swift_files = sorted(SOURCE_ROOT.rglob("*.swift"))

    for file in swift_files:
        path = relative(file)
        source = file.read_text(encoding="utf-8")
        imported = imports(source)

        leaked_ui = imported & UI_FRAMEWORKS
        if leaked_ui and not is_presentation(path):
            violations.append(
                f"{path}: UI/system-photo frameworks outside the presentation adapter: "
                f"{', '.join(sorted(leaked_ui))}"
            )

        leaked_remote = imported & REMOTE_SDKS
        if leaked_remote:
            violations.append(
                f"{path}: remote SDK entered the local-only app core: "
                f"{', '.join(sorted(leaked_remote))}"
            )

        is_core = path.startswith(CORE_PREFIXES) or path in CORE_PHOTO_FILES
        if is_core:
            for forbidden_symbol in (
                "PHPhotoLibrary",
                "PhotosPicker",
                "UIApplication",
                "UIViewController",
            ):
                if re.search(rf"\b{forbidden_symbol}\b", source):
                    violations.append(
                        f"{path}: core code directly references {forbidden_symbol}"
                    )

            if re.search(r"\bURLSession\b", source):
                violations.append(f"{path}: core code introduced a network session")

    if violations:
        print("Architecture boundary violations:", file=sys.stderr)
        for violation in violations:
            print(f"- {violation}", file=sys.stderr)
        return 1

    print(
        "Architecture boundaries passed: core storage, cryptography, session, "
        "and transfer code remain free of UI, Photos, network, and remote SDK concerns."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
