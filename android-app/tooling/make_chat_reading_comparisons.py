"""Pair unchanged original captures, with annotations only on composed copies."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw
import make_ui_comparisons as ui

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'android-app'
OUT = APP / 'outputs/ui_comparisons/2026-10-04-chat-reading'
BASE = ROOT / '.tmp/chat-ui-baseline'
SCENES = [
    ('reading-warm', '1. 标题/强调、悬挂列表、引用、横滑表格和可复制代码。', (12, 12, 408, 520)),
    ('reading-night', '1. 同一正文阅读层级，深色主题。', (12, 12, 408, 520)),
    ('thinking-warm', '1. 思考时间、真实摘要、分隔线使用主题灰阶。', (12, 115, 408, 210)),
    ('thinking-night', '1. 同一思考详情，深色主题。', (12, 115, 408, 210)),
    ('conversation-420-1x', '1. 消息延伸到上下 chrome 后，留距跟随输入框高度。', (8, 320, 412, 905)),
    ('conversation-320-2x', '1. 窄屏200%操作栏和来源分行，顶部柔和过渡。', (8, 10, 312, 905)),
    ('three-images', '1. 三张图片和文字排版保持一致；新增点击预览见末组。', (12, 416, 408, 610)),
    ('sources-warm', '1. 来源面板取主题底色，可拖至半屏/全屏停靠。', (8, 455, 412, 905)),
    ('sources-night', '1. 来源面板深色取色；页面链接仍可点击。', (8, 455, 412, 905)),
    ('menu-warm', '1. 长按菜单主题底色；真实时间和三项操作保留。', (150, 145, 412, 435)),
    ('menu-night', '1. 长按菜单深色主题；原操作和镂空灰幕保留。', (150, 145, 412, 435)),
    ('image-preview', '1. 同一点击：原来停在缩略图，现在打开可缩放预览。', (8, 80, 412, 905)),
]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def prepare():
    # The five popup scenes use the retained, authentic pre-batch widget code.
    test = (APP / 'test/ai_chat_reading_popups_test.dart').read_text('utf-8')
    test = test.replace("'package:qingji/views/home/ai_chat_panel.dart'", "'ai_chat_panel_before.dart'")
    test = test.replace("'screenshot_font_support.dart'", "'../../android-app/test/screenshot_font_support.dart'")
    if not (BASE / 'ai_chat_panel_before.dart').is_file():
        raise FileNotFoundError('Retained ca306cb source fixture is required')
    (BASE / 'ai_chat_reading_popups_test.dart').write_text(test, encoding='utf-8')
    print('Generated pre-batch popup fixture; production files unchanged.')

def compare():
    pairs = []
    for index, (name, note, box) in enumerate(SCENES, 1):
        paths = [OUT / phase / f'{name}.png' for phase in ('before', 'after')]
        hashes = [digest(path) for path in paths]
        originals = [Image.open(path).convert('RGB') for path in paths]
        if originals[0].size != originals[1].size:
            raise ValueError(f'Capture dimensions differ: {name}')
        width = originals[0].width // 3
        canvas = Image.new('RGB', (width * 2 + 48, 1080), '#f7f7f8')
        draw = ImageDraw.Draw(canvas)
        draw.text((12, 8), f'{index:02d} {name}', font=ui._font(18), fill='#202124')
        for side, picture in enumerate(originals):
            x, y = 12 + side * (width + 24), 64
            draw.text((x, 36), '改前' if side == 0 else '改后', font=ui._font(14), fill='#555555')
            canvas.paste(picture.resize((width, 912), Image.Resampling.LANCZOS), (x, y))
            left, top, right, bottom = box
            rect = (x + left, y + top, x + right, y + bottom)
            draw.rectangle(rect, outline='#a75530', width=2)
            draw.ellipse((rect[0], rect[1], rect[0] + 22, rect[1] + 22), fill='#a75530')
            draw.text((rect[0] + 7, rect[1] + 1), '1', font=ui._font(13), fill='white')
        draw.text((12, 991), note, font=ui._font(12), fill='#555555')
        draw.text((12, 1019), '实际Flutter离屏渲染，非装机截图；同数据/主题/尺寸/字体。', font=ui._font(12), fill='#555555')
        draw.text((12, 1045), '弹层改前取保留ca306cb源码；原始图不加标注、不覆盖。', font=ui._font(12), fill='#555555')
        target = OUT / f'{index:02d}_{name}_before_after.png'
        canvas.save(target, optimize=True)
        if hashes != [digest(path) for path in paths]:
            raise ValueError('Composition modified an original capture')
        pairs.append({'scene': name, 'comparison': target.name,
                      'before_sha256': hashes[0], 'after_sha256': hashes[1]})
    contact = Image.new('RGB', (1320, 2160), '#f7f7f8')
    for index, pair in enumerate(pairs):
        image = Image.open(OUT / pair['comparison'])
        image.thumbnail((440, 540), Image.Resampling.LANCZOS)
        contact.paste(image, ((index % 3) * 440, (index // 3) * 540))
    contact.save(OUT / '00_chat_reading_contact.png', optimize=True)
    (OUT / 'comparison_manifest.json').write_text(json.dumps({
        'kind': 'Flutter Widget offscreen', 'device_verified': False,
        'pairs': pairs, 'baseline_popup_ref': 'ca306cb970481c1564deace694b217c060eeca67',
        'source_sha256': {str(path.relative_to(ROOT)): digest(path) for path in
                          (APP / 'lib/views/home').glob('chat_*.dart')},
    }, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'{len(pairs)} comparisons created; all raw capture hashes unchanged.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare-popup-baseline', action='store_true')
    args = parser.parse_args()
    prepare() if args.prepare_popup_baseline else compare()
