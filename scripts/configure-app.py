#!/usr/bin/env python3
"""Write public distribution metadata before code signing; never embed secrets."""

import os
from pathlib import Path
import plistlib
import re
import sys
import uuid


def configure(path: Path) -> None:
    with path.open("rb") as source:
        info = plistlib.load(source)
    resources = Path(__file__).resolve().parent.parent / "Sources/RuriLocalization/Resources"
    info["CFBundleDevelopmentRegion"] = "zh-Hans"
    info["CFBundleLocalizations"] = sorted(p.stem for p in resources.glob("*.lproj"))
    version = os.environ.get("RURI_VERSION") or info["CFBundleShortVersionString"]
    number = r"(?:0|[1-9][0-9]*)"
    identifier = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    match = re.fullmatch(rf"({number}\.{number}\.{number})(?:-{identifier}(?:\.{identifier})*)?", version)
    if not match:
        raise ValueError("RURI_VERSION must be X.Y.Z or X.Y.Z-prerelease (without a v prefix).")
    build_number = os.environ.get("RURI_BUILD_NUMBER") or info["CFBundleVersion"]
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise ValueError("RURI_BUILD_NUMBER must be a positive integer.")
    client_id = os.environ.get("RURI_MICROSOFT_CLIENT_ID", "").strip()
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


if __name__ == "__main__":
    try:
        configure(Path(sys.argv[1]))
    except (ValueError, IndexError) as error:
        sys.exit(f"Invalid application metadata: {error}")
