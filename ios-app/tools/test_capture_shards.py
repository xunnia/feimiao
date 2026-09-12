import json
import tempfile
import unittest
import sys
from pathlib import Path
from merge_android_capture_shards import collect
from run_bounded import run


class BoundedCommandTests(unittest.TestCase):
    def test_preserves_failure(self):
        self.assertEqual(run([sys.executable, "-c", "raise SystemExit(7)"], 5), 7)

    def test_kills_hung_command(self):
        self.assertEqual(run([sys.executable, "-c", "import time; time.sleep(30)"], 0.1), 124)


class CaptureShardsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for index in range(2):
            directory = self.root / f"android-parity-shard-{index}"
            directory.mkdir()
            (directory / "shard-images.txt").write_text(f"{index}.png\n", encoding="utf-8")
            entry = {"imagePath": f"android-app/outputs/parity/{index}.png",
                     "sidecarPath": f"android-app/outputs/parity/{index}.metadata.json",
                     "captureStatus": "captured"}
            self.write(index, "shard.json", {"index": index, "count": 2})
            self.write(index, "p0-business-android.json", {"expense": "1017.9"})
            self.write(index, "capture-metadata.json", {"sourceRevision": "abc", "platform": "android",
                "schemaVersion": 2, "fixture": {}, "sourceVersions": {}, "screenshots": [entry]})
            (directory / f"{index}.png").write_bytes(b"png")
            self.write(index, f"{index}.metadata.json", entry)

    def write(self, index, name, data):
        (self.root / f"android-parity-shard-{index}" / name).write_text(json.dumps(data), encoding="utf-8")

    def test_complete_shards_preserve_entries(self):
        result, _, files = collect(self.root, 2, "abc")
        self.assertEqual(result["counts"]["total"], 2)
        self.assertEqual(len(files), 4)

    def test_missing_shard_rejected(self):
        with self.assertRaises(ValueError):
            collect(self.root, 3, "abc")

    def test_old_revision_rejected(self):
        with self.assertRaises(ValueError):
            collect(self.root, 2, "def")

    def test_duplicate_receipt_rejected(self):
        self.write(1, "shard.json", {"index": 0, "count": 2})
        with self.assertRaises(ValueError):
            collect(self.root, 2, "abc")

    def test_different_business_rejected(self):
        self.write(1, "p0-business-android.json", {"expense": "0"})
        with self.assertRaises(ValueError):
            collect(self.root, 2, "abc")

    def test_path_escape_rejected(self):
        path = self.root / "android-parity-shard-1/capture-metadata.json"
        metadata = json.loads(path.read_text())
        metadata["screenshots"][0]["imagePath"] = "../secret.png"
        self.write(1, "capture-metadata.json", metadata)
        with self.assertRaises(ValueError):
            collect(self.root, 2, "abc")

    def test_empty_shard_rejected(self):
        path = self.root / "android-parity-shard-1/capture-metadata.json"
        metadata = json.loads(path.read_text())
        metadata["screenshots"] = []
        self.write(1, "capture-metadata.json", metadata)
        with self.assertRaises(ValueError):
            collect(self.root, 2, "abc")

    def test_navigation_prerequisite_uses_assigned_owner(self):
        first = self.root / "android-parity-shard-0"
        second = self.root / "android-parity-shard-1"
        metadata = json.loads((second / "capture-metadata.json").read_text())
        extra = json.loads((first / "0.metadata.json").read_text())
        metadata["screenshots"].append(extra)
        self.write(1, "capture-metadata.json", metadata)
        self.write(1, "0.metadata.json", extra)
        (second / "0.png").write_bytes(b"different prerequisite view")
        result, _, files = collect(self.root, 2, "abc")
        self.assertEqual(result["counts"]["total"], 2)
        self.assertIn(first / "0.png", files)
        self.assertNotIn(second / "0.png", files)

    def test_missing_assigned_image_rejected(self):
        (self.root / "android-parity-shard-1/shard-images.txt").write_text("absent.png\n")
        with self.assertRaises(ValueError):
            collect(self.root, 2, "abc")


if __name__ == "__main__":
    unittest.main()
