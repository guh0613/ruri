#!/usr/bin/env python3
"""Configure distribution metadata and bundled service credentials before signing."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
KEY_VARIABLE = "RURI_CURSEFORGE_API_KEY"


def configure_metadata(path: Path) -> None:
    with path.open("rb") as source:
        info = plistlib.load(source)
    resources = ROOT / "Sources/RuriLocalization/Resources"
    info["CFBundleDevelopmentRegion"] = "zh-Hans"
    info["CFBundleLocalizations"] = sorted(p.stem for p in resources.glob("*.lproj"))
    version = os.environ.get("RURI_VERSION") or info.get("RuriVersion") or info["CFBundleShortVersionString"]
    number = r"(?:0|[1-9][0-9]*)"
    identifier = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    match = re.fullmatch(rf"({number}\.{number}\.{number})(?:-{identifier}(?:\.{identifier})*)?", version)
    if not match:
        raise ValueError("RURI_VERSION must be X.Y.Z or X.Y.Z-prerelease (without a v prefix).")
    build_number = os.environ.get("RURI_BUILD_NUMBER") or info["CFBundleVersion"]
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise ValueError("RURI_BUILD_NUMBER must be a positive integer.")
    client_id = os.environ.get("RURI_MICROSOFT_CLIENT_ID", "").strip() or info.get("RuriMicrosoftClientID", "").strip()
    if client_id:
        # Canonical UUIDs only; a client ID is public, not a client secret.
        if str(uuid.UUID(client_id)) != client_id.lower():
            raise ValueError("RURI_MICROSOFT_CLIENT_ID must be a UUID.")
        info["RuriMicrosoftClientID"] = client_id
    else:
        info.pop("RuriMicrosoftClientID", None)
    info["CFBundleShortVersionString"] = match[1]
    info["CFBundleVersion"] = build_number
    info["RuriVersion"] = version
    with path.open("wb") as destination:
        plistlib.dump(info, destination, sort_keys=False)



def configure_services(resources: Path, environment=None, root: Path = ROOT) -> None:
    environment = os.environ if environment is None else environment
    # Read raw text, never source a shell file: CurseForge keys can contain '$'.
    # An explicitly empty environment value disables local-file fallback.
    if KEY_VARIABLE in environment:
        key = environment[KEY_VARIABLE]
    else:
        local = root / ".private" / "curseforge-api-key"
        key = local.read_text(encoding="utf-8") if local.exists() else ""
    key = key.strip()
    if any(not 0x21 <= ord(character) <= 0x7E for character in key):
        raise ValueError("CurseForge API key must be a single printable ASCII token.")
    destination = resources / "RuriServices.plist"
    if not key:
        destination.unlink(missing_ok=True)
        return
    resources.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps({"CurseForgeAPIKey": key}))



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["metadata", "bundle"])
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "metadata":
            configure_metadata(args.path)
        else:
            configure_metadata(args.path / "Contents/Info.plist")
            configure_services(args.path / "Contents/Resources")
    except (ValueError, OSError) as error:
        # Service credentials must never be included in command output.
        if args.action == "metadata":
            sys.exit(f"Invalid application metadata: {error}")
        sys.exit("Unable to configure application metadata or service credentials.")
