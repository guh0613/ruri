#!/usr/bin/env python3
"""Exercise the distributed CLI using only disposable data and installation paths."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile


def command(arguments, **kwargs):
    result = subprocess.run(list(map(str, arguments)), capture_output=True, timeout=45, **kwargs)
    if result.returncode:
        raise RuntimeError(f"CLI package check failed ({result.returncode}): {result.stderr.decode(errors='replace')[:1000]}")
    return result.stdout


def designated_requirement(path):
    result = subprocess.run(["codesign", "-d", "-r-", str(path)], capture_output=True, check=True)
    for line in (result.stdout + result.stderr).decode().splitlines():
        if line.startswith("designated => "):
            return line
    raise RuntimeError("Missing designated requirement")


def validate(app):
    app = app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/Helpers/ruri-cli"
    details = subprocess.run(["codesign", "-d", "--verbose=2", str(app)], capture_output=True, check=True)
    if b"TeamIdentifier=not set" not in details.stderr:
        if designated_requirement(app) != designated_requirement(executable):
            raise RuntimeError("GUI and CLI must share a designated requirement for existing Keychain entries")
    with tempfile.TemporaryDirectory(prefix="ruri cli package ") as temporary:
        root = Path(temporary)
        data = root / "data directory"
        environment = dict(os.environ, RURI_DATA_DIR=str(root / "wrong data directory"))
        Path(environment["RURI_DATA_DIR"]).mkdir()
        (Path(environment["RURI_DATA_DIR"]) / "state.json").write_text("invalid")

        def invoke(binary, *arguments, input=None):
            result = json.loads(command([binary, *arguments, "--data-dir", data, "--json", "--quiet"], env=environment, input=input))
            assert result["schemaVersion"] == 1 and result["ok"] and result["error"] is None, result
            return result["data"]

        assert command([executable, "--version"], env=environment).decode().strip() == info.get("RuriVersion", info["CFBundleShortVersionString"])
        for arguments, usage in [
            (["--help"], "USAGE: ruri <subcommand>"),
            (["--help", "app"], "USAGE: ruri app <subcommand>"),
            (["app", "--help"], "USAGE: ruri app <subcommand>"),
            (["help", "app"], "USAGE: ruri app <subcommand>"),
            (["app"], "USAGE: ruri app <subcommand>"),
        ]:
            help_text = command([executable, *arguments], env=environment).decode()
            assert usage in help_text and "USAGE: help " not in help_text, help_text
        assert invoke(executable, "schema", "config", "apply")["commands"][0]["path"] == ["config", "apply"]
        assert not data.exists(), "Discovery must not create a state directory"
        invoke(executable, "config", "apply", "--scope", "app", "--file", "-", input=b'{"set":{"concurrentDownloads":7}}')
        assert invoke(executable, "config", "get", "--scope", "app")["effective"]["concurrentDownloads"] == 7
        created = invoke(executable, "instance", "create", "--name", "Package fixture", "--game", "1.21.1", "--directory", "default", "--no-install")
        assert invoke(executable, "instance", "show", created["instance"]["id"])["name"] == "Package fixture"

        copied = root / "App with spaces" / "Ruri.app"
        copied.parent.mkdir()
        # ditto preserves bundle symlinks, executable modes and signatures.
        command(["ditto", app, copied])
        bundled = copied / "Contents/Helpers/ruri-cli"
        bin_dir = root / "user bin"
        assert invoke(bundled, "cli", "install", "--bin-dir", bin_dir)["status"]["installed"]
        link = bin_dir / "ruri"
        assert Path(invoke(link, "app", "info")["application"]).resolve() == copied.resolve()
        command([link, "--localization-check"])
        assert "USAGE: ruri app <subcommand>" in command([link, "--help", "app"], env=environment).decode()
        moved = root / "Moved Ruri.app"
        shutil.move(copied, moved)
        relocated = moved / "Contents/Helpers/ruri-cli"
        assert not invoke(relocated, "cli", "status", "--bin-dir", bin_dir)["installed"]
        assert invoke(relocated, "cli", "install", "--bin-dir", bin_dir)["status"]["installed"]
        assert Path(invoke(link, "app", "info")["application"]).resolve() == moved.resolve()
        # Check helpers with fresh data so doctor needs no Java installation,
        # network access, credentials, or game download.
        clean_data = root / "doctor data"
        result = json.loads(command([link, "doctor", "--data-dir", clean_data, "--json"], env=environment))
        assert result["ok"] and result["data"]["healthy"], result
        assert invoke(link, "cli", "uninstall", "--bin-dir", bin_dir, "--yes")["changed"]
        assert not link.is_symlink()
    print("CLI: version, discovery, stdin, configuration, helpers, relocation and link repair verified")


if __name__ == "__main__":
    validate(Path(sys.argv[1]))
