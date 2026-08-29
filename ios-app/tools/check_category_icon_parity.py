"""Verify that Android and iOS ship the same two category icon sets."""

from pathlib import Path
import sys


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    failed = False
    for style in ("filled", "line"):
        android_dir = root / "android-app" / f"assets/cat_icons_{style}"
        ios_dir = root / "ios-app" / "QingJi" / "Resources" / "CategoryIcons" / style
        android = {path.stem for path in android_dir.glob("*.svg")}
        ios = {path.stem for path in ios_dir.glob("*.png")}
        print(f"{style}: Android={len(android)} iOS={len(ios)}")
        missing = sorted(android - ios)
        extra = sorted(ios - android)
        if missing:
            print(f"missing iOS {style}: {', '.join(missing)}")
            failed = True
        if extra:
            print(f"extra iOS {style}: {', '.join(extra)}")
            failed = True
    if failed:
        print("Android/iOS category icon asset sets are not identical", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
