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
        self.certificate = self.root / "public.cer"
        self.certificate.write_bytes(b"public certificate")
        self.addCleanup(patch.stopall)
        patch.object(signing, "CERTIFICATE", self.certificate).start()

    def ci_environment(self):
        return {"CI": "true", "RURI_REQUIRE_SIGNING": "1", "RUNNER_TEMP": str(self.root),
                "RURI_SIGN_P12_BASE64": base64.b64encode(b"private identity").decode(),
                "RURI_SIGN_P12_PASSWORD": "private password"}

    def test_ci_never_uses_a_runners_local_identity(self):
        for ci_flag in ["CI", "GITHUB_ACTIONS"]:
            with self.subTest(ci_flag=ci_flag):
                with patch.object(signing, "available_identities", return_value={signing.fingerprint()}) as identities:
                    with self.assertRaises(signing.SigningError):
                        with signing.signing_environment({ci_flag: "true", "RURI_REQUIRE_SIGNING": "1"}):
                            self.fail("Missing release credentials must not use a runner's local keychain")
                    identities.assert_not_called()

    def test_local_build_uses_the_pinned_xcode_identity_without_exporting_it(self):
        with patch.object(signing, "available_identities", return_value={signing.fingerprint()}):
            with patch.object(signing, "command") as command:
                with signing.signing_environment({"RURI_SIGN_KEYCHAIN": "/obsolete/keychain"}) as environment:
                    self.assertEqual(environment["RURI_SIGN_IDENTITY"], signing.fingerprint())
                    self.assertNotIn("RURI_SIGN_KEYCHAIN", environment)
                command.assert_not_called()

    def test_unavailable_pinned_identity_cannot_silently_downgrade_required_builds(self):
        with patch.object(signing, "available_identities", return_value={"A" * 40}):
            with self.assertRaisesRegex(signing.SigningError, "unavailable"):
                with signing.signing_environment({"RURI_REQUIRE_SIGNING": "1"}):
                    self.fail("An unrelated local identity must not sign a required package")

    def test_contributor_build_can_use_adhoc_without_private_credentials(self):
        with signing.signing_environment({"CI": "true"}) as environment:
            self.assertEqual(environment["RURI_SIGN_IDENTITY"], "-")

    def test_required_release_rejects_an_adhoc_override(self):
        with self.assertRaises(signing.SigningError):
            with signing.signing_environment({"RURI_REQUIRE_SIGNING": "1", "RURI_SIGN_IDENTITY": "-"}):
                self.fail("A release must not silently become ad hoc")

    def test_partial_or_invalid_secrets_do_not_fall_back(self):
        for environment in [
            {"RURI_SIGN_P12_PASSWORD": "password"},
            {"RURI_SIGN_P12_BASE64": "YWJj"},
            {"RURI_SIGN_P12_BASE64": "invalid!", "RURI_SIGN_P12_PASSWORD": "password"},
        ]:
            with self.subTest(environment=tuple(environment)):
                with self.assertRaises(signing.SigningError):
                    signing.signing_material(environment)

    def test_unpinned_identity_override_is_rejected(self):
        with patch.object(signing, "command") as command:
            with self.assertRaisesRegex(signing.SigningError, "does not match"):
                with signing.signing_environment({"RURI_SIGN_IDENTITY": "A" * 40}):
                    self.fail("An unrelated signing identity must not be accepted")
            command.assert_not_called()

    def mock_security(self, arguments, **kwargs):
        if arguments[:2] == ["security", "create-keychain"]:
            Path(arguments[-1]).touch()
        if arguments == ["security", "list-keychains", "-d", "user"]:
            return b'    "/existing/login.keychain-db"\n    "/existing/custom keychain.keychain-db"\n'
        if arguments[:2] == ["security", "find-identity"]:
            return f'  1) {signing.fingerprint()} "Apple Development: Fixture"\n'.encode()
        return b""

    def test_build_failure_cleans_keychain_and_never_passes_passwords_to_build(self):
        environment = self.ci_environment()
        with patch.object(signing, "command", side_effect=self.mock_security) as command:
            with self.assertRaisesRegex(RuntimeError, "build failed"):
                with signing.signing_environment(environment) as child:
                    self.assertEqual(child["RURI_SIGN_IDENTITY"], signing.fingerprint())
                    self.assertTrue(Path(child["RURI_SIGN_KEYCHAIN"]).exists())
                    self.assertFalse(any(name in child for name in signing.SECRET_VARIABLES))
                    command.assert_any_call(["security", "list-keychains", "-d", "user", "-s",
                                             "/existing/login.keychain-db", "/existing/custom keychain.keychain-db",
                                             child["RURI_SIGN_KEYCHAIN"]], label="Temporary keychain search configuration")
                    command.assert_any_call(["security", "import", str(signing.INTERMEDIATE_CERTIFICATE),
                                             "-k", child["RURI_SIGN_KEYCHAIN"]], label="Apple intermediate certificate import")
                    raise RuntimeError("build failed")
            self.assertEqual(command.call_args.args[0][:2], ["security", "delete-keychain"])
        self.assertFalse(list(self.root.glob("ruri-signing-*")))

    def test_wrong_private_identity_is_rejected_and_cleaned(self):
        def security(arguments, **kwargs):
            return b"wrong identity" if arguments[1] == "find-identity" else self.mock_security(arguments, **kwargs)
        with patch.object(signing, "command", side_effect=security) as command:
            with self.assertRaisesRegex(signing.SigningError, "does not match"):
                with signing.signing_environment(self.ci_environment()):
                    self.fail("An unrelated certificate must not sign Ruri")
            self.assertEqual(command.call_args.args[0][:2], ["security", "delete-keychain"])

    def test_package_verification_requires_apple_chain_and_matching_team_on_every_helper(self):
        with patch.object(signing, "certificate_team", return_value="ABCDEFGHIJ"):
            with patch.object(signing, "command", return_value=b"TeamIdentifier=ABCDEFGHIJ\n") as command:
                signing.verify(self.root / "Ruri.app", {"RURI_SIGN_IDENTITY": signing.fingerprint()})
        checks = [call.args[0] for call in command.call_args_list if "--verify" in call.args[0]]
        self.assertEqual(len(checks), 7)
        for arguments in checks:
            requirement = arguments[arguments.index("-R") + 1]
            self.assertIn("anchor apple generic", requirement)
            self.assertIn('certificate leaf = H"' + signing.fingerprint() + '"', requirement)
            self.assertIn("1.2.840.113635.100.6.2.1", requirement)
            self.assertIn("1.2.840.113635.100.6.1.12", requirement)
            self.assertIn('subject.OU] = "ABCDEFGHIJ"', requirement)

    def test_package_verification_rejects_a_missing_team_identifier(self):
        with patch.object(signing, "certificate_team", return_value="ABCDEFGHIJ"):
            with patch.object(signing, "command", return_value=b"TeamIdentifier=not set\n"):
                with self.assertRaisesRegex(signing.SigningError, "Team ID"):
                    signing.verify(self.root / "Ruri.app", {"RURI_SIGN_IDENTITY": signing.fingerprint()})

    def test_failed_commands_do_not_disclose_secret_arguments_or_output(self):
        result = subprocess.CompletedProcess([], 1, b"private data", b"private password")
        with patch.object(subprocess, "run", return_value=result):
            with self.assertRaises(signing.SigningError) as error:
                signing.command(["security", "import", "-P", "private password"], label="Import")
        self.assertNotIn("private", str(error.exception))

    def test_security_passwords_use_stdin_and_secrets_are_not_inherited(self):
        result = subprocess.CompletedProcess([], 0, b"", b"")
        password = 'private "password" \\ value'
        with patch.object(subprocess, "run", return_value=result) as run:
            signing.command(["security", "unlock-keychain", "-p", password, "/keychain path"], label="Unlock",
                            env={"PATH": "/usr/bin", "RURI_SIGN_P12_BASE64": "private data", "RURI_SIGN_P12_PASSWORD": password})
        self.assertEqual(run.call_args.args[0], ["/usr/bin/security", "-i"])
        self.assertEqual(run.call_args.kwargs["env"], {"PATH": "/usr/bin"})
        self.assertEqual(run.call_args.kwargs["input"],
                         b'"unlock-keychain" "-p" "private \\"password\\" \\\\ value" "/keychain path"\n')

    def test_security_stdin_rejects_line_injection_and_truncation(self):
        for value in ["password\nlist-keychains", "password\rcommand", "password\0suffix", "x" * 4096]:
            with patch.object(subprocess, "run") as run:
                with self.assertRaises(signing.SigningError):
                    signing.command(["security", "unlock-keychain", "-p", value], label="Unlock")
                run.assert_not_called()

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


@unittest.skipUnless(sys.platform == "darwin" and os.environ.get("RURI_TEST_SIGNING") == "1"
                     and not os.environ.get("CI"), "Requires explicit opt-in and the local Apple signing identity")
class KeychainSigningTests(unittest.TestCase):
    def test_disposable_keychain_acl_survives_updates_and_rejects_other_signers(self):
        # security create-keychain creates a legacy keychain. This covers ACL
        # continuity only, not the login keychain's additional partition checks.
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
                with signing.signing_environment(dict(os.environ, RURI_REQUIRE_SIGNING="1")) as environment:
                    requirements = []
                    keychain_options = (["--keychain", environment["RURI_SIGN_KEYCHAIN"]]
                                        if environment.get("RURI_SIGN_KEYCHAIN") else [])
                    for revision, file in enumerate(sources):
                        signing.command(["xcrun", "swiftc", str(file), "-o", str(executable)], label="Keychain probe compilation")
                        signing.command(["codesign", "--force", "--sign", environment["RURI_SIGN_IDENTITY"],
                                         *keychain_options,
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
