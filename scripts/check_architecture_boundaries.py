#!/usr/bin/env python3
"""Fail CI when platform UI or remote-service concerns leak into the core."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "KeyHollow"
PROJECT_FILE = ROOT / "project.yml"
ADDON_ROOT = SOURCE_ROOT / "AddOns"
THUMBNAIL_EXTENSION_ROOT = ROOT / "KeyHollowVaultThumbnailExtension"

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
FILE_RECOGNITION_PREFIX = "KeyHollow/AddOns/FileRecognition/"
GENERAL_FILE_SUPPORT_PREFIX = "KeyHollow/AddOns/GeneralFileSupport/"
SECURITY_SCOPED_INGRESS_PREFIXES = (
    FILE_RECOGNITION_PREFIX,
    GENERAL_FILE_SUPPORT_PREFIX,
)


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


def target_body(project: str, target: str) -> str | None:
    match = re.search(
        rf"(?ms)^  {re.escape(target)}:\s*$\n(?P<body>.*?)(?=^  [A-Za-z0-9_]+:\s*$|^schemes:\s*$)",
        project,
    )
    return match.group("body") if match else None


def main() -> int:
    violations: list[str] = []
    swift_files = sorted(SOURCE_ROOT.rglob("*.swift"))

    project = PROJECT_FILE.read_text(encoding="utf-8")
    app_target = target_body(project, "KeyHollow")
    if app_target is None:
        violations.append("project.yml: application target KeyHollow is missing")

    addon_modules: set[str] = set()
    if ADDON_ROOT.exists():
        for addon_directory in sorted(path for path in ADDON_ROOT.iterdir() if path.is_dir()):
            addon_sources = sorted(addon_directory.rglob("*.swift"))
            if not addon_sources:
                continue

            addon_name = addon_directory.name
            if re.fullmatch(r"[A-Z][A-Za-z0-9]*", addon_name) is None:
                violations.append(
                    f"KeyHollow/AddOns/{addon_name}: add-on directory must use UpperCamelCase"
                )
                continue

            target = f"KeyHollow{addon_name}AddOn"
            addon_modules.add(target)
            body = target_body(project, target)
            if body is None:
                violations.append(
                    f"KeyHollow/AddOns/{addon_name}: missing compiled target {target}"
                )
                continue

            if re.search(r"(?m)^    type:\s*library\.static\s*$", body) is None:
                violations.append(f"project.yml: {target} must be a static library")

            if "SWIFT_TREAT_WARNINGS_AS_ERRORS: YES" not in body:
                violations.append(
                    f"project.yml: {target} must compile Swift warnings as errors"
                )

            source_marker = f"- path: KeyHollow/AddOns/{addon_name}"
            if source_marker not in body:
                violations.append(
                    f"project.yml: {target} must own {source_marker!r}"
                )

            dependency_marker = f"- target: {target}"
            if app_target is not None and dependency_marker not in app_target:
                violations.append(
                    f"project.yml: KeyHollow must compose {target} explicitly"
                )

            exclusion_marker = f"- AddOns/{addon_name}"
            if app_target is not None and exclusion_marker not in app_target:
                violations.append(
                    f"project.yml: KeyHollow must exclude {exclusion_marker!r} "
                    "so the add-on is compiled only in its own target"
                )
    thumbnail_target = target_body(project, "KeyHollowVaultThumbnailExtension")
    required_thumbnail_markers = (
        "type: app-extension",
        "- path: KeyHollowVaultThumbnailExtension",
        "- path: KeyHollowVaultThumbnailExtension/Resources/Assets.xcassets",
        "buildPhase: resources",
        "PRODUCT_BUNDLE_IDENTIFIER: com.keyhollow.app.vault-thumbnail",
        "APPLICATION_EXTENSION_API_ONLY: YES",
        "NSExtensionPointIdentifier: com.apple.quicklook.thumbnail",
        "- com.keyhollow.encrypted-vault",
        "- target: KeyHollowVaultThumbnailExtension",
        "embed: true",
    )
    if thumbnail_target is None:
        violations.append(
            "project.yml: isolated KeyHollowVaultThumbnailExtension target is missing"
        )
    else:
        for marker in required_thumbnail_markers[:-2]:
            if marker not in thumbnail_target:
                violations.append(
                    f"project.yml: thumbnail extension is missing {marker!r}"
                )
        if app_target is not None:
            for marker in required_thumbnail_markers[-2:]:
                if marker not in app_target:
                    violations.append(
                        f"project.yml: app embedding is missing {marker!r}"
                    )

    if "CFBundleTypeIconFiles" in project or "UTTypeIcons:" in project:
        violations.append(
            "project.yml: abandoned document-icon metadata must not coexist "
            "with the thumbnail extension"
        )

    thumbnail_sources = (
        sorted(THUMBNAIL_EXTENSION_ROOT.rglob("*.swift"))
        if THUMBNAIL_EXTENSION_ROOT.exists()
        else []
    )
    if [relative(path) for path in thumbnail_sources] != [
        "KeyHollowVaultThumbnailExtension/ThumbnailProvider.swift"
    ]:
        violations.append(
            "KeyHollowVaultThumbnailExtension: expected exactly ThumbnailProvider.swift"
        )

    for file in thumbnail_sources:
        source = file.read_text(encoding="utf-8")
        unexpected = imports(source) - {"QuickLookThumbnailing", "UIKit"}
        if unexpected:
            violations.append(
                f"{relative(file)}: thumbnail extension imports outside its allowlist: "
                f"{', '.join(sorted(unexpected))}"
            )
        for forbidden in (
            "request.fileURL",
            "Data(contentsOf:",
            "FileHandle",
            "CryptoKit",
            "KeyHollowCryptoCore",
            "KeyHollowVaultCore",
            "KeyHollowPhotoCore",
            "KeyHollowTransferCore",
            "URLSession",
        ):
            if forbidden in source:
                violations.append(
                    f"{relative(file)}: thumbnail extension must not access vault "
                    f"data or protected services ({forbidden})"
                )

    approved_app_icon = (
        ROOT
        / "KeyHollow"
        / "Resources"
        / "Assets.xcassets"
        / "AppIcon.appiconset"
        / "AppIcon.png"
    )
    thumbnail_icon = (
        THUMBNAIL_EXTENSION_ROOT
        / "Resources"
        / "Assets.xcassets"
        / "KeyHollowVaultIcon.imageset"
        / "KeyHollowVaultIcon.png"
    )
    if not thumbnail_icon.is_file():
        violations.append(
            "KeyHollowVaultThumbnailExtension: approved thumbnail icon is missing"
        )
    elif not approved_app_icon.is_file():
        violations.append("KeyHollow: approved app icon is missing")
    elif thumbnail_icon.read_bytes() != approved_app_icon.read_bytes():
        violations.append(
            "KeyHollowVaultThumbnailExtension: thumbnail icon must remain a "
            "byte-for-byte copy of the approved app icon"
        )

    legacy_icons = ROOT / "KeyHollow" / "Resources" / "DocumentIcons"
    if legacy_icons.exists() and any(legacy_icons.iterdir()):
        violations.append(
            "KeyHollow/Resources/DocumentIcons: legacy icon assets must be removed"
        )

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

        if path.startswith("KeyHollow/AddOns/") and "KeyHollow" in imported:
            violations.append(
                f"{path}: add-on module imports the application target instead of a narrow interface"
            )

        if path.startswith(FILE_RECOGNITION_PREFIX):
            unexpected = imported - {"Foundation"}
            if unexpected:
                violations.append(
                    f"{path}: file-recognition add-on imports outside its allowlist: "
                    f"{', '.join(sorted(unexpected))}"
                )

        if (
            "startAccessingSecurityScopedResource" in source
            and not path.startswith(SECURITY_SCOPED_INGRESS_PREFIXES)
        ):
            violations.append(
                f"{path}: security-scoped file access must remain inside an "
                "approved file-ingress add-on"
            )

        if (
            "KeyHollowPortableImports" in source
            and not path.startswith(FILE_RECOGNITION_PREFIX)
        ):
            violations.append(
                f"{path}: incoming vault staging must remain inside the "
                "file-recognition add-on"
            )

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
            leaked_addons = imported & addon_modules
            if leaked_addons:
                violations.append(
                    f"{path}: protected core imports add-on modules: "
                    f"{', '.join(sorted(leaked_addons))}"
                )

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
        "Architecture boundaries passed: KeyHollowVaultThumbnailExtension, "
        "KeyHollowCryptoCore, "
        "KeyHollowVaultCore, KeyHollowPhotoCore, KeyHollowPhotosAdapter, and "
        "KeyHollowTransferCore remain separately compiled; registered add-ons "
        "remain independently compiled; and core storage, "
        "cryptography, session, and transfer code "
        "remain free of UI, Photos, network, and remote SDK concerns."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

