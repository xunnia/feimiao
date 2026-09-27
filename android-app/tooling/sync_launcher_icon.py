"""Synchronize an approved square source image to existing Android icon slots."""
import argparse
import hashlib
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = args.source.resolve()
    target = root / 'assets/icon/app_icon.png'
    evidence = args.evidence.resolve()
    if evidence.exists():
        raise ValueError('Use a new evidence directory to preserve earlier originals')
    with Image.open(source) as image:
        image.load()
        if image.width != image.height or image.width < 512:
            raise ValueError('Source must be square and at least 512px')
        approved = image.convert('RGBA')
    res = root / 'android/app/src/main/res'
    paths = sorted(set(res.glob('mipmap-*/ic_launcher*.png')) |
                   set(res.glob('drawable-*/ic_launcher_foreground.png')))
    if len(paths) != 15:
        raise ValueError(f'Expected 15 existing density assets, found {len(paths)}')
    slots = []
    for path in paths:
        with Image.open(path) as image:
            slots.append((path, image.size))
    evidence.mkdir(parents=True)
    with Image.open(target) as image:
        before = image.convert('RGBA')
    for path in [target, *paths]:
        backup = evidence / 'before' / path.relative_to(root)
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, backup)
    shutil.copyfile(source, target)
    for path, size in slots:
        approved.resize(size, Image.Resampling.LANCZOS).save(path)
        with Image.open(path) as actual:
            assert actual.size == size
            assert actual.convert('RGBA').tobytes() == approved.resize(size, Image.Resampling.LANCZOS).tobytes()
    assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(target.read_bytes()).digest()
    canvas = Image.new('RGB', (960, 410), '#f4f5f7')
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 19)
    labels = ['1 修改前', '1 修改后（原图）', '圆形遮罩预览', '圆角遮罩预览']
    for index, image in enumerate([before, approved, approved, approved]):
        tile = image.resize((210, 210), Image.Resampling.LANCZOS)
        mask = Image.new('L', (210, 210), 255)
        if index >= 2:
            mask = Image.new('L', (210, 210), 0)
            painter = ImageDraw.Draw(mask)
            if index == 2:
                painter.ellipse((0, 0, 209, 209), fill=255)
            else:
                painter.rounded_rectangle((0, 0, 209, 209), radius=46, fill=255)
        x = 15 + index * 240
        canvas.paste(tile, (x, 65), mask)
        draw.text((x, 20), labels[index], font=font, fill='#242424')
    draw.text((15, 310), '1 桌面图标替换；原图不重绘、不预加圆角。', font=font, fill='#242424')
    draw.text((15, 345), '遮罩为静态预览，不代表已通过手机桌面安装验收。', font=font, fill='#555555')
    canvas.save(evidence / 'launcher_before_after.png')
    print(f'Synchronized {len(slots)} assets; source SHA256={hashlib.sha256(target.read_bytes()).hexdigest()}')
    print(evidence / 'launcher_before_after.png')


if __name__ == '__main__':
    main()
