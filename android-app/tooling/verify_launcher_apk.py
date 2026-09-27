"""Verify the manifest-resolved launcher PNGs inside a built APK."""
import argparse
import io
import re
import subprocess
import zipfile
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('apk', type=Path)
parser.add_argument('--aapt', required=True)
parser.add_argument('--source', type=Path, required=True)
args = parser.parse_args()
badging = subprocess.check_output([args.aapt, 'dump', 'badging', str(args.apk)], text=True, encoding='utf-8')
icons = re.findall(r"application-icon-(\d+):'([^']+)'", badging)
if not icons:
    raise SystemExit('No manifest-resolved launcher icons found')
expected_sizes = {120: 48, 160: 48, 240: 72, 320: 96, 480: 144, 640: 192}
with Image.open(args.source) as original, zipfile.ZipFile(args.apk) as archive:
    original = original.convert('RGBA')
    for density, name in icons:
        with Image.open(io.BytesIO(archive.read(name))) as actual:
            size = actual.size
            expected = original.resize(size, Image.Resampling.LANCZOS)
            if actual.convert('RGBA').tobytes() != expected.tobytes():
                raise SystemExit(f'Launcher pixels differ from approved source: {density} {name}')
            if int(density) in expected_sizes and size != (expected_sizes[int(density)],) * 2:
                raise SystemExit(f'Unexpected launcher size: {density} {size}')
            print(f'ICON_OK density={density} size={size} resource={name}')
print(f'Verified {len(icons)} manifest-resolved launcher resources')
