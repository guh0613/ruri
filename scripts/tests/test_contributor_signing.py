import importlib.util
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("signing", ROOT / "scripts/release/signing.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class ContributorSigningTests(unittest.TestCase):
    def test_requires_explicit_opt_in(self):
        self.assertIsNone(signing.contributor_identity({}))

    def test_rejects_release_and_ci_environments_before_signing(self):
        for flag, value in [("RURI_REQUIRE_SIGNING", "1"), ("CI", "1"),
                            ("GITHUB_ACTIONS", "true"), ("CI", ""), ("GITHUB_ACTIONS", "")]:
            environment = {signing.CONTRIBUTOR_IDENTITY: signing.fingerprint(), flag: value}
            with self.subTest(flag=flag, value=value):
                with self.assertRaisesRegex(signing.SigningError, "only available for local builds"):
                    with signing.signing_environment(environment):
                        self.fail("Contributor signing must reject release and CI builds")
                with self.assertRaisesRegex(signing.SigningError, "only available for local builds"):
                    signing.verify(ROOT / "build/Ruri.app", environment)

    def test_requires_an_exact_sha1_fingerprint(self):
        for identity in ["", "-", "Apple Development", signing.fingerprint() + "\n"]:
            with self.subTest(identity=identity):
                with self.assertRaisesRegex(signing.SigningError, "SHA-1"):
                    with signing.signing_environment({signing.CONTRIBUTOR_IDENTITY: identity}):
                        self.fail("Invalid contributor identities must fail before a build starts")

    def test_normalizes_fingerprint_case(self):
        identity = signing.fingerprint()
        self.assertEqual(signing.contributor_identity({signing.CONTRIBUTOR_IDENTITY: identity.lower()}), identity)

    def test_rejects_conflicting_ad_hoc_override(self):
        with self.assertRaisesRegex(signing.SigningError, "conflicts"):
            with signing.signing_environment({signing.CONTRIBUTOR_IDENTITY: signing.fingerprint(),
                                              "RURI_SIGN_IDENTITY": "-"}):
                self.fail("Contributor signing must not silently select ad hoc signing")

    @unittest.skipUnless(os.environ.get(signing.CONTRIBUTOR_IDENTITY), "Requires a local Apple Development identity")
    def test_validates_a_real_local_development_identity(self):
        identity = os.environ[signing.CONTRIBUTOR_IDENTITY]
        with signing.signing_environment({signing.CONTRIBUTOR_IDENTITY: identity}) as environment:
            self.assertEqual(environment["RURI_SIGN_IDENTITY"], identity.upper())
            self.assertNotIn("RURI_SIGN_KEYCHAIN", environment)
            self.assertFalse(any(name in environment for name in signing.SECRET_VARIABLES))


if __name__ == "__main__":
    unittest.main()
