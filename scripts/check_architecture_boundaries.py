#!/usr/bin/env python3
"""Fail CI when platform UI or remote-service concerns leak into the core."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "KeyHollow"
PROJECT_FILE = ROOT / "project.yml"

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
CRYPTO_MODULE_PREFIXES = ("KeyHollow/ThirdParty/Argon2id/",)
CRYPTO_MODULE_FILES = {"KeyHollow/Security/CryptoBox.swift"}
VAULT_MODULE_FILES = {
    "KeyHollow/Security/KeyDerivation.swift",
    "KeyHollow/Security/PasscodePolicy.swift",
    "KeyHollow/Security/VaultEnvelope.swift",
    "KeyHollow/Security/VaultLocator.swift",
    "KeyHollow/Storage/VaultStore.swift",
}
PHOTO_MODULE_FILES = {
    "KeyHollow/Photos/VaultPhotoCryptographicAccess.swift",
    "KeyHollow/Photos/VaultPhotoModels.swift",
    "KeyHollow/Photos/VaultPhotoStore.swift",
}
PHOTOS_ADAPTER_FILES = {
    "KeyHollow/Photos/PhotoLibraryAdapter.swift",
}
TRANSFER_MODULE_FILES = {
    "KeyHollow/Transfer/PortableArchiveContainer.swift",
    "KeyHollow/Transfer/PortableArchiveSecurity.swift",
    "KeyHollow/Transfer/PortableArchivePayload.swift",
    "KeyHollow/Transfer/PortableVaultRestoreTransactionJournal.swift",
    "KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift",
}


def relative(file: Path) -> str:
    return file.relative_to(ROOT).as_posix()


def is_presentation(path: str) -> bool:
    return path in PRESENTATION_FILES or path.startswith(PRESENTATION_PREFIXES)


def imports(source: str) -> set[str]:
    return set(
        re.findall(
            r"(?m)^(?:@preconcurrency\s+)?import\s+([A-Za-z0-9_]+)\s*$",
            source,
        )
    )


def main() -> int:
    violations: list[str] = []
    swift_files = sorted(SOURCE_ROOT.rglob("*.swift"))

    project = PROJECT_FILE.read_text(encoding="utf-8")
    required_crypto_module_markers = (
        "KeyHollowCryptoCore:",
        "- path: KeyHollow/Security/CryptoBox.swift",
        "- path: KeyHollow/ThirdParty/Argon2id",
        "- target: KeyHollowCryptoCore",
        "- Security/CryptoBox.swift",
        "- ThirdParty/Argon2id",
    )
    for marker in required_crypto_module_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled crypto boundary is missing {marker!r}"
            )

    required_vault_module_markers = (
        "KeyHollowVaultCore:",
        "- path: KeyHollow/Security/KeyDerivation.swift",
        "- path: KeyHollow/Security/PasscodePolicy.swift",
        "- path: KeyHollow/Security/VaultEnvelope.swift",
        "- path: KeyHollow/Security/VaultLocator.swift",
        "- path: KeyHollow/Storage/VaultStore.swift",
        "- target: KeyHollowVaultCore",
        "- Security/KeyDerivation.swift",
        "- Security/PasscodePolicy.swift",
        "- Security/VaultEnvelope.swift",
        "- Security/VaultLocator.swift",
        "- Storage/VaultStore.swift",
    )
    for marker in required_vault_module_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled vault boundary is missing {marker!r}"
            )

    required_photo_module_markers = (
        "KeyHollowPhotoCore:",
        "- path: KeyHollow/Photos/VaultPhotoCryptographicAccess.swift",
        "- path: KeyHollow/Photos/VaultPhotoModels.swift",
        "- path: KeyHollow/Photos/VaultPhotoStore.swift",
        "- target: KeyHollowPhotoCore",
        "- Photos/VaultPhotoCryptographicAccess.swift",
        "- Photos/VaultPhotoModels.swift",
        "- Photos/VaultPhotoStore.swift",
    )
    for marker in required_photo_module_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled photo-storage boundary is missing {marker!r}"
            )

    required_photos_adapter_markers = (
        "KeyHollowPhotosAdapter:",
        "- path: KeyHollow/Photos/PhotoLibraryAdapter.swift",
        "- target: KeyHollowPhotosAdapter",
        "- Photos/PhotoLibraryAdapter.swift",
    )
    for marker in required_photos_adapter_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled Photos adapter boundary is missing {marker!r}"
            )

    required_transfer_module_markers = (
        "KeyHollowTransferCore:",
        "- path: KeyHollow/Transfer/PortableArchiveContainer.swift",
        "- path: KeyHollow/Transfer/PortableArchiveSecurity.swift",
        "- path: KeyHollow/Transfer/PortableArchivePayload.swift",
        "- path: KeyHollow/Transfer/PortableVaultRestoreTransactionJournal.swift",
        "- path: KeyHollow/Transfer/EncryptedVaultTransferCoordinator.swift",
        "- target: KeyHollowTransferCore",
        "- Transfer/PortableArchiveContainer.swift",
        "- Transfer/PortableArchiveSecurity.swift",
        "- Transfer/PortableArchivePayload.swift",
        "- Transfer/PortableVaultRestoreTransactionJournal.swift",
        "- Transfer/EncryptedVaultTransferCoordinator.swift",
    )
    for marker in required_transfer_module_markers:
        if marker not in project:
            violations.append(
                f"project.yml: compiled transfer boundary is missing {marker!r}"
            )

    for file in swift_files:
        path = relative(file)
        source = file.read_text(encoding="utf-8")
        imported = imports(source)

        if path in CRYPTO_MODULE_FILES or path.startswith(CRYPTO_MODULE_PREFIXES):
            unexpected = imported - {"CryptoKit", "Foundation"}
            if unexpected:
                violations.append(
                    f"{path}: crypto module imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path in VAULT_MODULE_FILES:
            unexpected = imported - {
                "CryptoKit",
                "Foundation",
                "KeyHollowCryptoCore",
                "Security",
            }
            if unexpected:
                violations.append(
                    f"{path}: vault module imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path in PHOTO_MODULE_FILES:
            unexpected = imported - {
                "CryptoKit",
                "Foundation",
                "KeyHollowCryptoCore",
            }
            if unexpected:
                violations.append(
                    f"{path}: photo-storage module imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path in PHOTOS_ADAPTER_FILES:
            unexpected = imported - {
                "Foundation",
                "Photos",
                "PhotosUI",
                "UIKit",
            }
            if unexpected:
                violations.append(
                    f"{path}: Photos adapter imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if path in TRANSFER_MODULE_FILES:
            unexpected = imported - {
                "CryptoKit",
                "Foundation",
                "KeyHollowCryptoCore",
                "KeyHollowPhotoCore",
                "KeyHollowVaultCore",
                "Security",
            }
            if unexpected:
                violations.append(
                    f"{path}: transfer module imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        leaked_ui = imported & UI_FRAMEWORKS
        if leaked_ui and not is_presentation(path) and path not in PHOTOS_ADAPTER_FILES:
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
        "Architecture boundaries passed: KeyHollowCryptoCore, "
        "KeyHollowVaultCore, KeyHollowPhotoCore, KeyHollowPhotosAdapter, and "
        "KeyHollowTransferCore remain separately compiled, and core storage, "
        "cryptography, session, and transfer code "
        "remain free of UI, Photos, network, and remote SDK concerns."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

