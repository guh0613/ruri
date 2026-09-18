#!/usr/bin/env python3
"""Keep packaged builds on one signing identity without exposing its private key."""

import argparse
import base64
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CERTIFICATE = ROOT / "Resources/RuriSigning.cer"
PRIVATE = ROOT / ".private/signing"
SECRET_VARIABLES = ("RURI_SIGN_P12_BASE64", "RURI_SIGN_P12_PASSWORD")


class SigningError(Exception):
    pass


def command(arguments, *, label, env=None):
    result = subprocess.run(arguments, capture_output=True, env=env)
    if result.returncode:
        # security/openssl arguments can contain passwords. Never include the
        # command line, environment or captured output in an exception/log.
        raise SigningError(f"{label} failed (exit {result.returncode}).")
    return result.stdout


def fingerprint():
    if not CERTIFICATE.is_file():
        raise SigningError("The public Ruri signing certificate is missing.")
    return hashlib.sha1(CERTIFICATE.read_bytes()).hexdigest().upper()


def create_identity():
    if CERTIFICATE.exists() or PRIVATE.exists():
        raise SigningError("A signing identity already exists; refusing to rotate it.")
    PRIVATE.mkdir(parents=True, mode=0o700)
    password = secrets.token_urlsafe(48)
    openssl = shutil.which("openssl")
    if not openssl:
        raise SigningError("OpenSSL is required to create a signing identity.")
    with tempfile.TemporaryDirectory(prefix="create-", dir=PRIVATE) as temporary:
        work = Path(temporary)
        key, certificate, p12 = work / "key.pem", work / "certificate.pem", work / "identity.p12"
        configuration = work / "openssl.cnf"
        configuration.write_text("""[req]
distinguished_name = name
x509_extensions = signing
prompt = no
[name]
CN = Ruri Project Code Signing
O = Ruri
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
        environment = os.environ | {"RURI_CERT_PASSWORD": password}
        command([openssl, "req", "-new", "-x509", "-newkey", "rsa:3072", "-sha256", "-days", "3650",
                 "-config", str(configuration), "-keyout", str(key), "-out", str(certificate),
                 "-passout", "env:RURI_CERT_PASSWORD"], label="Certificate creation", env=environment)
        # The macOS PKCS#12 importer also needs to work on older release runners.
        command([openssl, "pkcs12", "-export", "-inkey", str(key), "-in", str(certificate),
                 "-name", "Ruri Project Code Signing", "-out", str(p12),
                 "-passin", "env:RURI_CERT_PASSWORD", "-passout", "env:RURI_CERT_PASSWORD",
                 "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1"],
                label="Signing identity export", env=environment)
        public = command([openssl, "x509", "-in", str(certificate), "-outform", "DER"], label="Public certificate export")
        save_private(PRIVATE / "identity.p12", p12.read_bytes())
        save_private(PRIVATE / "password", password.encode())
        CERTIFICATE.write_bytes(public)
    print(f"Created Ruri signing certificate: {fingerprint()}")


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
    # CI must explicitly supply its identity; a persistent runner's local files
    # must never become a fallback signing credential.
    if environment.get("CI") or environment.get("GITHUB_ACTIONS"):
        return None
    p12, password_file = PRIVATE / "identity.p12", PRIVATE / "password"
    if p12.exists() or password_file.exists():
        if not p12.is_file() or not password_file.is_file():
            raise SigningError("The local signing identity is incomplete.")
        return p12.read_bytes(), password_file.read_text().strip()
    return None


@contextmanager
def signing_environment(environment):
    child = dict(environment)
    for name in SECRET_VARIABLES:
        child.pop(name, None)
    child["RURI_SIGNING_ACTIVE"] = "1"
    required = environment.get("RURI_REQUIRE_SIGNING") == "1"
    override = environment.get("RURI_SIGN_IDENTITY")
    if override and not required:
        child["RURI_SIGN_IDENTITY"] = override
        yield child
        return
    material = signing_material(environment)
    if material is None:
        if required:
            raise SigningError("Release signing is required, but no signing identity was supplied.")
        child["RURI_SIGN_IDENTITY"] = "-"
        yield child
        return
    identity = fingerprint()
    if override and override.upper() != identity:
        raise SigningError("The requested signing identity does not match the Ruri certificate.")
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
            command(["security", "import", str(p12), "-k", str(keychain), "-f", "pkcs12", "-P", material[1],
                     "-x", "-T", "/usr/bin/codesign"], label="Signing identity import")
            command(["security", "set-key-partition-list", "-S", "apple-tool:", "-s", "-k", keychain_password, str(keychain)],
                    label="Signing key access configuration")
            identities = command(["security", "find-identity", "-p", "codesigning", str(keychain)], label="Signing identity verification")
            if identity.encode() not in identities:
                raise SigningError("The private signing identity does not match the public Ruri certificate.")
            p12.unlink()
            child["RURI_SIGN_IDENTITY"] = identity
            child["RURI_SIGN_KEYCHAIN"] = str(keychain)
            print(f"Signing with the fixed Ruri certificate: {identity}", flush=True)
            yield child
        finally:
            if keychain.exists():
                command(["security", "delete-keychain", str(keychain)], label="Temporary signing keychain cleanup")


def verify(app, environment):
    identity = environment.get("RURI_SIGN_IDENTITY", "-")
    if environment.get("RURI_REQUIRE_SIGNING") == "1" and identity.upper() != fingerprint():
        raise SigningError("A release must be signed with the fixed Ruri certificate.")
    if identity.upper() != fingerprint():
        return
    targets = [app, app / "Contents/Helpers/ruri-monitor", app / "Contents/Helpers/RuriGame.app",
               app / "Contents/Helpers/RuriGame.app/Contents/Frameworks/libRuriGameSupport.dylib"]
    for target in targets:
        command(["codesign", "--verify", "--all-architectures", "--strict", "-R",
                 f'=certificate leaf = H"{identity}"', str(target)], label=f"Signature verification for {target.name}")
    print("Verified the Ruri certificate on the app and every helper.")


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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["create", "run", "verify", "cleanup-ci"])
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.action == "create":
        create_identity()
    elif args.action == "verify":
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
