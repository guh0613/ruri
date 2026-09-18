import base64
import importlib.util
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("signing", ROOT / "scripts/signing.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.private = self.root / "private"
        self.private.mkdir()
        self.certificate = self.root / "public.cer"
        self.certificate.write_bytes(b"public certificate")
        self.addCleanup(patch.stopall)
        patch.object(signing, "PRIVATE", self.private).start()
        patch.object(signing, "CERTIFICATE", self.certificate).start()

    def local_identity(self):
        signing.save_private(self.private / "identity.p12", b"private identity")
        signing.save_private(self.private / "password", b"private password")

    def test_ci_never_uses_a_runners_local_identity(self):
        self.local_identity()
        self.assertIsNone(signing.signing_material({"CI": "true"}))
        with self.assertRaises(signing.SigningError):
            with signing.signing_environment({"CI": "true", "RURI_REQUIRE_SIGNING": "1"}):
                self.fail("Missing release credentials must not use local files")

    def test_contributor_build_can_use_adhoc_without_private_credentials(self):
        with signing.signing_environment({"CI": "true"}) as environment:
            self.assertEqual(environment["RURI_SIGN_IDENTITY"], "-")

    def test_required_release_rejects_an_adhoc_override(self):
        with self.assertRaises(signing.SigningError):
            with signing.signing_environment({"RURI_REQUIRE_SIGNING": "1", "RURI_SIGN_IDENTITY": "-"}):
                self.fail("A release must not silently become ad hoc")

    def test_partial_or_invalid_secrets_do_not_fall_back(self):
        self.local_identity()
        for environment in [
            {"RURI_SIGN_P12_PASSWORD": "password"},
            {"RURI_SIGN_P12_BASE64": "YWJj"},
            {"RURI_SIGN_P12_BASE64": "invalid!", "RURI_SIGN_P12_PASSWORD": "password"},
        ]:
            with self.subTest(environment=tuple(environment)):
                with self.assertRaises(signing.SigningError):
                    signing.signing_material(environment)

    def test_certificate_creation_never_replaces_an_existing_identity(self):
        before = self.certificate.read_bytes()
        with self.assertRaises(signing.SigningError):
            signing.create_identity()
        self.assertEqual(self.certificate.read_bytes(), before)

    def mock_security(self, arguments, **kwargs):
        if arguments[:2] == ["security", "create-keychain"]:
            Path(arguments[-1]).touch()
        if arguments[:2] == ["security", "find-identity"]:
            return signing.fingerprint().encode()
        return b""

    def test_build_failure_cleans_keychain_and_never_passes_passwords_to_build(self):
        environment = {"CI": "true", "RURI_REQUIRE_SIGNING": "1", "RUNNER_TEMP": str(self.root),
                       "RURI_SIGN_P12_BASE64": base64.b64encode(b"private identity").decode(),
                       "RURI_SIGN_P12_PASSWORD": "private password"}
        with patch.object(signing, "command", side_effect=self.mock_security) as command:
            with self.assertRaisesRegex(RuntimeError, "build failed"):
                with signing.signing_environment(environment) as child:
                    self.assertEqual(child["RURI_SIGN_IDENTITY"], signing.fingerprint())
                    self.assertTrue(Path(child["RURI_SIGN_KEYCHAIN"]).exists())
                    self.assertFalse(any(name in child for name in signing.SECRET_VARIABLES))
                    raise RuntimeError("build failed")
            self.assertEqual(command.call_args.args[0][:2], ["security", "delete-keychain"])
        self.assertFalse(list(self.root.glob("ruri-signing-*")))

    def test_wrong_private_identity_is_rejected_and_cleaned(self):
        self.local_identity()
        def security(arguments, **kwargs):
            return b"wrong identity" if arguments[1] == "find-identity" else self.mock_security(arguments, **kwargs)
        with patch.object(signing, "command", side_effect=security) as command:
            with self.assertRaisesRegex(signing.SigningError, "does not match"):
                with signing.signing_environment({"RUNNER_TEMP": str(self.root)}):
                    self.fail("An unrelated certificate must not sign Ruri")
            self.assertEqual(command.call_args.args[0][:2], ["security", "delete-keychain"])

    def test_failed_commands_do_not_disclose_secret_arguments_or_output(self):
        result = subprocess.CompletedProcess([], 1, b"private data", b"private password")
        with patch.object(subprocess, "run", return_value=result):
            with self.assertRaises(signing.SigningError) as error:
                signing.command(["security", "import", "-P", "private password"], label="Import")
        self.assertNotIn("private", str(error.exception))

    def test_final_cleanup_is_confined_to_its_own_temporary_directories(self):
        owned = self.root / "ruri-signing-interrupted"
        owned.mkdir()
        (owned / "signing.keychain-db").touch()
        unrelated = self.root / "unrelated"
        unrelated.mkdir()
        (self.root / "ruri-signing-link").symlink_to(unrelated, target_is_directory=True)
        with patch.object(signing, "command") as command:
            signing.cleanup_ci({"RUNNER_TEMP": str(self.root)})
            command.assert_called_once()
        self.assertFalse(owned.exists())
        self.assertTrue(unrelated.is_dir())


@unittest.skipUnless(sys.platform == "darwin" and (signing.PRIVATE / "identity.p12").is_file()
                     and not os.environ.get("CI"), "Requires the local Ruri signing identity")
class KeychainSigningTests(unittest.TestCase):
    def test_new_credentials_and_updated_builds_read_without_ui_but_other_signers_cannot(self):
        with tempfile.TemporaryDirectory(prefix="ruri-keychain-test-") as temporary:
            work = Path(temporary)
            source = ROOT / "scripts/tests/signing-keychain-probe.swift"
            executable = work / "probe"
            # Change the executable's bytes between builds while retaining the
            # identifier and certificate. Neither run may show keychain UI.
            sources = []
            for revision in (1, 2):
                file = work / f"probe-{revision}.swift"
                file.write_text(source.read_text() + f'\nprint("build {revision}")\n')
                sources.append(file)
            store = work / "credentials.keychain-db"
            password = secrets.token_urlsafe(32)
            try:
                signing.command(["security", "create-keychain", "-p", password, str(store)], label="Test keychain creation")
                signing.command(["security", "unlock-keychain", "-p", password, str(store)], label="Test keychain unlock")
                with signing.signing_environment(os.environ) as environment:
                    requirements = []
                    for revision, file in enumerate(sources):
                        signing.command(["xcrun", "swiftc", str(file), "-o", str(executable)], label="Keychain probe compilation")
                        signing.command(["codesign", "--force", "--sign", environment["RURI_SIGN_IDENTITY"],
                                         "--keychain", environment["RURI_SIGN_KEYCHAIN"],
                                         "--identifier", "dev.ruri.signing-probe", str(executable)], label="Keychain probe signing")
                        result = subprocess.run(["codesign", "-d", "-r-", str(executable)], capture_output=True, text=True, check=True)
                        requirements.append(next(line for line in (result.stdout + result.stderr).splitlines() if line.startswith("designated =>")))
                        result = subprocess.run([str(executable), "read" if revision else "create", str(store)], capture_output=True, text=True)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(requirements[0], requirements[1])
                    signing.command(["codesign", "--force", "--sign", "-", "--identifier", "dev.ruri.signing-probe", str(executable)], label="Unrelated probe signing")
                    result = subprocess.run([str(executable), "deny", str(store)], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            finally:
                if store.exists():
                    signing.command(["security", "delete-keychain", str(store)], label="Test keychain cleanup")


if __name__ == "__main__":
    unittest.main()
