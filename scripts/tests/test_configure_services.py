import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "configure-services.py"
spec = importlib.util.spec_from_file_location("configure_services", SCRIPT)
services = importlib.util.module_from_spec(spec)
spec.loader.exec_module(services)


class ConfigureServicesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.resources = self.root / "Ruri.app" / "Contents" / "Resources"
        self.local = self.root / ".private" / "curseforge-api-key"
        self.local.parent.mkdir()
        self.output = self.resources / "RuriServices.plist"

    def configure(self, environment=None):
        services.configure(self.resources, environment or {}, self.root)

    def bundled_key(self):
        return plistlib.loads(self.output.read_bytes())["CurseForgeAPIKey"]

    def test_local_key_is_literal_and_trimmed(self):
        self.local.write_text("  $2a$example&<>'\"+token\n")
        self.configure()
        self.assertEqual(self.bundled_key(), "$2a$example&<>'\"+token")

    def test_environment_wins_without_reading_local_file(self):
        self.local.write_bytes(b"\xff")
        self.configure({services.KEY_VARIABLE: "$ci-key"})
        self.assertEqual(self.bundled_key(), "$ci-key")

    def test_empty_environment_disables_local_key_and_removes_stale_resource(self):
        self.local.write_text("local-key")
        self.configure()
        self.configure({services.KEY_VARIABLE: ""})
        self.assertFalse(self.output.exists())

    def test_missing_and_empty_local_file_need_no_key(self):
        self.configure()
        self.assertFalse(self.output.exists())
        self.local.write_text(" \n")
        self.configure()
        self.assertFalse(self.output.exists())

    def test_invalid_keys_are_rejected_without_echoing_them(self):
        for key in ["key\ninjection", "key\rinjection", "key\x00", "key\ttoken", "key token", "密钥"]:
            with self.subTest(key=key):
                with self.assertRaises(ValueError) as error:
                    self.configure({services.KEY_VARIABLE: key})
                self.assertNotIn(key, str(error.exception))
                self.assertFalse(self.output.exists())

    def test_cli_never_prints_credentials_on_success_or_failure(self):
        for key, status in [("$example-key", 0), ("$example-key\ninjected", 1)]:
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(self.resources)],
                env={services.KEY_VARIABLE: key}, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, status)
            self.assertNotIn("$example-key", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
