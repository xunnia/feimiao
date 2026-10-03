"""Compare real Flutter popup captures; never recolor or replace source pixels."""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

import make_ui_comparisons as ui


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'android-app/outputs/ui_comparisons/2026-10-02-themed-popups/verified'
THEMES = {'warm': '暖橙', 'white': '简约白', 'pink': '樱粉',
          'mint': '薄荷', 'blue': '雾蓝', 'night': '暮夜'}
KINDS = {'confirm': '确认', 'form': '改名表单', 'menu': '选项菜单',
         'budget': '预算规则', 'model': '模型列表', 'effort': '思考强度',
         'add': '添加到聊天', 'date': '日期', 'month': '首页月份',
         'account': '账号表单外壳', 'profile': '编辑资料', 'about': '关于',
         'terms': '使用条款', 'privacy': '隐私政策'}


def pair(theme, kind, narrow=False):
    stem = f'{theme}_{kind}' + ('_narrow' if narrow else '')
    width, height = (320, 640) if narrow else (420, 912)
    originals = [Image.open(OUT / f'{stem}_{stage}.png').convert('RGB')
                 for stage in ('before', 'after')]
    if any(im.size != (width * 3, height * 3) for im in originals):
        raise ValueError(f'Unexpected capture dimensions: {theme}_{kind}')
    changed = ImageChops.difference(*originals).getbbox() is not None
    images = [im.resize((width, height)) for im in originals]
    canvas = Image.new('RGB', (width * 2 + 48, height + 198), '#f7f7f8')
    draw = ImageDraw.Draw(canvas)
    label = f'{THEMES[theme]} · {KINDS[kind]}' + (' · 窄屏/两倍字号' if narrow else '')
    draw.text((16, 12), label, font=ui._font(21), fill='#202124')
    draw.text((16, 45), '修改前 v324', font=ui._font(14), fill='#666666')
    draw.text((width + 32, 45), '本批修改后' if changed else '保持一致',
              font=ui._font(14), fill='#666666')
    for x, image in zip((16, width + 32), images):
        canvas.paste(image, (x, 73))
        # One frame marks the common visible surface changes, not a fabricated UI.
        draw.rounded_rectangle((x + 5, 73 + 35, x + width - 5, 73 + height - 16), radius=8,
                               outline='#cb6f43', width=2)
        draw.ellipse((x + 10, 73 + 40, x + 32, 73 + 62), fill='#cb6f43')
        draw.text((x + 16, 73 + 42), '1', font=ui._font(13), fill='white')
    notes = [
        ('1. 浮层与填充跟随主题；白主题仍白，深色不再出现亮白/蓝白格。' if changed
         else '1. 保持一致：此场景原有取色已符合主题，没有可见变化。'),
        '布局不变，只统一取色；近似无变化的场景仍保留对照。',
        f'真实 Widget 离屏图，非真机；原始图 {width * 3}×{height * 3}，未修改。',
    ]
    for row, note in enumerate(notes):
        draw.text((16, height + 90 + row * 28), note, font=ui._font(13), fill='#555555')
    target = OUT / f'{stem}_before_after.png'
    canvas.save(target, optimize=True)
    return target


def overview(kind, pairs):
    tiles = []
    for theme, path in pairs:
        tile = Image.open(path).convert('RGB')
        tile.thumbnail((592, 740))
        tiles.append(tile)
    result = Image.new('RGB', (592 * 3, 740 * 2), '#f7f7f8')
    for index, tile in enumerate(tiles):
        result.paste(tile, ((index % 3) * 592, (index // 3) * 740))
    target = OUT / f'overview_{kind}.png'
    result.save(target, optimize=True)
    return target


def main():
    generated = []
    for kind in KINDS:
        pairs = [(theme, pair(theme, kind)) for theme in THEMES]
        generated.append(overview(kind, pairs))
    # Scan all popup families without a full-resolution mosaic.
    contact = Image.new('RGB', (420 * 3, 590 * ((len(KINDS) + 2) // 3)), '#f7f7f8')
    draw = ImageDraw.Draw(contact)
    for index, kind in enumerate(KINDS):
        image = Image.open(OUT / f'pink_{kind}_after.png').convert('RGB')
        image.thumbnail((250, 542))
        x, y = (index % 3) * 420, (index // 3) * 590
        draw.text((x + 12, y + 8), KINDS[kind], font=ui._font(18), fill='#202124')
        contact.paste(image, (x + 85, y + 38))
    target = OUT / '00_popup_families.png'
    contact.save(target, optimize=True)
    for kind in ('confirm', 'form'):
        for theme in THEMES:
            pair(theme, kind, narrow=True)
    print(f'Created {len(THEMES) * (len(KINDS) + 2)} annotated pairs and {len(generated) + 1} overviews in {OUT}')


if __name__ == '__main__':
    main()
