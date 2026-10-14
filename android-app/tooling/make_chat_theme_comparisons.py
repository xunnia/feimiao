"""Compose retained real Widget captures; never modify the original images."""

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

from make_ui_comparisons import _font

OUT = Path(__file__).resolve().parents[1] / 'outputs/ui_comparisons/2026-10-04-chat-theme'
SCENES = [
    ('empty-warm', '暖橙·空聊天', '1. 去掉底部反向染黄；输入框上下沿用完整主题渐变。', 700, 980),
    ('empty-pink', '樱粉·空聊天', '1. 粉色主题同样保持连续，不在输入框附近补一层顶色。', 700, 980),
    ('empty-white', '简约白·空聊天', '1. 纯色背景保持一致；输入框样式和操作不变。', 700, 980),
    ('empty-night', '暮夜·空聊天', '1. 去掉底部额外提亮；深色输入框保持原有材质。', 700, 980),
    ('keyboard-warm', '暖橙·键盘留位', '1. 键盘留位320dp时，输入框上移不重新染色；非系统键盘截图。', 410, 660),
    ('attachments-warm', '暖橙·三图与文字草稿', '1. 输入框增高后背景仍连续；三图和补充文字保留。', 590, 980),
    ('large-text-warm', '暖橙·320dp/200%字', '1. 窄屏大字取色一致；输入区留距随实际高度变化。', 700, 980),
    ('conversation-warm', '暖橙·SQLite真实会话', '1. 只让消息渐隐，不涂改其下的主题背景；内容与操作不变。', 700, 980),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    pairs = []
    for index, (name, title, note, top, bottom) in enumerate(SCENES, 1):
        paths = [OUT / phase / f'{name}.png' for phase in ('before', 'after')]
        hashes = [digest(path) for path in paths]
        pictures = [Image.open(path).convert('RGB') for path in paths]
        metadata = [json.loads(path.with_suffix('.json').read_text('utf-8')) for path in paths]
        if pictures[0].size != pictures[1].size or metadata[0]['logical_size'] != metadata[1]['logical_size']:
            raise ValueError(f'Scene dimensions differ: {name}')
        for path in ('lib/views/home/ai_chat_panel.dart', 'lib/widgets/glass_input.dart'):
            if metadata[0]['source_sha256'][path] != metadata[1]['source_sha256'][path]:
                raise ValueError(f'Unrelated UI source changed: {path}')
        for path in ('lib/views/home/chat_reading_viewport.dart',
                     'lib/views/home/ai_chat_panel.dart', 'lib/widgets/glass_input.dart'):
            if digest(OUT.parents[2] / path) != metadata[1]['source_sha256'][path]:
                raise ValueError(f'Capture does not match current production source: {path}')
        width = int(metadata[0]['logical_size'][0])
        canvas = Image.new('RGB', (width * 2 + 48, 1172), '#f7f7f8')
        draw = ImageDraw.Draw(canvas)
        draw.text((12, 8), f'{index:02d} {title}', font=_font(18), fill='#202124')
        for side, picture in enumerate(pictures):
            x, y = 12 + side * (width + 24), 64
            draw.text((x, 36), '改前' if side == 0 else '改后', font=_font(14), fill='#555555')
            canvas.paste(picture.resize((width, 1000), Image.Resampling.LANCZOS), (x, y))
            rect = (x + 2, y + top, x + width - 2, y + bottom)
            draw.rectangle(rect, outline='#a75530', width=2)
            draw.ellipse((rect[0], rect[1], rect[0] + 22, rect[1] + 22), fill='#a75530')
            draw.text((rect[0] + 7, rect[1] + 1), '1', font=_font(13), fill='white')
        draw.text((12, 1078), note, font=_font(12), fill='#555555')
        draw.text((12, 1105), '实际Flutter页面离屏渲染，非装机；同数据/主题/尺寸/字体。', font=_font(12), fill='#555555')
        draw.text((12, 1132), '标注只加在拼图；原图与源码指纹保留。键盘图仅模拟系统留位。', font=_font(12), fill='#555555')
        target = OUT / f'{index:02d}_{name}_before_after.png'
        canvas.save(target, optimize=True)
        if hashes != [digest(path) for path in paths]:
            raise ValueError('An original capture was changed')
        pairs.append({
            'scene': name,
            'comparison': target.name,
            'before_sha256': hashes[0],
            'after_sha256': hashes[1],
            'before_source_sha256': metadata[0]['source_sha256'],
            'after_source_sha256': metadata[1]['source_sha256'],
        })
    contact = Image.new('RGB', (1440, 1758), '#f7f7f8')
    for index, pair in enumerate(pairs):
        picture = Image.open(OUT / pair['comparison'])
        picture.thumbnail((480, 586), Image.Resampling.LANCZOS)
        contact.paste(picture, ((index % 3) * 480, (index // 3) * 586))
    contact.save(OUT / '00_chat_theme_contact.png', optimize=True)
    (OUT / 'comparison_manifest.json').write_text(json.dumps({
        'kind': 'Flutter Widget offscreen; not an installed app',
        'device_verified': False,
        'pairs': pairs,
    }, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'{len(pairs)} comparisons; original image hashes unchanged.')


if __name__ == '__main__':
    main()
