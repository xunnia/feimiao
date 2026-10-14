"""Annotate actual asset overview captures without changing their source pixels."""

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

import make_ui_comparisons as ui


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'android-app/outputs/ui_comparisons/2026-10-03-asset-overview'


def pair(number, theme):
    paths = [OUT / f'page-{theme}-{stage}.png' for stage in ('before', 'after')]
    hashes = [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]
    images = [Image.open(path).convert('RGB') for path in paths]
    if any(image.size != (1260, 2736) for image in images):
        raise ValueError('Expected matching 420 x 912 dp captures at 3x')
    canvas = Image.new('RGB', (888, 1130), '#f7f7f8')
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), f'{number:02d} 资产总览 · {"暖色" if theme == "warm" else "深色"}',
              font=ui._font(22), fill='#202124')
    draw.text((16, 43), '修改前（本地在途基线）', font=ui._font(14), fill='#666666')
    draw.text((452, 43), '修改后（当前源码）', font=ui._font(14), fill='#666666')
    boxes = [[(16, 121, 404, 321), (16, 121, 404, 375)],
             [(16, 321, 404, 479), (16, 388, 404, 623)]]
    for side, image in enumerate(images):
        x, y = 16 + side * 436, 70
        # The whole image uses one uniform 1/3 scale, never a forced aspect ratio.
        canvas.paste(image.resize((420, 912), Image.Resampling.LANCZOS), (x, y))
        for index, both in enumerate(boxes, start=1):
            left, top, right, bottom = both[side]
            draw.rounded_rectangle((x + left, y + top, x + right, y + bottom),
                                   radius=8, outline='#a75530', width=2)
            draw.ellipse((x + left + 4, y + top + 4, x + left + 27, y + top + 27), fill='#a75530')
            draw.text((x + left + 10, y + top + 5), str(index), font=ui._font(13), fill='white')
    notes = [
        '1. 主卡去猫，标题统一 15 / w450 / 灰色，和小卡左边缘对齐。',
        '2. 四张独立小卡：紧凑比例、无金额符号、真实 w800 数字。',
        '历史不足不补造曲线；来源和口径断点保留，菜单共享时间范围。',
        '真实 Flutter Widget 离屏图，非模拟器或真机；原 PNG 未修改。',
    ]
    for row, text in enumerate(notes):
        draw.text((16, 997 + row * 29), text, font=ui._font(14), fill='#555555')
    target = OUT / f'{number:02d}_{theme}_before_after.png'
    canvas.save(target, optimize=True)
    if hashes != [hashlib.sha256(path.read_bytes()).hexdigest() for path in paths]:
        raise ValueError('Source capture changed during annotation')
    return target, {'theme': theme, 'source_sha256': hashes,
                    'original_size': [1260, 2736], 'comparison': target.name}


def main():
    results = [pair(index, theme) for index, theme in enumerate(('warm', 'night'), start=1)]
    contact = Image.new('RGB', (888, 1130), '#f7f7f8')
    for index, (path, _) in enumerate(results):
        image = Image.open(path).convert('RGB')
        image.thumbnail((444, 565), Image.Resampling.LANCZOS)
        contact.paste(image, (index * 444, 0))
    draw = ImageDraw.Draw(contact)
    for index, name in enumerate(('dashboard-394-1.png', 'dashboard-320-1.png',
                                  'dashboard-394-2.png', 'dashboard-320-2.png')):
        image = Image.open(OUT / name).convert('RGB')
        image.thumbnail((190, 480), Image.Resampling.LANCZOS)
        x = index * 222 + 12
        draw.text((x, 578), ('常规', '窄屏', '大字', '窄屏大字')[index],
                  font=ui._font(16), fill='#202124')
        contact.paste(image, (x, 610))
    draw.text((16, 1103), '下方为有两条历史快照的组件测试场景，非用户数据。', font=ui._font(14), fill='#555555')
    contact.save(OUT / '00_asset_overview_contact.png', optimize=True)
    (OUT / 'comparison_manifest.json').write_text(json.dumps({
        'capture_kind': 'Flutter Widget offscreen',
        'device_verified': False,
        'pairs': [item for _, item in results],
    }, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Generated 2 numbered pairs and contact sheet in {OUT}')


if __name__ == '__main__':
    main()
