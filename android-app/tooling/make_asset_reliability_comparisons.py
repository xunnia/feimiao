"""Numbered comparisons of preserved asset-overview Flutter captures."""

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

import make_ui_comparisons as ui


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'android-app/outputs/ui_comparisons/2026-10-03-asset-reliability'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pair(number, stem, title, page=False):
    names = [f'{stem}-{stage}.png' if page else f'{stem}.png'
             for stage in ('before', 'after')]
    paths = [OUT / stage / name for stage, name in zip(('before', 'after'), names)]
    hashes = [sha256(path) for path in paths]
    images = [Image.open(path).convert('RGB') for path in paths]
    if any(image.size != (1260, 2736) for image in images):
        raise ValueError('Expected 420x912 logical pixels at 3x')
    canvas = Image.new('RGB', (888, 1140), '#f7f7f8')
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), f'{number:02d} {title}', font=ui._font(21), fill='#202124')
    draw.text((16, 42), '改前：字体校准后，可靠性修复前', font=ui._font(14), fill='#555555')
    draw.text((452, 42), '改后：本地资产总览候选', font=ui._font(14), fill='#555555')
    for side, image in enumerate(images):
        x, y = 16 + side * 436, 70
        canvas.paste(image.resize((420, 912), Image.Resampling.LANCZOS), (x, y))
        if page:
            rects = [(20, 119, 400, 367), (20, 367, 400, 594)]
            if side:
                rects = [(20, 119, 400, 331), (20, 331, 400, 558)]
        else:
            bounds = json.loads((OUT / ('before' if side == 0 else 'after') /
                                 f'{stem}.json').read_text('utf-8'))
            first = bounds['asset-net-worth-card']
            funds, debt = bounds['asset-metric-funds'], bounds['asset-metric-liabilities']
            rects = [first, [funds[0], funds[1], debt[2], debt[3]]]
        for index, (left, top, right, bottom) in enumerate(rects, 1):
            draw.rounded_rectangle((x + left, y + top, x + right, y + bottom),
                                   radius=6, outline='#a75530', width=2)
            draw.ellipse((x + left, y + top, x + left + 23, y + top + 23), fill='#a75530')
            draw.text((x + left + 6, y + top + 1), str(index), font=ui._font(13), fill='white')
    notes = [
        '1. 合并重复说明；变化金额与区间同一行，详细口径从右上信息图标进入。',
        '2. 字体、四小卡保持；缺估值不跨点连线、不再将补齐资料显示为涨幅。',
        '短历史日期去重；负向变化按有符号金额取整；图表读屏补首末日期/金额。',
        'Flutter离屏/测试数据，非模拟器或真机；原图未改，对比图仅等比缩略。',
    ]
    for row, note in enumerate(notes):
        draw.text((16, 997 + row * 29), note, font=ui._font(14), fill='#555555')
    target = OUT / f'{number:02d}_{stem}_before_after.png'
    canvas.save(target, optimize=True)
    if hashes != [sha256(path) for path in paths]:
        raise ValueError('Original capture changed during composition')
    return target, {'title': title, 'before': str(paths[0].relative_to(OUT)),
                    'after': str(paths[1].relative_to(OUT)), 'sha256': hashes,
                    'comparison': target.name}


def main():
    scenes = [('warm-complete', '暖色 · 完整历史'), ('warm-partial', '暖色 · 缺估值历史'),
              ('white-complete', '简约白 · 完整历史'), ('white-partial', '简约白 · 缺估值历史'),
              ('night-complete', '深色 · 完整历史'), ('night-partial', '深色 · 缺估值历史'),
              ('short-history', '一天历史 · 日期刻度'), ('negative-floor', '负数变化 · 向下取整')]
    pairs = [pair(i, stem, title) for i, (stem, title) in enumerate(scenes, 1)]
    pairs += [pair(9, 'page-warm', '暖色 · 总览完整页面', True),
              pair(10, 'page-night', '深色 · 总览完整页面', True)]
    contact = Image.new('RGB', (1776, 1710), '#f7f7f8')
    for i, (path, _) in enumerate(pairs):
        image = Image.open(path).convert('RGB')
        image.thumbnail((444, 570), Image.Resampling.LANCZOS)
        contact.paste(image, ((i % 4) * 444, (i // 4) * 570))
    contact.save(OUT / '00_asset_reliability_contact.png', optimize=True)
    manifest = {
        'capture_kind': 'Flutter Widget offscreen', 'device_verified': False,
        'baseline': '546794c with prior local typography calibration reapplied in isolated copy',
        'baseline_source': '.tmp/asset-overview-review-20261003/baseline-source/android-app',
        'invalid_baseline_excluded': 'before-unloaded-fonts',
        'logic_size': [420, 912], 'pixel_ratio': 3,
        'capture_time': '2026-10-03T12:00:00+08:00',
        'pairs': [item for _, item in pairs],
    }
    (OUT / 'comparison_manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Generated {len(pairs)} pairs and contact sheet in {OUT}')

    for theme, label in [('warm', '暖色'), ('white', '简约白'), ('night', '深色')]:
        source = OUT / 'after' / f'{theme}-explanation.png'
        if not source.exists():
            continue
        image = Image.open(source).convert('RGB')
        canvas = Image.new('RGB', (452, 1015), '#f7f7f8')
        draw = ImageDraw.Draw(canvas)
        draw.text((16, 10), f'{label} · 新增估算说明入口', font=ui._font(19), fill='#202124')
        canvas.paste(image.resize((420, 912), Image.Resampling.LANCZOS), (16, 46))
        draw.text((16, 970), '真实Widget离屏图；改前无此说明弹层。', font=ui._font(14), fill='#555555')
        canvas.save(OUT / f'explanation-{theme}.png', optimize=True)


if __name__ == '__main__':
    main()
