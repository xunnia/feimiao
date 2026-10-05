"""Compare immutable, same-scene Flutter renders. No device claim."""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw
from make_ui_comparisons import _font

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/ui_comparisons/2026-10-04-chat-stream"
SCENES = [
    ("waiting", "等待反馈", "1. 保留简洁状态与实际文字动效；无摘要时不放假入口。"),
    ("live-expanded", "生成中展开", "1. 生成中可以展开。2. 真实摘要保留段落与强调，持续更新。"),
    ("completed-expanded", "完成后展开", "1. 本地耗时标为处理时长。2. 摘要排版与正文分隔。"),
    ("completed-collapsed", "完成后收起", "1. 正文到达自动收起；可以再次展开，重开可恢复。"),
    ("night-live", "深色生成中", "1. 深色入口与文字跟主题。2. 过程可展开，不再只有状态。"),
    ("large-live", "320dp与两倍字", "1. 标签不溢出。2. 摘要高度受控，支持阅读与滚动。"),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    pairs = []
    for index, (name, title, note) in enumerate(SCENES, 1):
        paths = [OUT / phase / f"{name}.png" for phase in ("before", "after")]
        hashes = [digest(path) for path in paths]
        metadata = [json.loads(path.with_suffix(".json").read_text("utf-8")) for path in paths]
        images = [Image.open(path).convert("RGB") for path in paths]
        if images[0].size != images[1].size or metadata[0]["logical_size"] != metadata[1]["logical_size"]:
            raise ValueError("Scene dimensions changed")
        if metadata[0]["text_scale"] != metadata[1]["text_scale"]:
            raise ValueError("Scene text scale changed")
        if metadata[1]["source_sha256"] != digest(ROOT / "lib/views/home/ai_chat_panel.dart"):
            raise ValueError("Screenshot is not from the current production panel")
        if metadata[1]["summary_widget_sha256"] != digest(ROOT / "lib/views/home/chat_thinking_summary.dart"):
            raise ValueError("Screenshot is not from the current summary widget")
        width, height = map(int, metadata[0]["logical_size"])
        canvas = Image.new("RGB", (width * 2 + 48, height + 188), "#f7f7f8")
        draw = ImageDraw.Draw(canvas)
        draw.text((12, 8), f"{index:02d} {title}", font=_font(18), fill="#202124")
        for side, picture in enumerate(images):
            x = 12 + side * (width + 24)
            draw.text((x, 38), "改前" if side == 0 else "改后", font=_font(14), fill="#555555")
            canvas.paste(picture.resize((width, height), Image.Resampling.LANCZOS), (x, 64))
            for number, top, bottom in [(1, 190 if name == "large-live" else 124, 236 if name == "large-live" else 156)] + (
                [(2, 244 if name == "large-live" else 158, 525 if name == "large-live" else 312)]
                if "expanded" in name or name in ("night-live", "large-live") else []):
                rect = (x + 14, 64 + top, x + width - 14, 64 + bottom)
                draw.rectangle(rect, outline="#a75530", width=2)
                draw.ellipse((rect[0], rect[1], rect[0] + 22, rect[1] + 22), fill="#a75530")
                draw.text((rect[0] + 7, rect[1] + 1), str(number), font=_font(13), fill="white")
        draw.text((12, height + 82), note, font=_font(12), fill="#555555")
        draw.text((12, height + 110), "同数据/主题/尺寸/字体的真实Flutter离屏渲染；非装机，非Claude实测。", font=_font(12), fill="#555555")
        draw.text((12, height + 138), "原图不加标注；实际交互、动效像素与SQLite恢复另有测试。", font=_font(12), fill="#555555")
        target = OUT / f"{index:02d}_{name}_before_after.png"
        canvas.save(target, optimize=True)
        if hashes != [digest(path) for path in paths]:
            raise ValueError("Original screenshot modified")
        pairs.append({"scene": name, "comparison": target.name, "before_sha256": hashes[0],
                      "after_sha256": hashes[1], "before_source_sha256": metadata[0]["source_sha256"],
                      "after_source_sha256": metadata[1]["source_sha256"]})
    contact = Image.new("RGB", (1260, 1000), "#f7f7f8")
    for index, pair in enumerate(pairs):
        picture = Image.open(OUT / pair["comparison"])
        picture.thumbnail((420, 500), Image.Resampling.LANCZOS)
        contact.paste(picture, ((index % 3) * 420, (index // 3) * 500))
    contact.save(OUT / "00_chat_stream_contact.png", optimize=True)
    (OUT / "comparison_manifest.json").write_text(json.dumps({"kind": "Flutter Widget offscreen",
        "device_verified": False, "pairs": pairs}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{len(pairs)} comparisons; original hashes and current source verified.")


if __name__ == "__main__":
    main()
