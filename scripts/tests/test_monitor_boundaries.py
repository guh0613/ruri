import json
from pathlib import Path
import subprocess
import unittest


class MonitorBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        result = subprocess.run(
            ["xcrun", "swift", "package", "dump-package"], cwd=root,
            check=True, capture_output=True, text=True,
        )
        cls.targets = {target["name"]: target for target in json.loads(result.stdout)["targets"]}

    def dependencies(self, name):
        result = set()
        for dependency in self.targets[name]["dependencies"]:
            kind = next(iter(dependency))
            child = dependency[kind][0]
            result.add(child)
            if child in self.targets:
                result.update(self.dependencies(child))
        return result

    def test_monitor_cannot_transitively_link_launcher_or_content_libraries(self):
        self.assertEqual(self.dependencies("RuriMonitor"), {
            "RuriMonitorRuntime", "RuriSessionKit", "RuriLocalization", "CSQLite", "CZlib",
        })

    def test_launcher_clients_do_not_link_monitor_implementation(self):
        for name in ["RuriCore", "Ruri", "RuriCLI"]:
            with self.subTest(target=name):
                dependencies = self.dependencies(name)
                self.assertIn("RuriSessionKit", dependencies)
                self.assertNotIn("RuriMonitorRuntime", dependencies)
                self.assertNotIn("RuriMonitor", dependencies)
