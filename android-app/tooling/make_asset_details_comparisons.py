"""Compare preserved, font-complete asset detail captures without altering originals."""

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

import make_ui_comparisons as ui


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'android-app/outputs/ui_comparisons/2026-10-03-asset-details'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pair(number, stem, title):
    paths = [OUT / stage / f'{stem}.png' for stage in ('before-final', 'after-final')]
    hashes = [sha256(path) for path in paths]
    images = [Image.open(path).convert('RGB') for path in paths]
    if any(image.size != (1260, 2736) for image in images):
        raise ValueError(f'{stem}: expected 420x912 logical pixels at 3x')
    unchanged = hashes[0] == hashes[1]
    canvas = Image.new('RGB', (888, 1140), '#f7f7f8')
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), f'{number:02d} {title}', font=ui._font(21), fill='#202124')
    draw.text((16, 42), '改前：旧核对摘要 / 环图', font=ui._font(14), fill='#555555')
    draw.text((452, 42), '改后：资产页本地候选', font=ui._font(14), fill='#555555')
    for side, image in enumerate(images):
        x, y = 16 + side * 436, 70
        canvas.paste(image.resize((420, 912), Image.Resampling.LANCZOS), (x, y))
        bounds = json.loads(paths[side].with_suffix('.json').read_text('utf-8'))
        for index, name in enumerate(('VerifiedNetWorthCard', 'AssetAnalysisCard'), 1):
            if name not in bounds:
                continue
            left, top, right, bottom = bounds[name]
            left, top, right, bottom = max(0, left), max(0, top), min(420, right), min(912, bottom)
            if bottom <= top or right <= left:
                continue
            rect = (x + left, y + top, x + right, y + bottom)
            draw.rounded_rectangle(rect, radius=5, outline='#a75530', width=2)
            draw.ellipse((rect[0], rect[1], rect[0] + 23, rect[1] + 23), fill='#a75530')
            draw.text((rect[0] + 6, rect[1] + 1), str(index), font=ui._font(13), fill='white')
    notes = [
        '1. 上次核对：历史日期、完整/部分状态和统一金额；全部缺口进入详情。',
        '2. 资产结构：去重复圆环/总额，分类金额对齐，真实占比与负债率。',
        '缺金额或口径不一致时保留已覆盖金额，不假造占比；单类别不画冗余图。',
        '真实Flutter离屏图 / 固定测试数据，非模拟器或真机；原图未改。',
    ]
    if unchanged:
        notes[0] = '本场景保持一致；下半页可见变化见同主题滚动到底对比。'
    for row, note in enumerate(notes):
        draw.text((16, 997 + row * 29), note, font=ui._font(14), fill='#555555')
    target = OUT / f'{number:02d}_{stem}_before_after.png'
    canvas.save(target, optimize=True)
    if hashes != [sha256(path) for path in paths]:
        raise ValueError('Original capture changed during composition')
    return target, {'title': title, 'before': str(paths[0].relative_to(OUT)),
                    'after': str(paths[1].relative_to(OUT)), 'sha256': hashes,
                    'unchanged': unchanged, 'comparison': target.name}


def main():
    scenes = [(f'{theme}-{scene}', f'{label} · {state}')
              for theme, label in [('warm', '暖色'), ('white', '简约白'), ('night', '深色')]
              for scene, state in [('complete', '完整'), ('partial', '部分'),
                                   ('single', '单一类别'), ('zero', '零资产 / 有负债')]]
    scenes += [(f'{theme}-page-{position}', f'{label} · 完整页面{state}')
               for theme, label in [('warm', '暖色'), ('night', '深色')]
               for position, state in [('top', '首屏'), ('bottom', '底部')]]
    pairs = [pair(i, stem, title) for i, (stem, title) in enumerate(scenes, 1)]
    contact = Image.new('RGB', (1776, 2280), '#f7f7f8')
    for i, (path, _) in enumerate(pairs):
        image = Image.open(path).convert('RGB')
        image.thumbnail((444, 570), Image.Resampling.LANCZOS)
        contact.paste(image, ((i % 4) * 444, (i // 4) * 570))
    contact.save(OUT / '00_asset_details_contact.png', optimize=True)
    source = ROOT / '.tmp/asset-details-baseline-20261003/android-app/lib/views/assets/asset_overview_cards.dart'
    baseline_hash = sha256(source)
    if baseline_hash != 'dae5b84897eceaf4c8cc45ad8b2badf47aad4107597aeac9d322912d6908e14b':
        raise ValueError('Baseline cards differ from the verified pre-edit source')
    manifest = {
        'capture_kind': 'Flutter Widget offscreen', 'device_verified': False,
        'baseline': '546794c asset_overview_cards with existing typography/reliability changes preserved',
        'baseline_source': str(source.relative_to(ROOT)), 'baseline_cards_sha256': baseline_hash,
        'excluded': ['before-incomplete-fonts', 'after-first-pass', 'before', 'after',
                     'after-pre-localization'],
        'fixed_time': '2026-10-03T12:00:00+08:00', 'logic_size': [420, 912], 'pixel_ratio': 3,
        'pairs': [item for _, item in pairs],
        'after_source_sha256': {str(path.relative_to(ROOT)): sha256(path) for path in [
            ROOT / 'android-app/lib/views/assets/asset_overview_cards.dart',
            ROOT / 'android-app/lib/views/assets/asset_overview_style.dart',
            ROOT / 'android-app/lib/core/assets/asset_structure_projection.dart',
            ROOT / 'android-app/test/asset_overview_details_test.dart',
        ]},
    }
    (OUT / 'comparison_manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Generated {len(pairs)} numbered comparisons; original hashes preserved.')


if __name__ == '__main__':
    main()
