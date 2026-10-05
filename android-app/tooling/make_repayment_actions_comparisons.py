"""Prepare a Git baseline fixture or pair real repayment Widget captures."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw

import make_ui_comparisons as ui

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'android-app'
OUT = APP / 'outputs/ui_comparisons/2026-10-04-repayment-actions'
BASELINE = ROOT / '.tmp/repayment-ui-baseline'
BASE_REF = 'ca306cb970481c1564deace694b217c060eeca67'
SOURCE = 'android-app/lib/widgets/transaction_actions.dart'
TEST = APP / 'test/liability_repayment_actions_visual_test.dart'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare():
    original = subprocess.check_output(
        ['git', 'show', f'{BASE_REF}:{SOURCE}'], cwd=ROOT,
    ).decode('utf-8')
    transformed = original.replace('TransactionSlidable', 'BeforeTransactionSlidable')
    transformed = transformed.replace("'../", "'package:qingji/")
    for name in ('app_toast', 'refund_settlement_sheet', 'slidable_tracker'):
        transformed = transformed.replace(
            f"'{name}.dart'", f"'package:qingji/widgets/{name}.dart'",
        )
    BASELINE.mkdir(parents=True, exist_ok=True)
    (BASELINE / 'transaction_actions_before.dart').write_text(transformed, encoding='utf-8')
    copied_test = TEST.read_text('utf-8').replace(
        "'package:qingji/widgets/transaction_actions.dart'",
        "'transaction_actions_before.dart'",
    ).replace("'screenshot_font_support.dart'", "'../../android-app/test/screenshot_font_support.dart'")
    copied_test = copied_test.replace('TransactionSlidable(', 'BeforeTransactionSlidable(')
    (BASELINE / 'liability_repayment_actions_visual_test.dart').write_text(
        copied_test, encoding='utf-8',
    )
    (BASELINE / 'baseline_metadata.json').write_text(json.dumps({
        'git_ref': BASE_REF,
        'original_source': SOURCE,
        'original_sha256': hashlib.sha256(original.encode()).hexdigest(),
        'transforms': ['public widget renamed', 'imports resolved to package URIs'],
    }, indent=2), encoding='utf-8')
    print(f'Baseline fixture prepared at {BASELINE}; application source untouched.')


def pair(index, stem):
    paths = [OUT / stage / f'{stem}.png' for stage in ('before', 'after')]
    hashes = [sha256(path) for path in paths]
    images = [Image.open(path).convert('RGB') for path in paths]
    width = int(stem.split('-')[1])
    if any(image.size != (width * 3, 2400) for image in images):
        raise ValueError(f'Capture size mismatch: {stem}')
    canvas = Image.new('RGB', (width * 2 + 64, 1010), '#f7f7f8')
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), f'{index:02d} {stem}', font=ui._font(20), fill='#202124')
    draw.text((16, 42), '改前', font=ui._font(15), fill='#555555')
    draw.text((width + 48, 42), '改后', font=ui._font(15), fill='#555555')
    for side, image in enumerate(images):
        x, y = 16 + side * (width + 32), 70
        canvas.paste(image.resize((width, 800), Image.Resampling.LANCZOS), (x, y))
        bounds = json.loads(paths[side].with_suffix('.json').read_text('utf-8'))
        for number, row in enumerate(('1', '2', '10'), 1):
            left, top, right, bottom = bounds[row]
            rect = (x + left, y + top, x + right, y + bottom)
            draw.rectangle(rect, outline='#a75530', width=2)
            draw.ellipse((rect[0], rect[1], rect[0] + 23, rect[1] + 23), fill='#a75530')
            draw.text((rect[0] + 6, rect[1] + 1), str(number), font=ui._font(13), fill='white')
    notes = [
        '1. 本金流水：撤销整次还款，移除普通编辑与删除入口。',
        '2. 利息流水：移除退款入口，与本金共用整次还款撤销。',
        '3. 普通账单保持一致；操作区像素已另行核对。',
        '真实 Widget 离屏渲染；同主题/字体/尺寸，非真机验收。',
    ]
    for line, note in enumerate(notes):
        draw.text((16, 887 + line * 27), note, font=ui._font(13), fill='#555555')
    target = OUT / f'{index:02d}_{stem}_before_after.png'
    canvas.save(target, optimize=True)
    ordinary = []
    for side, image in enumerate(images):
        bounds = json.loads(paths[side].with_suffix('.json').read_text('utf-8'))['10']
        ordinary.append(image.crop(tuple(round(value * 3) for value in bounds)).tobytes())
    if ordinary[0] != ordinary[1]:
        raise ValueError(f'Ordinary transaction differs from baseline: {stem}')
    if hashes != [sha256(path) for path in paths]:
        raise ValueError('Original capture changed during composition')
    return target, {'scene': stem, 'before_sha256': hashes[0],
                    'after_sha256': hashes[1], 'ordinary_pixels_identical': True,
                    'comparison': target.name}


def compare():
    stems = [f'{theme}-{width}-{scale}x-{phase}'
             for theme in ('warm', 'white', 'night')
             for width, scale in ((420, 1), (320, 2))
             for phase in ('actions', 'confirm')]
    pairs = [pair(index, stem) for index, stem in enumerate(stems, 1)]
    contact = Image.new('RGB', (1320, 2040), '#f7f7f8')
    for index, (path, _) in enumerate(pairs):
        image = Image.open(path).convert('RGB')
        image.thumbnail((440, 510), Image.Resampling.LANCZOS)
        contact.paste(image, ((index % 3) * 440, (index // 3) * 510))
    contact.save(OUT / '00_repayment_actions_contact.png', optimize=True)
    metadata = json.loads((BASELINE / 'baseline_metadata.json').read_text('utf-8'))
    metadata.update({
        'capture_kind': 'Flutter Widget offscreen', 'device_verified': False,
        'pixel_ratio': 3, 'logical_height': 800, 'fonts': ['Nunito', 'Noto Sans SC',
            'MaterialIcons', 'CupertinoIcons'], 'pairs': [item for _, item in pairs],
        'current_source_sha256': sha256(ROOT / SOURCE),
        'visual_test_sha256': sha256(TEST),
    })
    (OUT / 'comparison_manifest.json').write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8',
    )
    print(f'Generated {len(pairs)} comparisons; ordinary row pixels identical in all pairs.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare-baseline', action='store_true')
    args = parser.parse_args()
    prepare() if args.prepare_baseline else compare()
