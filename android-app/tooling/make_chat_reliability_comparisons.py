"""Prepare the fixed old chat UI and pair real cold-restored Widget captures."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw

import make_ui_comparisons as ui

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'android-app'
OUT = APP / 'outputs/ui_comparisons/2026-10-04-chat-reliability'
BASELINE = ROOT / '.tmp/chat-ui-baseline'
BASE_REF = 'ca306cb970481c1564deace694b217c060eeca67'
SOURCE = 'android-app/lib/views/home/ai_chat_panel.dart'
TEST = APP / 'test/ai_chat_reliability_visual_test.dart'
AFTER = 'after-verified'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare():
    original = subprocess.check_output(
        ['git', 'show', f'{BASE_REF}:{SOURCE}'], cwd=ROOT,
    ).decode('utf-8')
    transformed = original.replace("'../../", "'package:qingji/")
    transformed = transformed.replace("'../", "'package:qingji/views/")
    transformed = transformed.replace(
        "'chat_add_sheet.dart'", "'package:qingji/views/home/chat_add_sheet.dart'",
    )
    BASELINE.mkdir(parents=True, exist_ok=True)
    (BASELINE / 'ai_chat_panel_before.dart').write_text(transformed, encoding='utf-8')
    fixture = TEST.read_text('utf-8').replace(
        "'package:qingji/views/home/ai_chat_panel.dart'", "'ai_chat_panel_before.dart'",
    ).replace("'screenshot_font_support.dart'",
              "'../../android-app/test/screenshot_font_support.dart'")
    (BASELINE / 'ai_chat_reliability_visual_test.dart').write_text(fixture, encoding='utf-8')
    (BASELINE / 'baseline_metadata.json').write_text(json.dumps({
        'git_ref': BASE_REF, 'original_source': SOURCE,
        'original_sha256': hashlib.sha256(original.encode()).hexdigest(),
        'transforms': ['imports resolved to package URIs'],
        'limitation': 'Old UI with current repository and identical synthetic data; not an old APK.',
    }, indent=2), encoding='utf-8')
    print(f'Baseline fixture prepared at {BASELINE}; production source untouched.')


def pair(index, stem):
    paths = [OUT / phase / f'{stem}.png' for phase in ('before', AFTER)]
    hashes = [sha256(path) for path in paths]
    images = [Image.open(path).convert('RGB') for path in paths]
    width = int(stem.split('-')[1])
    if any(image.size != (width * 3, 912 * 3) for image in images):
        raise ValueError(f'Capture size mismatch: {stem}')
    bounds = json.loads((OUT / AFTER / f'{stem}.json').read_text('utf-8'))
    canvas = Image.new('RGB', (width * 2 + 64, 1205), '#f7f7f8')
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), f'{index:02d} {stem}', font=ui._font(20), fill='#202124')
    draw.text((16, 42), '改前', font=ui._font(15), fill='#555555')
    draw.text((width + 48, 42), '改后', font=ui._font(15), fill='#555555')
    for side, picture in enumerate(images):
        x, y = 16 + side * (width + 32), 70
        canvas.paste(picture.resize((width, 912), Image.Resampling.LANCZOS), (x, y))
        for number, key in enumerate(('thinking', 'interrupted', 'selectors'), 1):
            if key not in bounds:
                continue
            left, top, right, bottom = bounds[key]
            rect = (x + max(0, left - 4), y + top - 3,
                    x + min(width, right + 4), y + bottom + 3)
            draw.rectangle(rect, outline='#a75530', width=2)
            draw.ellipse((rect[0], rect[1], rect[0] + 22, rect[1] + 22), fill='#a75530')
            draw.text((rect[0] + 6, rect[1] + 1), str(number), font=ui._font(13), fill='white')
    notes = [
        '1. 重开后恢复真实摘要和耗时；2. 保留正文/标明中断，不加续写按钮。',
        '3. 模型文字测量计入系统字号，不覆盖思考强度与发送按钮。',
        '正文/操作栏保留；恢复状态新增后自然重排，未人工挪动截图。',
        '320dp/200%已滚到末尾，思考时间在上方，不画视口外的编号1。',
        '同数据/主题/字体/尺寸；旧UI搭配当前仓储fixture，非旧APK。',
        'Flutter离屏渲染，非装机/动效/性能验收；原始图不加标注。',
    ]
    for line, note in enumerate(notes):
        draw.text((16, 1000 + line * 28), note, font=ui._font(12), fill='#555555')
    target = OUT / f'{index:02d}_{stem}_before_after.png'
    canvas.save(target, optimize=True)
    if hashes != [sha256(path) for path in paths]:
        raise ValueError('Original capture modified during composition')
    return target, {'scene': stem, 'before_sha256': hashes[0], 'after_sha256': hashes[1],
                    'comparison': target.name, 'annotations_from_after': bounds}


def compare():
    stems = [f'{theme}-{width}-{scale}x' for theme in ('warm', 'white', 'night')
             for width, scale in ((420, 1), (320, 2))]
    pairs = [pair(index, stem) for index, stem in enumerate(stems, 1)]
    contact = Image.new('RGB', (1320, 1206), '#f7f7f8')
    for index, (path, _) in enumerate(pairs):
        picture = Image.open(path).convert('RGB')
        picture.thumbnail((440, 603), Image.Resampling.LANCZOS)
        contact.paste(picture, ((index % 3) * 440, (index // 3) * 603))
    contact.save(OUT / '00_chat_reliability_contact.png', optimize=True)
    metadata = json.loads((BASELINE / 'baseline_metadata.json').read_text('utf-8'))
    metadata.update({
        'capture_kind': 'Flutter Widget offscreen', 'device_verified': False,
        'pixel_ratio': 3, 'logical_height': 912,
        'fonts': ['Nunito', 'Noto Sans SC', 'MaterialIcons', 'CupertinoIcons'],
        'pairs': [item for _, item in pairs], 'current_source_sha256': sha256(ROOT / SOURCE),
        'visual_test_sha256': sha256(TEST),
    })
    (OUT / 'comparison_manifest.json').write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8',
    )
    print(f'Generated {len(pairs)} comparisons; raw capture hashes unchanged.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare-baseline', action='store_true')
    args = parser.parse_args()
    prepare() if args.prepare_baseline else compare()
