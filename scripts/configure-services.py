#!/usr/bin/env python3
"""Bundle application credentials before signing; the resulting app key is extractable."""

import os
from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parent.parent
KEY_VARIABLE = "RURI_CURSEFORGE_API_KEY"


def configure(resources: Path, environment=None, root: Path = ROOT) -> None:
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
    try:
        configure(Path(sys.argv[1]))
    except (ValueError, IndexError, OSError):
        # Do not include exception details: they may contain credential bytes.
        sys.exit("Unable to configure service credentials. Check RURI_CURSEFORGE_API_KEY or .private/curseforge-api-key.")
