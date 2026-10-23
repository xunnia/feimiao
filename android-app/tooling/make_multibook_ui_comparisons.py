"""Compose genuine multibook Widget screenshots; never change source PNGs."""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

from make_ui_comparisons import _font, _wrap


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/ui_comparisons/2026-10-23-multibook"
VARIANTS = {"light": "浅色", "dark": "深色", "large": "320dp / 200% 字号"}
SCENES = {
    "book-new": ("新建账本", "1. 取消计入总账本开关，说明总账本自动包含全部；创建后可直接添加历史账单。"),
    "book-edit": ("编辑账本", "1. 保留名称备注，加入添加已有账单及管理关联入口；移出关联不删除原始账单。"),
    "entry-edit": ("编辑账单", "1. 原编辑模式无账本入口，现可多选场景账本；200% 字号分类格随文字增高。"),
}
NEW_SCENES = {
    "book-select": "多选场景账本（新增页面，无旧页面）",
    "history-add": "批量添加已有账单（新增页面，无旧页面）",
    "history-remove": "批量移出关联（新增页面，无旧页面）",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compose(index, scene, variant):
    title, note = SCENES[scene]
    phases = ("before-final", "after-final") if scene == "book-new" else ("before-verified", "after")
    sources = [OUT / f"{scene}_{variant}_{phase}.png" for phase in phases]
    hashes = [digest(path) for path in sources]
    images = [Image.open(path).convert("RGB") for path in sources]
    if images[0].size != images[1].size:
        raise ValueError(f"Scene dimensions differ: {scene}/{variant}")
    w, h = images[0].size
    canvas = Image.new("RGB", (2 * w + 96, h + 310), "#f7f7f8")
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 12), f"{index:02d} {title} · {VARIANTS[variant]}", font=_font(30), fill="#202124")
    for side, picture in enumerate(images):
        x = 24 + side * (w + 48)
        draw.text((x, 60), "改前 / HEAD 原始 UI" if side == 0 else "改后 / 当前源码", font=_font(24), fill="#555555")
        canvas.paste(picture, (x, 104))
        # The same region is marked on both sides; raw PNGs remain untouched.
        top = int(h * (0.43 if scene == "entry-edit" else 0.54))
        rect = (x + 12, 104 + top, x + w - 12, 104 + h - 8)
        draw.rectangle(rect, outline="#a75530", width=4)
        draw.ellipse((rect[0], rect[1], rect[0] + 44, rect[1] + 44), fill="#a75530")
        draw.text((rect[0] + 14, rect[1] + 4), "1", font=_font(27), fill="white")
    y = h + 128
    for line in _wrap(draw, note, _font(24), canvas.width - 48):
        draw.text((24, y), line, font=_font(24), fill="#444444")
        y += 34
    draw.text((24, y + 8), "同数据 / AppTheme / 字体 / 尺寸；真实 Flutter Widget 离屏，非装机或真机。", font=_font(22), fill="#666666")
    if variant == "large" and scene == "entry-edit":
        draw.text((24, y + 42), "改前原有 4px 分类格溢出保留；改后不得吞掉布局异常。", font=_font(22), fill="#666666")
    if variant == "large" and scene in ("book-new", "book-edit"):
        draw.text((24, y + 42), "备注窄列在200%字号下仍竖排，属既有缺口，未宣称整页达标。", font=_font(22), fill="#666666")
    target = OUT / f"{index:02d}_{scene}_{variant}_comparison.png"
    canvas.save(target, optimize=True)
    if hashes != [digest(path) for path in sources]:
        raise ValueError("Original screenshots were changed")
    return {"scene": scene, "variant": variant, "comparison": target.name,
            "before": sources[0].name, "after": sources[1].name,
            "before_sha256": hashes[0], "after_sha256": hashes[1], "size": [w, h]}


def main():
    pairs = []
    for scene in SCENES:
        for variant in VARIANTS:
            pairs.append(compose(len(pairs) + 1, scene, variant))
    contact = Image.new("RGB", (1440, 2000), "#f7f7f8")
    for index, pair in enumerate(pairs):
        image = Image.open(OUT / pair["comparison"])
        image.thumbnail((480, 650), Image.Resampling.LANCZOS)
        contact.paste(image, ((index % 3) * 480, (index // 3) * 650))
    contact.save(OUT / "00_multibook_comparison_contact.png", optimize=True)
    additions = []
    gallery = Image.new("RGB", (1440, 3300), "#f7f7f8")
    for scene, title in NEW_SCENES.items():
        for variant in VARIANTS:
            path = OUT / f"{scene}_{variant}_after.png"
            additions.append({"scene": scene, "title": title, "variant": variant,
                              "after": path.name, "after_sha256": digest(path),
                              "before": None, "reason": "new screen"})
            index = len(additions) - 1
            x, y = (index % 3) * 480, (index // 3) * 1100
            draw = ImageDraw.Draw(gallery)
            draw.text((x + 12, y + 8), f"{scene} / {VARIANTS[variant]}", font=_font(20), fill="#333333")
            picture = Image.open(path)
            picture.thumbnail((460, 1040), Image.Resampling.LANCZOS)
            gallery.paste(picture, (x + 10, y + 48))
    gallery.save(OUT / "00_multibook_new_screens_contact.png", optimize=True)
    (OUT / "comparison_manifest.json").write_text(json.dumps({
        "kind": "Flutter Widget offscreen", "device_verified": False,
        "pairs": pairs, "new_screens": additions,
        "current_sources": {str(path.relative_to(ROOT)): digest(path) for path in [
            ROOT / "lib/views/books/book_sheet.dart",
            ROOT / "lib/views/books/transaction_books_sheet.dart",
            ROOT / "lib/views/home/manual_add_sheet.dart",
            ROOT / "lib/views/quick_add/category_grid.dart",
            ROOT / "test/multibook_ui_test.dart",
        ]},
        "notes": "Original initial/before-verified PNGs retained. Book-new uses before-final/after-final from an isolated project with identical fonts/data, explicit precacheImage and decoded RawImage assertions. Other pairs retain before-verified/after. Existing 200% remark vertical wrapping remains unaccepted."
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{len(pairs)} same-font comparison pairs, {len(additions)} new-screen captures; original hashes unchanged.")


if __name__ == "__main__":
    main()
