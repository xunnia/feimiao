import re
import unittest
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1] / "QingJi"
BLOCK_OPEN = re.compile(r"\.toolbar\s*\{|some ToolbarContent\s*\{")
ITEM_OPEN = re.compile(r"\bToolbarItem(?:Group)?\(")
# iOS 26 toolbars draw one shared Liquid Glass container. These add a second surface
# or hide the system one, which is what stacked the effects on top-bar buttons.
FORBIDDEN = re.compile(
    r"liquidGlass(?:Circle|Pill|PrimaryCircle|PrimaryPill|Key)Control|LiquidGlass(?:Icon|Pill)Button"
    r"|sharedBackgroundVisibility\(\.hidden\)|GlassEffectContainer|glassEffect|buttonStyle\(\.glass")
# Unstyled controls inherit the app-wide `.buttonStyle(.glass(.clear))` fallback.
CONTROL = re.compile(r"\b(?:Button|Menu|NavigationLink|EditButton)\b\s*[({]")
NATIVE = re.compile(r"\.nativeToolbarControl\(\)|\bToolbarIconButton\(")
# The app root tints every control with the accent color; toolbar items reset it so
# they stay monochrome like the system back button.
ACCENT = re.compile(r"\.(?:tint|foregroundStyle|foregroundColor)\((?:Color)?\.accentColor\)")


def braced(text, start):
    """Return the text from `start` (an opening brace) through its matching close."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ValueError("unbalanced braces")


def toolbar_blocks():
    for path in sorted(SOURCE.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for match in BLOCK_OPEN.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            yield f"{path.relative_to(SOURCE).as_posix()}:{line}", braced(text, match.end() - 1)


class ToolbarNativeGlassTests(unittest.TestCase):
    def test_toolbar_blocks_draw_no_custom_glass(self):
        blocks = list(toolbar_blocks())
        self.assertGreaterEqual(len(blocks), 60)
        offenders = [f"{where}: {hit.group(0)}" for where, block in blocks for hit in FORBIDDEN.finditer(block)]
        self.assertEqual(offenders, [])

    def test_toolbar_controls_reset_the_app_glass_fallback(self):
        items, offenders = 0, []
        for where, block in toolbar_blocks():
            for match in ITEM_OPEN.finditer(block):
                body = braced(block, block.index("{", match.end()))
                items += 1
                if CONTROL.search(body) and not NATIVE.search(body):
                    offenders.append(f"{where}: {' '.join(body.split())[:90]}")
        self.assertGreaterEqual(items, 100)
        self.assertEqual(offenders, [])

    def test_toolbar_controls_stay_monochrome(self):
        helper = (SOURCE / "Views/Support/LiquidGlass.swift").read_text(encoding="utf-8")
        body = braced(helper, helper.index("{", helper.index("func nativeToolbarControl()")))
        self.assertIn(".tint(Color.primary)", body)
        offenders = [f"{where}: {hit.group(0)}" for where, block in toolbar_blocks() for hit in ACCENT.finditer(block)]
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
