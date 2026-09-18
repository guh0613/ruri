import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("configure_app", ROOT / "scripts/configure-app.py")
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class ConfigureAppTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / "Info.plist"
        self.source = (ROOT / "Resources/Info.plist").read_bytes()

    def configure(self, environment):
        self.path.write_bytes(self.source)
        with patch.dict(os.environ, environment, clear=True):
            app.configure(self.path)
        return plistlib.loads(self.path.read_bytes())

    def test_local_and_ci_builds_keep_builtin_login_without_override(self):
        for environment in ({}, {"RURI_MICROSOFT_CLIENT_ID": ""}, {"RURI_MICROSOFT_CLIENT_ID": " \n"}):
            with self.subTest(environment=environment):
                info = self.configure(environment)
                self.assertEqual(info["RuriMicrosoftClientID"], "92e3a8ab-0d43-4868-bbc2-58ddcb2081c5")

    def test_distribution_can_override_client_id_without_changing_source(self):
        client_id = "df01d133-3715-49b0-a48f-31e486c76402"
        info = self.configure({"RURI_MICROSOFT_CLIENT_ID": " " + client_id + "\n"})
        self.assertEqual(info["RuriMicrosoftClientID"], client_id)
        self.assertEqual((ROOT / "Resources/Info.plist").read_bytes(), self.source)

    def test_invalid_override_does_not_silently_ship_a_broken_login(self):
        with self.assertRaises(ValueError):
            self.configure({"RURI_MICROSOFT_CLIENT_ID": "not-a-client-id"})
        self.assertEqual(self.path.read_bytes(), self.source)


if __name__ == "__main__":
    unittest.main()
