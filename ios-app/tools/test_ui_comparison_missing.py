import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from PIL import Image


class MissingComparisonTests(unittest.TestCase):
    def run_report(self, status="missing", android_exists=True):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            if android_exists:
                Image.new("RGB", (20, 30), "white").save(root / "android.png")
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"pairs": [{
                "id": "assets-funds", "android": "android.png",
                "ios": None, "iosStatus": status, "notes": "P4 pending"
            }]}))
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name("make_ios_ui_comparisons.py")),
                "--root", str(root), "--manifest", str(manifest),
                "--output-dir", str(root / "out")
            ], capture_output=True, text=True)
            index = root / "out/comparison-index.json"
            return result, json.loads(index.read_text()) if index.exists() else None

    def test_declared_missing_target_is_reported_not_compared(self):
        result, report = self.run_report()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["pairCount"], 0)
        self.assertEqual(report["missingTargets"][0]["id"], "assets-funds")
        self.assertFalse(report["productComplete"])

    def test_undeclared_null_fails(self):
        result, _ = self.run_report("captured")
        self.assertNotEqual(result.returncode, 0)

    def test_missing_android_still_fails(self):
        result, _ = self.run_report(android_exists=False)
        self.assertNotEqual(result.returncode, 0)
