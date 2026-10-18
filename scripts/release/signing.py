#!/usr/bin/env python3
"""Use the pinned Apple Development identity for local and CI packages."""

import argparse
import base64
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CERTIFICATE = ROOT / "Resources/RuriSigning.cer"
INTERMEDIATE_CERTIFICATE = ROOT / "Resources/AppleWWDRCAG3.cer"
SECRET_VARIABLES = ("RURI_SIGN_P12_BASE64", "RURI_SIGN_P12_PASSWORD")
CONTRIBUTOR_IDENTITY = "RURI_CONTRIBUTOR_SIGN_IDENTITY"


class SigningError(Exception):
    pass


def command(arguments, *, label, env=None, include_stderr=False):
    environment = dict(os.environ if env is None else env)
    for name in SECRET_VARIABLES:
        environment.pop(name, None)
    input_data = None
    if arguments[0] == "security":
        # security supports one command on stdin in interactive mode and
        # returns that command's status at EOF. Keep passwords out of argv.
        values = arguments[1:]
        if len(values) > 32 or any(any(c in value for c in "\0\r\n") for value in values):
            raise SigningError(f"{label} has invalid input.")
        def quote(value):
            return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
        input_data = (" ".join(map(quote, values)) + "\n").encode()
        if len(input_data) >= 4096:
            raise SigningError(f"{label} input is too long.")
        arguments = ["/usr/bin/security", "-i"]
    result = subprocess.run(arguments, input=input_data, capture_output=True, env=environment)
    if result.returncode:
        # security/openssl arguments can contain passwords. Never include the
        # command line, environment or captured output in an exception/log.
        raise SigningError(f"{label} failed (exit {result.returncode}).")
    return result.stdout + (result.stderr if include_stderr else b"")


def fingerprint():
    if not CERTIFICATE.is_file():
        raise SigningError("The public Ruri signing certificate is missing.")
    return hashlib.sha1(CERTIFICATE.read_bytes()).hexdigest().upper()


def certificate_team(certificate=None):
    subject = command(["/usr/bin/openssl", "x509", "-inform", "DER", "-in", str(certificate or CERTIFICATE),
                       "-noout", "-subject", "-nameopt", "RFC2253"], label="Certificate team lookup").decode()
    match = re.search(r"(?:^|,)OU=([A-Z0-9]{10})(?:,|$)", subject.strip())
    if not match:
        if certificate is None:
            raise SigningError("The pinned signing certificate has no Apple Team ID.")
        raise SigningError("The contributor signing certificate has no Apple Team ID.")
    return match[1]


def available_identities(keychain=None):
    arguments = ["security", "find-identity", "-v", "-p", "codesigning"]
    if keychain is not None:
        arguments.append(str(keychain))
    output = command(arguments, label="Signing identity lookup").decode()
    return {value.upper() for value in re.findall(r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"', output, re.MULTILINE)}


def contributor_identity(environment):
    if CONTRIBUTOR_IDENTITY not in environment:
        return None
    if environment.get("RURI_REQUIRE_SIGNING") == "1" or "CI" in environment or "GITHUB_ACTIONS" in environment:
        raise SigningError("Contributor signing is only available for local builds without required release signing or CI.")
    identity = environment[CONTRIBUTOR_IDENTITY]
    if not re.fullmatch(r"[A-Fa-f0-9]{40}", identity):
        raise SigningError("RURI_CONTRIBUTOR_SIGN_IDENTITY must be a SHA-1 signing identity fingerprint.")
    override = environment.get("RURI_SIGN_IDENTITY")
    if override and override.upper() != identity.upper():
        raise SigningError("RURI_SIGN_IDENTITY conflicts with the contributor signing identity.")
    return identity.upper()


def apple_requirement(identity, team):
    return (f'anchor apple generic and certificate leaf = H"{identity}" '
            'and certificate 1[field.1.2.840.113635.100.6.2.1] exists '
            'and certificate leaf[field.1.2.840.113635.100.6.1.12] exists '
            f'and certificate leaf[subject.OU] = "{team}"')


def contributor_team(target, identity, work):
    prefix = work / "certificate-"
    command(["codesign", "-d", "--extract-certificates=" + str(prefix), str(target)],
            label="Contributor signing certificate extraction")
    certificate = Path(str(prefix) + "0")
    if hashlib.sha1(certificate.read_bytes()).hexdigest().upper() != identity:
        raise SigningError("The package leaf certificate does not match the contributor signing identity.")
    return certificate_team(certificate)


def validate_contributor(identity):
    if identity not in available_identities():
        raise SigningError("The contributor identity is not a valid code signing identity in the keychain.")
    work_root = ROOT / ".work"
    work_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="contributor-signing-", dir=work_root) as temporary:
        work = Path(temporary)
        target = work / "signing-check"
        shutil.copyfile("/usr/bin/true", target)
        command(["codesign", "--force", "--sign", identity, str(target)], label="Contributor identity signing check")
        team = contributor_team(target, identity, work)
        command(["codesign", "--verify", "--all-architectures", "--strict", "-R",
                 "=" + apple_requirement(identity, team), str(target)],
                label="Contributor Apple Development certificate verification")


def save_private(path, data):
    with path.open("xb") as output:
        os.chmod(path, 0o600)
        output.write(data)


def signing_material(environment):
    encoded = environment.get(SECRET_VARIABLES[0], "")
    password = environment.get(SECRET_VARIABLES[1], "")
    if encoded or password:
        if not encoded or not password:
            raise SigningError("Both signing certificate and password secrets are required.")
        try:
            data = base64.b64decode(encoded, validate=True)
        except ValueError:
            raise SigningError("The signing certificate secret is not valid Base64.") from None
        if not data or len(data) > 65536:
            raise SigningError("The signing certificate secret has an invalid size.")
        return data, password
    # Local packages use the existing Xcode identity in the user's keychain.
    # Never fall back to the old self-signed identity under .private/signing.
    return None


@contextmanager
def signing_environment(environment):
    child = dict(environment)
    for name in SECRET_VARIABLES:
        child.pop(name, None)
    child.pop("RURI_SIGN_KEYCHAIN", None)
    child["RURI_SIGNING_ACTIVE"] = "1"
    contributor = contributor_identity(environment)
    if contributor is not None:
        validate_contributor(contributor)
        child["RURI_SIGN_IDENTITY"] = contributor
        print("Signing with an Apple Development identity: contributor build, not a release signature.", flush=True)
        yield child
        return
    required = environment.get("RURI_REQUIRE_SIGNING") == "1"
    override = environment.get("RURI_SIGN_IDENTITY")
    identity = fingerprint()
    if override and override != "-" and override.upper() != identity:
        raise SigningError("The requested signing identity does not match the pinned Apple certificate.")
    if override == "-":
        if required:
            raise SigningError("A required signed package must not use ad hoc signing.")
        child["RURI_SIGN_IDENTITY"] = "-"
        yield child
        return
    material = signing_material(environment)
    if material is None:
        if not (environment.get("CI") or environment.get("GITHUB_ACTIONS")) and identity in available_identities():
            child["RURI_SIGN_IDENTITY"] = identity
            print(f"Signing with the local Apple Development identity: {identity}", flush=True)
            yield child
            return
        if required or override:
            raise SigningError("The pinned Apple Development identity is unavailable. Supply signing secrets in CI or install it with Xcode locally.")
        child["RURI_SIGN_IDENTITY"] = "-"
        print("No pinned Apple Development identity is available; this contributor build uses ad hoc signing.", flush=True)
        yield child
        return
    keychain_password = secrets.token_urlsafe(48)
    with tempfile.TemporaryDirectory(prefix="ruri-signing-", dir=environment.get("RUNNER_TEMP")) as temporary:
        work = Path(temporary)
        keychain = work / "signing.keychain-db"
        p12 = work / "identity.p12"
        save_private(p12, material[0])
        try:
            command(["security", "create-keychain", "-p", keychain_password, str(keychain)], label="Temporary keychain creation")
            command(["security", "set-keychain-settings", "-lut", "21600", str(keychain)], label="Keychain settings")
            command(["security", "unlock-keychain", "-p", keychain_password, str(keychain)], label="Keychain unlock")
            # codesign --keychain selects the identity, but its certificate
            # chain is resolved through the user's search list. Preserve all
            # existing entries; delete-keychain removes our entry on cleanup.
            search_list = shlex.split(command(["security", "list-keychains", "-d", "user"],
                                             label="Keychain search list lookup").decode())
            if str(keychain) not in search_list:
                command(["security", "list-keychains", "-d", "user", "-s", *search_list, str(keychain)],
                        label="Temporary keychain search configuration")
            # Hosted runners need not have the WWDR intermediate preinstalled.
            # Import its public certificate without changing any trust settings.
            command(["security", "import", str(INTERMEDIATE_CERTIFICATE), "-k", str(keychain)],
                    label="Apple intermediate certificate import")
            command(["security", "import", str(p12), "-k", str(keychain), "-f", "pkcs12", "-P", material[1],
                     "-x", "-T", "/usr/bin/codesign"], label="Signing identity import")
            command(["security", "set-key-partition-list", "-S", "apple-tool:", "-s", "-k", keychain_password, str(keychain)],
                    label="Signing key access configuration")
            if identity not in available_identities(keychain):
                raise SigningError("The private signing identity does not match the public Ruri certificate.")
            p12.unlink()
            child["RURI_SIGN_IDENTITY"] = identity
            child["RURI_SIGN_KEYCHAIN"] = str(keychain)
            print(f"Signing with the pinned Apple Development identity: {identity}", flush=True)
            yield child
        finally:
            if keychain.exists():
                command(["security", "delete-keychain", str(keychain)], label="Temporary signing keychain cleanup")


def verify(app, environment):
    contributor = contributor_identity(environment)
    identity = environment.get("RURI_SIGN_IDENTITY", contributor or "-")
    if contributor is not None:
        if identity.upper() != contributor:
            raise SigningError("The package must use the requested contributor signing identity.")
        work_root = ROOT / ".work"
        work_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="contributor-verify-", dir=work_root) as temporary:
            team = contributor_team(app, contributor, Path(temporary))
        identity = contributor
    elif identity == "-" and environment.get("RURI_REQUIRE_SIGNING") != "1":
        return
    elif identity.upper() != fingerprint():
        raise SigningError("A signed package must use the pinned Apple Development certificate.")
    else:
        team = certificate_team()
    # A stable self-signed DR is insufficient: modern keychains additionally
    # partition those callers by CDHash. This Apple-issued Mac development
    # certificate is classified by its stable Team ID instead.
    requirement = apple_requirement(identity, team)
    sparkle = app / "Contents/Frameworks/Sparkle.framework"
    targets = [app, app / "Contents/Helpers/ruri-cli", app / "Contents/Helpers/ruri-monitor", app / "Contents/Helpers/RuriGame.app",
               app / "Contents/Helpers/RuriGame.app/Contents/Frameworks/libRuriGameSupport.dylib",
               sparkle, sparkle / "Versions/B/Autoupdate", sparkle / "Versions/B/Updater.app"]
    for target in targets:
        command(["codesign", "--verify", "--all-architectures", "--strict", "-R",
                 "=" + requirement, str(target)], label=f"Signature verification for {target.name}")
        details = command(["codesign", "-d", "--verbose=2", str(target)],
                          label=f"Signing team verification for {target.name}", include_stderr=True).decode()
        if f"TeamIdentifier={team}" not in details.splitlines():
            if contributor is not None:
                raise SigningError(f"The signing Team ID for {target.name} does not match the contributor certificate.")
            raise SigningError(f"The signing Team ID for {target.name} does not match the pinned certificate.")
    if contributor is not None:
        print("Verified the Apple certificate and Team ID on the app and every helper: contributor build, not a release signature.")
    else:
        print(f"Verified the Apple certificate and Team ID {team} on the app and every helper.")


def cleanup_ci(environment):
    runner_temp = environment.get("RUNNER_TEMP")
    if not runner_temp:
        raise SigningError("CI cleanup requires RUNNER_TEMP.")
    for work in Path(runner_temp).glob("ruri-signing-*"):
        if not work.is_dir() or work.is_symlink():
            continue
        keychain = work / "signing.keychain-db"
        if keychain.exists():
            command(["security", "delete-keychain", str(keychain)], label="Leftover signing keychain cleanup")
        shutil.rmtree(work)


def run_build(arguments, environment):
    process = subprocess.Popen(arguments, env=environment, start_new_session=True)
    try:
        return process.wait()
    except KeyboardInterrupt:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise


def main():
    parser = argparse.ArgumentParser(description="Sign packages with the pinned Apple Development identity, or explicitly opt in to local contributor signing.")
    parser.add_argument("action", choices=["run", "verify", "cleanup-ci"])
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == "verify":
        verify(Path(args.arguments[0]), os.environ)
    elif args.action == "cleanup-ci":
        cleanup_ci(os.environ)
    else:
        arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
        if not arguments:
            raise SigningError("A build command is required.")
        # Normal CI cancellation must still unwind the temporary keychain.
        def cancel(_signal, _frame):
            raise KeyboardInterrupt
        signal.signal(signal.SIGTERM, cancel)
        with signing_environment(os.environ) as environment:
            return run_build(arguments, environment)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (SigningError, OSError) as error:
        sys.exit(f"Signing: {error}")
    except KeyboardInterrupt:
        sys.exit(130)
