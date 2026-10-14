import json
from pathlib import Path
import shutil
import tempfile
import unittest

from PIL import Image, ImageDraw

from review_theme_popup_attachments import EXPECTED, inspect_attachments


class ThemePopupAttachmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory(prefix="feimiao-theme-fixture-")
        cls.source = Path(cls.fixture.name)
        attachments = []
        for index, name in enumerate(sorted(EXPECTED)):
            filename = f"capture-{index}.png"
            image = Image.new("RGB", (960 if "320-large" in name else 1260, 2736), "white")
            ImageDraw.Draw(image).rectangle((50, 100, 250, 500), fill="black")
            image.save(cls.source / filename)
            attachments.append({
                "exportedFileName": filename, "suggestedHumanReadableName": name + "_0.png",
                "deviceName": "iPhone Air",
            })
        (cls.source / "manifest.json").write_text(json.dumps([
            {"testIdentifier": "SyntheticFixture", "attachments": attachments}
        ]), encoding="utf-8")

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="feimiao-theme-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copytree(self.source, self.root, dirs_exist_ok=True)
        self.manifest_path = self.root / "manifest.json"
        self.manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))

    def inspect(self):
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")
        return inspect_attachments(self.root)

    def test_valid_fixture_checks_all_22_captures(self):
        records = self.inspect()
        self.assertEqual(len(records), 22)
        self.assertEqual({item["name"] for item in records}, EXPECTED)
        self.assertTrue(all(item["alphaRange"] == [255, 255] for item in records))

    def test_missing_capture_fails(self):
        self.manifest[0]["attachments"].pop()
        with self.assertRaisesRegex(ValueError, "Missing attachments"):
            self.inspect()

    def test_duplicate_capture_fails(self):
        self.manifest[0]["attachments"].append(self.manifest[0]["attachments"][0].copy())
        with self.assertRaisesRegex(ValueError, "duplicate attachment"):
            self.inspect()

    def test_path_traversal_fails_before_reading_image(self):
        self.manifest[0]["attachments"][0]["exportedFileName"] = "../outside.png"
        with self.assertRaisesRegex(ValueError, "Unsafe attachment filename"):
            self.inspect()

    def test_wrong_device_fails(self):
        self.manifest[0]["attachments"][0]["deviceName"] = "Other device"
        with self.assertRaisesRegex(ValueError, "Unexpected device"):
            self.inspect()

    def test_wrong_dimensions_fail(self):
        first = self.manifest[0]["attachments"][0]
        Image.new("RGB", (20, 30), "black").save(self.root / first["exportedFileName"])
        with self.assertRaisesRegex(ValueError, "Unexpected PNG dimensions"):
            self.inspect()

    def test_blank_capture_fails(self):
        first = self.manifest[0]["attachments"][0]
        Image.new("RGB", (1260, 2736), "white").save(self.root / first["exportedFileName"])
        with self.assertRaisesRegex(ValueError, "Blank capture"):
            self.inspect()

    def test_unknown_scene_fails(self):
        self.manifest[0]["attachments"][0]["suggestedHumanReadableName"] = "other_0.png"
        with self.assertRaisesRegex(ValueError, "Unexpected or duplicate attachment"):
            self.inspect()
