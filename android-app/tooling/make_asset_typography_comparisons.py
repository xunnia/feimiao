"""Compare preserved Flutter captures and measure unscaled reference text."""

import hashlib
import json
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import make_ui_comparisons as ui


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'android-app/outputs/ui_comparisons/2026-10-03-asset-typography'
BASELINE = ROOT / 'android-app/outputs/ui_comparisons/2026-10-03-asset-overview'
REFERENCES = Path(
    'C:/Users/寻逆啊/Documents/Tencent Files/948095682/nt_qq/nt_data/Pic/2026-10/Ori'
)
THEMES = [('warm', '暖色'), ('white', '简约白'), ('night', '深色')]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def preserve_page_baselines():
    for theme in ('warm', 'night'):
        source = BASELINE / f'page-{theme}-after.png'
        target = OUT / f'page-{theme}-before.png'
        if not target.exists():
            target.write_bytes(source.read_bytes())


def pair(number, stem, title, page=False):
    paths = [OUT / f'{stem}-{stage}.png' for stage in ('before', 'after')]
    original_hashes = [sha256(path) for path in paths]
    images = [Image.open(path).convert('RGB') for path in paths]
    if any(image.size != (1260, 2736) for image in images):
        raise ValueError('Expected 420 x 912 logical pixels captured at 3x')
    canvas = Image.new('RGB', (888, 1156), '#f7f7f8')
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), f'{number:02d} {title}', font=ui._font(21), fill='#202124')
    draw.text((16, 42), '修改前：v325 源码离屏基线', font=ui._font(14), fill='#555555')
    draw.text((452, 42), '修改后：本地字体校准', font=ui._font(14), fill='#555555')
    # The numbered regions follow the actual content after the smaller labels
    # reflow. They do not replace or annotate the source captures themselves.
    regions = (
        [[(30, 129, 388, 220), (30, 129, 388, 220)],
         [(20, 386, 400, 623), (20, 389, 400, 626)]] if page else
        [[(30, 26, 388, 143), (30, 26, 388, 141)],
         [(16, 439 if 'partial' in stem else 396, 404,
           678 if 'partial' in stem else 635),
          (16, 442 if 'partial' in stem else 399, 404,
           681 if 'partial' in stem else 638)]]
    )
    for side, image in enumerate(images):
        x, y = 16 + side * 436, 70
        canvas.paste(image.resize((420, 912), Image.Resampling.LANCZOS), (x, y))
        for index, both in enumerate(regions, start=1):
            left, top, right, bottom = both[side]
            draw.rounded_rectangle((x + left, y + top, x + right, y + bottom),
                                   radius=6, outline='#a75530', width=2)
            draw.ellipse((x + left - 28, y + top + 4, x + left - 5, y + top + 27),
                         fill='#a75530')
            draw.text((x + left - 22, y + top + 5), str(index),
                      font=ui._font(13), fill='white')
    notes = [
        '1. 主金额 38→41.75 / 真 w800；标题 15/w450→12.5/w400、参考灰。',
        '2. 小金额 28→22.5 / w800；数字 1 去底脚；主小卡内距统一 16。',
        '负值保留橙色并加深；百分比保留灰色，不搬参考红绿。',
        '图表、历史质量提示及下半页旧组件保持；不是整页重设计。',
        'Flutter 离屏截图，非模拟器/真机；仅此对比图等比缩略，原图未改。',
    ]
    for row, text in enumerate(notes):
        draw.text((16, 997 + row * 29), text, font=ui._font(14), fill='#555555')
    target = OUT / f'{number:02d}_{stem}_before_after.png'
    canvas.save(target, optimize=True)
    if original_hashes != [sha256(path) for path in paths]:
        raise ValueError('Source capture changed during comparison')
    return target, {
        'title': title, 'original_size': list(images[0].size),
        'before': paths[0].name, 'after': paths[1].name,
        'source_sha256': original_hashes, 'comparison': target.name,
    }


def ink(crop, threshold):
    pixels = np.asarray(crop.convert('RGB'))
    mask = pixels.mean(axis=2) < threshold
    y, x = np.nonzero(mask)
    if not len(x):
        raise ValueError('Text ROI is empty')
    bounds = (int(x.min()), int(y.min()), int(x.max()) + 1, int(y.max()) + 1)
    colors = Counter(map(tuple, pixels[mask].tolist()))
    return crop.crop(bounds), mask[bounds[1]:bounds[3], bounds[0]:bounds[2]], {
        'bounds': list(bounds), 'width': bounds[2] - bounds[0],
        'height': bounds[3] - bounds[1], 'ink_pixels': int(mask.sum()),
        'most_common_foreground': list(colors.most_common(1)[0][0]),
    }


def font_comparison():
    candidate_path = OUT / 'font-candidates.png'
    candidate = Image.open(candidate_path).convert('RGB')
    bounds = json.loads((OUT / 'font-candidate-bounds.json').read_text('utf-8'))
    samples = [
        ('标题：带宽', '2954704ffb2359a3d4bd4abc3c8673cc.png',
         (90, 810, 360, 880), 'label-12.5', 175),
        ('小数字：13.4 MB', '2954704ffb2359a3d4bd4abc3c8673cc.png',
         (90, 880, 440, 960), 'metric-22.5', 90),
        ('主数字：10,369', '2404fc9d4c1e38ead02c944c36e96ec1.png',
         (90, 1250, 610, 1385), 'hero-41.75', 90),
    ]
    canvas = Image.new('RGB', (1390, 735), 'white')
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), '原像素同文字校准：不缩放、不拉伸字形',
              font=ui._font(23), fill='#202124')
    draw.text((16, 48), '橙云原图（Apple 系统字体）', font=ui._font(16), fill='#555555')
    draw.text((478, 48), 'Android 候选（已随包字体）', font=ui._font(16), fill='#555555')
    draw.text((940, 48), '叠加：参考洋红 / 候选青色', font=ui._font(16), fill='#555555')
    metrics = []
    protected = {candidate_path: sha256(candidate_path)}
    for index, (label, file, roi, key, threshold) in enumerate(samples):
        reference_path = REFERENCES / file
        protected[reference_path] = sha256(reference_path)
        reference = Image.open(reference_path).convert('RGB')
        current_roi = tuple(round(value) for value in bounds[key])
        crops = [reference.crop(roi), candidate.crop(current_roi)]
        items = [ink(crop, threshold) for crop in crops]
        top = 95 + index * 194
        draw.text((16, top), label, font=ui._font(17), fill='#202124')
        for column, (crop, _, metric) in enumerate(items):
            canvas.paste(crop, (16 + column * 462, top + 33))
            draw.text((16 + column * 462, top + 146),
                      f"墨迹 {metric['width']}×{metric['height']} px",
                      font=ui._font(15), fill='#555555')
        masks = [item[1] for item in items]
        overlay = np.full((118, 434, 3), 255, dtype=np.uint8)
        for color, mask in zip(([212, 40, 140], [0, 155, 182]), masks):
            h, w = mask.shape
            if h > 118 or w > 434:
                raise ValueError('Overlay slot is smaller than the unscaled ink')
            area = overlay[:h, :w]
            area[mask] = ((area[mask].astype(int) + color) // 2).astype(np.uint8)
        canvas.paste(Image.fromarray(overlay), (940, top + 33))
        metrics.append({'text': label, 'reference_file': file,
                        'reference_roi': list(roi), 'candidate_key': key,
                        'candidate_roi': list(current_roi),
                        'reference': items[0][2], 'candidate': items[1][2]})
    draw.text((16, 694), '样本按左上墨迹对齐，仅检验字形/笔画；不证明原参考逻辑尺寸或真机渲染相同。',
              font=ui._font(16), fill='#555555')
    canvas.save(OUT / '09_reference_font_overlay.png', optimize=True)
    if any(sha256(path) != value for path, value in protected.items()):
        raise ValueError('Reference or candidate source image changed')
    return metrics, {str(path): value for path, value in protected.items()}


def main():
    preserve_page_baselines()
    pairs = []
    for theme, label in THEMES:
        for scenario, name in [('complete', '完整历史'), ('partial', '缺口与负值')]:
            pairs.append(pair(len(pairs) + 1, f'dashboard-{theme}-{scenario}',
                              f'{label} · {name}'))
    for theme, label in [('warm', '暖色'), ('night', '深色')]:
        pairs.append(pair(len(pairs) + 1, f'page-{theme}',
                          f'{label} · 总览整页 fixture', page=True))
    contact = Image.new('RGB', (1776, 1156), '#f7f7f8')
    for index, (path, _) in enumerate(pairs):
        image = Image.open(path).convert('RGB')
        image.thumbnail((444, 578), Image.Resampling.LANCZOS)
        contact.paste(image, ((index % 4) * 444, (index // 4) * 578))
    contact.save(OUT / '00_asset_typography_contact.png', optimize=True)
    metrics, hashes = font_comparison()
    manifest = {
        'capture_kind': 'Flutter Widget offscreen', 'device_verified': False,
        'baseline_commit': '546794c', 'logic_size': [420, 912], 'pixel_ratio': 3,
        'reference_logic_size_confirmed': False,
        'source_font_confirmed': 'Apple system default labels and rounded bold numerals',
        'source_repository': 'https://github.com/chen2he/orange-cloud',
        'source_commit': '6ac763d357b2cabb86bffe24c1770a333462af95',
        'reference_copy_of_code_or_fonts': False,
        'pairs': [item for _, item in pairs], 'font_metrics': metrics,
        'protected_source_sha256': hashes,
    }
    (OUT / 'comparison_manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Generated {len(pairs)} numbered pairs, contact sheet and font overlay in {OUT}')
    for item in metrics:
        print(json.dumps(item, ensure_ascii=False))


if __name__ == '__main__':
    main()
