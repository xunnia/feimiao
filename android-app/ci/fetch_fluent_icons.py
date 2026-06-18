#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
下载 Microsoft Fluent UI Emoji 的「3D」PNG 图标到 android-app/assets/cat_icons/。

用途：
- CI 在「构建 APK」之前执行（见 .github/workflows/android-ci.yml）。
- 本地也能手动跑：  python3 android-app/ci/fetch_fluent_icons.py

设计要点（解决交接文档里「文件夹名靠猜 + API 限流」的卡点）：
- 下表是「分类 emoji → Fluent 资源文件夹名」的人工核对全表，
  每一条的真实路径都已逐个核验过确实存在（核验方式见 接入说明.md）。
- 普通 emoji：      assets/{Folder}/3D/{base}_3d.png
- 带肤色的 emoji：  assets/{Folder}/Default/3D/{base}_3d_default.png
  （base = 文件夹名转小写、空格换成下划线、连字符保留）
- 本地统一存成 {base}.png，与 Dart 端 fluent_icon.dart 里 kEmojiToFluentBase 的 value 一一对应。
- 任意一张下载失败：只告警、不报错（脚本永远 exit 0）；App 端会自动回退到原 emoji 文本，绝不崩。
- 直接从 raw.githubusercontent.com 拉「具体文件」，不走会限流的目录枚举 API。
"""

import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

RAW = "https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets"

# (emoji, Fluent 文件夹名, 是否带肤色变体)
ICONS = [
    # —— 食品餐饮 ——
    ("🍜", "Steaming bowl", False),
    ("🍳", "Cooking", False),
    ("🍱", "Bento box", False),
    ("🍚", "Cooked rice", False),
    ("🧋", "Bubble tea", False),
    ("🍿", "Popcorn", False),
    ("🥬", "Leafy green", False),
    ("🍻", "Clinking beer mugs", False),
    ("🧂", "Salt", False),
    # —— 购物消费 ——
    ("🛍️", "Shopping bags", False),
    ("🛋️", "Couch and lamp", False),
    ("💄", "Lipstick", False),
    ("📱", "Mobile phone", False),
    ("🎟️", "Admission tickets", False),
    ("📺", "Television", False),
    ("⌚", "Watch", False),
    ("🧸", "Teddy bear", False),
    ("👟", "Running shoe", False),
    ("🐾", "Paw prints", False),
    ("📎", "Paperclip", False),
    ("🧰", "Toolbox", False),
    # —— 出行交通 ——
    ("🚗", "Automobile", False),
    ("🚕", "Taxi", False),
    ("🚌", "Bus", False),
    ("🅿️", "P button", False),
    ("⛽", "Fuel pump", False),
    ("🚄", "High-speed train", False),
    ("✈️", "Airplane", False),
    ("🔧", "Wrench", False),
    # —— 休闲娱乐 ——
    ("🎮", "Video game", False),
    ("🧳", "Luggage", False),
    ("🎤", "Microphone", False),
    ("🏋️", "Person lifting weights", True),
    ("💆", "Person getting massage", True),
    ("🀄", "Mahjong red dragon", False),
    ("🍸", "Cocktail glass", False),
    ("🎭", "Performing arts", False),
    # —— 居家生活 ——
    ("🏠", "House", False),
    ("📶", "Antenna bars", False),
    ("💡", "Light bulb", False),
    ("🚰", "Potable water", False),
    ("🔥", "Fire", False),
    ("🏢", "Office building", False),
    ("🏦", "Bank", False),
    ("🚙", "Sport utility vehicle", False),
    ("🧹", "Broom", False),
    # —— 医疗健康 ——
    ("💊", "Pill", False),
    ("🏥", "Hospital", False),
    ("🩺", "Stethoscope", False),
    # —— 教育学习 ——
    ("📚", "Books", False),
    ("📖", "Open book", False),
    ("🎓", "Graduation cap", False),
    ("🖨️", "Printer", False),
    # —— 人情往来 ——
    ("🎁", "Wrapped gift", False),
    ("🧧", "Red envelope", False),
    ("🎀", "Ribbon", False),
    # —— 其他 / 收入 ——
    ("📦", "Package", False),
    ("⚖️", "Balance scale", False),
    ("📉", "Chart decreasing", False),
    ("❤️", "Red heart", False),
    ("💰", "Money bag", False),
    ("🏆", "Trophy", False),
    ("📈", "Chart increasing", False),
    ("↩️", "Right arrow curving left", False),
    ("💵", "Dollar banknote", False),
]

OUT = Path(__file__).resolve().parent.parent / "assets" / "cat_icons"


def base_of(folder: str) -> str:
    return folder.lower().replace(" ", "_")


def url_of(folder: str, skin: bool) -> str:
    b = base_of(folder)
    enc = urllib.parse.quote(folder)
    if skin:
        return f"{RAW}/{enc}/Default/3D/{b}_3d_default.png"
    return f"{RAW}/{enc}/3D/{b}_3d.png"


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    ok = miss = skip = 0
    seen = set()
    for emoji, folder, skin in ICONS:
        b = base_of(folder)
        if b in seen:  # 同一资源被多个分类复用（如红包），只下一次
            continue
        seen.add(b)
        dest = OUT / f"{b}.png"
        if dest.exists() and dest.stat().st_size > 0:
            skip += 1
            continue
        u = url_of(folder, skin)
        try:
            req = urllib.request.Request(u, headers={"User-Agent": "qingji-ci"})
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
            if not data:
                raise ValueError("空响应")
            dest.write_bytes(data)
            ok += 1
            print(f"  OK  {emoji} {folder} -> {dest.name} ({len(data)//1024}KB)")
        except Exception as e:  # noqa: BLE001
            miss += 1
            print(f"  !!  {emoji} {folder} 下载失败：{e}  (App 端将回退 emoji)")
        time.sleep(0.05)
    print(f"\nFluent 3D 图标：新下载 {ok}，已存在跳过 {skip}，失败 {miss}，目录 {OUT}")
    # 永远返回 0：缺图标不阻断构建，App 端有 emoji 兜底
    return 0


if __name__ == "__main__":
    sys.exit(main())
