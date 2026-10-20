#!/usr/bin/env python3
"""Exercise the distributed CLI using only disposable data and installation paths."""
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


def command(arguments, **kwargs):
    result = subprocess.run(list(map(str, arguments)), capture_output=True, timeout=45, **kwargs)
    if result.returncode:
        raise RuntimeError(f"CLI package check failed ({result.returncode}): {result.stderr.decode(errors='replace')[:1000]}")
    return result.stdout


def pasted(line, executable, environment):
    """Runs a command the CLI printed, as a person pasting it into a shell would."""
    shell = 'ruri() { "$RURI_UNDER_TEST" "$@"; }; ' + line
    return command(["/bin/sh", "-c", shell], env=dict(environment, RURI_UNDER_TEST=str(executable))).decode()


def printed(prefix, text):
    for line in text.splitlines():
        if line.startswith(prefix):
            return line[len(prefix):]
    raise RuntimeError(f"Missing {prefix!r} in {text}")


ZSH_HARNESS = r'''
zmodload zsh/zpty
zpty -b z zsh -f -i
zpty -w z "PS1='> '; fpath=(${(q)1} \$fpath); autoload -U compinit; compinit -u -D; zstyle ':completion:*' list-grouped no; LISTMAX=1000; setopt nobeep"
zpty -w z "print -r -- READY"
zpty -r z out '*READY*'
zpty -w -n z "$2"$'\t'
sleep 1.5
zpty -w -n z $'\C-u'
zpty -w z "print -r -- DONE"
zpty -r z out '*DONE*'
print -r -- "${out}"
zpty -d z
'''

BASH_HARNESS = r'''
source "$1"; line="$2"
COMP_LINE="$line"; COMP_POINT=${#line}
read -ra COMP_WORDS <<< "$line"
if [[ "$line" == *" " ]]; then COMP_WORDS+=(""); fi
COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
_ruri ruri "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
printf '%s\n' "${COMPREPLY[@]}"
'''


def completion_output(shell, script, line, environment, fish=None):
    """What a real shell offers after line, with the generated script loaded and nothing else."""
    with tempfile.TemporaryDirectory(prefix="ruri completion ") as temporary:
        directory = Path(temporary)
        if shell == "zsh":
            (directory / "_ruri").write_bytes(script)
            return command(["/bin/zsh", "-f", "-c", ZSH_HARNESS, "zsh", directory, line], env=environment).decode(errors="replace")
        if shell == "bash":
            (directory / "ruri.bash").write_bytes(script)
            return command(["/bin/bash", "-c", BASH_HARNESS, "bash", directory / "ruri.bash", line], env=environment).decode()
        (directory / "ruri.fish").write_bytes(script)
        source = "source " + shlex.quote(str(directory / "ruri.fish")) + "; complete -C " + shlex.quote(line)
        return command([fish, "--no-config", "-c", source], env=environment).decode()


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
        environment = dict(os.environ, RURI_DATA_DIR=str(root / "wrong data directory"), RURI_LANGUAGE="zh-Hans")
        Path(environment["RURI_DATA_DIR"]).mkdir()
        (Path(environment["RURI_DATA_DIR"]) / "state.json").write_text("invalid")

        def invoke(binary, *arguments, input=None):
            result = json.loads(command([binary, *arguments, "--data-dir", data, "--json", "--quiet"], env=environment, input=input))
            assert result["schemaVersion"] == 1 and result["ok"] and result["error"] is None, result
            return result["data"]

        assert command([executable, "--version"], env=environment).decode().strip() == info.get("RuriVersion", info["CFBundleShortVersionString"])
        for arguments, usage in [
            (["--help"], "Usage: ruri <command>"),
            (["--help", "app"], "Usage: ruri app <subcommand>"),
            (["app", "--help"], "Usage: ruri app <subcommand>"),
            (["help", "app"], "Usage: ruri app <subcommand>"),
            (["app"], "Usage: ruri app <subcommand>"),
        ]:
            help_text = command([executable, *arguments], env=environment).decode()
            assert usage in help_text and "Usage: help " not in help_text, help_text
        grouped = command([executable, "help", "instance", "--full"], env=environment).decode()
        assert "ruri instance component set <instance>" in grouped and "--component" in grouped
        assert not re.search(r"[\u3400-\u9fff]", grouped), "CLI help must default to English"
        chinese = command([executable, "help", "instance", "--language", "zh-Hans"], env=environment).decode()
        assert re.search(r"[\u3400-\u9fff]", chinese), "Explicit zh-Hans help must contain Chinese"
        catalog_path = Path(__file__).resolve().parents[1] / "Sources/RuriLocalization/Resources/CLIInterface.xcstrings"
        catalog = json.loads(catalog_path.read_text())
        expected = catalog["strings"]["CLIInterface.instanceListHelp"]["localizations"]["zh-Hans"]["stringUnit"]["value"].rstrip("。")
        assert expected in chinese, chinese
        complete = command([executable, "help", "--all"], env=environment)
        assert len(complete) < 35_000
        index = invoke(executable, "schema")
        assert len(json.dumps(index).encode()) < 40_000
        assert "patchSchemas" not in index
        for item in index["commands"]:
            assert item["usage"] in complete.decode()
            assert "inputSchema" not in item and "resultSchema" not in item
        leaf = invoke(executable, "schema", "instance", "list")
        assert len(json.dumps(leaf).encode()) < 5_000
        assert set(leaf) == {"commands"}
        patch = invoke(executable, "schema", "config", "apply", "--input", "--scope", "instance")
        assert set(patch["patchSchemas"]) == {"instance"}
        assert "resultSchema" not in patch["commands"][0]
        assert not data.exists(), "Discovery must not create a state directory"
        invoke(executable, "config", "apply", "--scope", "app", "--file", "-", input=b'{"set":{"concurrentDownloads":7}}')
        assert invoke(executable, "config", "get", "--scope", "app")["effective"]["concurrentDownloads"] == 7
        created = invoke(executable, "instance", "create", "--name", "Package fixture", "--game", "1.21.1", "--directory", "default", "--no-install")
        assert invoke(executable, "instance", "show", created["instance"]["id"])["name"] == "Package fixture"

        # Default text must be independently usable; JSON/NDJSON retain their contract.
        readable = command([executable, "instance", "list", "--data-dir", data], env=environment).decode()
        short = created["instance"]["id"].replace("-", "").lower()[:8]
        assert short in readable and "Package fixture" in readable, readable
        assert not readable.lstrip().startswith("{")
        detailed = command([executable, "instance", "list", "--details", "--data-dir", data], env=environment).decode()
        assert created["instance"]["id"] in detailed
        assert invoke(executable, "instance", "show", short)["name"] == "Package fixture"
        original_state = (data / "state.json").read_bytes()
        preview = command([executable, "config", "set", "concurrentDownloads", "9", "--scope", "app",
                           "--dry-run", "--data-dir", data], env=environment).decode()
        assert "7 → 9" in preview and "Revision" not in preview
        assert "before" not in preview and "after" not in preview
        assert "Preview: configuration changes" in preview
        assert not re.search(r"[\u3400-\u9fff]", preview)
        assert "Revision" in command([executable, "config", "set", "concurrentDownloads", "9", "--scope", "app",
                                      "--dry-run", "--details", "--data-dir", data], env=environment).decode()
        assert (data / "state.json").read_bytes() == original_state
        current = command([executable, "config", "get", "concurrentDownloads", "--scope", "app",
                           "--data-dir", data], env=environment).decode()
        assert "concurrentDownloads" in current and "7" in current and "Source" in current
        events = command([executable, "app", "info", "--output", "ndjson", "--data-dir", data], env=environment).splitlines()
        assert len(events) == 1 and json.loads(events[0])["type"] == "result"
        bad = subprocess.run([executable, "unknown-command"], env=environment, capture_output=True, timeout=45)
        assert bad.returncode == 2 and not bad.stdout and b"INVALID_ARGUMENT" in bad.stderr

        # Select, configure and preview using only the short IDs and commands the text printed.
        def text(*arguments):
            return command([executable, *arguments, "--data-dir", data], env=environment).decode()
        invoke(executable, "instance", "create", "--name", "生存 世界", "--game", "1.21.1", "--directory", "default", "--no-install")
        assert text("instance", "select", short).startswith("Completed: Select an instance.")
        preview = text("config", "set", "memory.maximumMB", "6144", "--scope", f"instance:{short}", "--dry-run")
        applied = pasted(printed("Apply: ", preview), executable, environment)
        assert applied.startswith("Updated the configuration of instance Package fixture"), applied
        blocked = subprocess.run([executable, "launch", "preflight", short, "--data-dir", data], env=environment, capture_output=True, timeout=45)
        failure = blocked.stderr.decode()
        assert blocked.returncode == 1 and not blocked.stdout and failure.startswith("Error [INSTALLATION_REQUIRED]"), failure
        assert f"Package fixture ({short})" in failure, failure
        assert shlex.split(printed("Next: ", failure)) == ["ruri", "instance", "install", created["instance"]["id"], "--data-dir", str(data)], failure
        assert "名称" in text("instance", "list", "--language", "zh-Hans")
        assert "\x1b[" in text("instance", "list", "--color", "always") and "\x1b" not in readable
        assert text("recovery", "list") == "Nothing needs recovery.\n"

        # Completion scripts load in each shell and offer local targets, read
        # from the data directory the line names, or from RURI_DATA_DIR.
        completion_bin = root / "completion bin"
        completion_bin.mkdir()
        (completion_bin / "ruri").symlink_to(executable)
        shells = dict(environment, PATH=f"{completion_bin}:{os.environ['PATH']}")
        located = dict(shells, RURI_DATA_DIR=str(data))
        fish = os.environ.get("RURI_FISH") or shutil.which("fish")
        for shell in ["zsh", "bash", "fish"]:
            script = command([executable, "completions", shell], env=environment)
            assert invoke(executable, "completions", shell)["shell"] == shell and b"---completion" in script, shell
            checker = {"zsh": ["/bin/zsh", "-n"], "bash": ["/bin/bash", "-n"], "fish": [fish, "--no-config", "--no-execute"] if fish else None}[shell]
            if checker is None:
                print("CLI: fish not found; set RURI_FISH to an isolated fish to check its candidates")
                continue
            with tempfile.NamedTemporaryFile(suffix="." + shell) as file:
                file.write(script); file.flush()
                command([*checker, file.name])
            offered = completion_output(shell, script, "ruri instance show ", located, fish)
            for name in ["Package fixture", "生存 世界"]:
                assert name in offered or name.replace(" ", "\\ ") in offered, f"{shell}: {offered}"
            assert "memory.maximumMB" in completion_output(shell, script, "ruri config set memory.", located, fish), shell
            # Unreadable state offers nothing rather than failing.
            assert "Package fixture" not in completion_output(shell, script, "ruri instance show ", shells, fish), shell
            if shell == "fish":
                named = completion_output(shell, script, f"ruri instance show --data-dir {shlex.quote(str(data))} ", shells, fish)
                assert "Package fixture" in named, named

        if info.get("RuriPackageManager"):
            # The package manager links ruri itself, so Ruri refuses to.
            refused = subprocess.run([executable, "cli", "install", "--bin-dir", root / "user bin", "--json", "--quiet"],
                                     env=environment, capture_output=True, timeout=45)
            assert refused.returncode and json.loads(refused.stdout)["error"]["code"] == "MANAGED_BY_PACKAGE_MANAGER", refused
            link = executable
        else:
            copied = root / "App with spaces" / "Ruri.app"
            copied.parent.mkdir()
            # ditto preserves bundle symlinks, executable modes and signatures.
            command(["ditto", app, copied])
            bundled = copied / "Contents/Helpers/ruri-cli"
            bin_dir = root / "user bin"
            assert invoke(bundled, "cli", "install", "--bin-dir", bin_dir)["status"]["installed"]
            link = bin_dir / "ruri"
            assert Path(invoke(link, "app", "info")["application"]).resolve() == copied.resolve()
            status = command([link, "cli", "status", "--bin-dir", bin_dir], env=environment).decode()
            # The sentence may wrap before the path, never inside it.
            assert " ".join(status.splitlines()[:2]).startswith(f"ruri is installed at {link}."), status
            command([link, "--localization-check"])
            assert "Usage: ruri app <subcommand>" in command([link, "--help", "app"], env=environment).decode()
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
        assert command([link, "doctor", "--data-dir", clean_data], env=environment).decode().startswith("Every check passed.\n  ✓ ")
        if not info.get("RuriPackageManager"):
            assert invoke(link, "cli", "uninstall", "--bin-dir", bin_dir, "--yes")["changed"]
            assert not link.is_symlink()
    print("CLI: discovery budgets, text/JSON/NDJSON, stdin, configuration, pasted commands, shell completion, helpers, relocation and link repair verified")


if __name__ == "__main__":
    validate(Path(sys.argv[1]))
