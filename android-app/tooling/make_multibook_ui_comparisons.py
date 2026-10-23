"""Compose genuine multibook Widget screenshots; never change source PNGs."""
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from make_ui_comparisons import _font, _wrap


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/ui_comparisons/2026-10-23-multibook"
VARIANTS = {"light": "浅色", "dark": "深色", "large": "320dp / 200% 字号"}
SCENES = {
    "book-new": ("新建账本", "1. 取消计入总账本开关，说明总账本自动包含全部；创建后可直接添加历史账单。"),
    "book-edit": ("编辑账本", "1. 保留名称备注，加入添加已有账单及管理关联入口；移出关联不删除原始账单。"),
    "entry-edit": ("编辑账单", "1. 原编辑模式无账本入口，现可多选场景账本；200% 字号分类格随文字增高。"),
}
NEW_SCENES = {
    "book-select": "多选场景账本（新增页面，无旧页面）",
    "history-add": "批量添加已有账单（新增页面，无旧页面）",
    "history-remove": "批量移出关联（新增页面，无旧页面）",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compose(index, scene, variant):
    title, note = SCENES[scene]
    phases = ("before-final", "after-final") if scene == "book-new" else ("before-verified", "after")
    sources = [OUT / f"{scene}_{variant}_{phase}.png" for phase in phases]
    hashes = [digest(path) for path in sources]
    images = [Image.open(path).convert("RGB") for path in sources]
    if images[0].size != images[1].size:
        raise ValueError(f"Scene dimensions differ: {scene}/{variant}")
    w, h = images[0].size
    canvas = Image.new("RGB", (2 * w + 96, h + 310), "#f7f7f8")
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 12), f"{index:02d} {title} · {VARIANTS[variant]}", font=_font(30), fill="#202124")
    for side, picture in enumerate(images):
        x = 24 + side * (w + 48)
        draw.text((x, 60), "改前 / HEAD 原始 UI" if side == 0 else "改后 / 当前源码", font=_font(24), fill="#555555")
        canvas.paste(picture, (x, 104))
        # The same region is marked on both sides; raw PNGs remain untouched.
        top = int(h * (0.43 if scene == "entry-edit" else 0.54))
        rect = (x + 12, 104 + top, x + w - 12, 104 + h - 8)
        draw.rectangle(rect, outline="#a75530", width=4)
        draw.ellipse((rect[0], rect[1], rect[0] + 44, rect[1] + 44), fill="#a75530")
        draw.text((rect[0] + 14, rect[1] + 4), "1", font=_font(27), fill="white")
    y = h + 128
    for line in _wrap(draw, note, _font(24), canvas.width - 48):
        draw.text((24, y), line, font=_font(24), fill="#444444")
        y += 34
    draw.text((24, y + 8), "同数据 / AppTheme / 字体 / 尺寸；真实 Flutter Widget 离屏，非装机或真机。", font=_font(22), fill="#666666")
    if variant == "large" and scene == "entry-edit":
        draw.text((24, y + 42), "改前原有 4px 分类格溢出保留；改后不得吞掉布局异常。", font=_font(22), fill="#666666")
    if variant == "large" and scene in ("book-new", "book-edit"):
        draw.text((24, y + 42), "备注窄列在200%字号下仍竖排，属既有缺口，未宣称整页达标。", font=_font(22), fill="#666666")
    target = OUT / f"{index:02d}_{scene}_{variant}_comparison.png"
    canvas.save(target, optimize=True)
    if hashes != [digest(path) for path in sources]:
        raise ValueError("Original screenshots were changed")
    return {"scene": scene, "variant": variant, "comparison": target.name,
            "before": sources[0].name, "after": sources[1].name,
            "before_sha256": hashes[0], "after_sha256": hashes[1], "size": [w, h]}


def main():
    if '--anchored-selection' in sys.argv:
        make_anchored_comparisons()
        return
    if '--filter-toolbar' in sys.argv:
        make_refinement_comparisons(filter_toolbar=True)
        return
    if '--book-picker-dialog' in sys.argv:
        make_refinement_comparisons(book_picker=True)
        return
    if '--refinement' in sys.argv:
        make_refinement_comparisons()
        return
    pairs = []
    for scene in SCENES:
        for variant in VARIANTS:
            pairs.append(compose(len(pairs) + 1, scene, variant))
    contact = Image.new("RGB", (1440, 2000), "#f7f7f8")
    for index, pair in enumerate(pairs):
        image = Image.open(OUT / pair["comparison"])
        image.thumbnail((480, 650), Image.Resampling.LANCZOS)
        contact.paste(image, ((index % 3) * 480, (index // 3) * 650))
    contact.save(OUT / "00_multibook_comparison_contact.png", optimize=True)
    additions = []
    gallery = Image.new("RGB", (1440, 3300), "#f7f7f8")
    for scene, title in NEW_SCENES.items():
        for variant in VARIANTS:
            path = OUT / f"{scene}_{variant}_after.png"
            additions.append({"scene": scene, "title": title, "variant": variant,
                              "after": path.name, "after_sha256": digest(path),
                              "before": None, "reason": "new screen"})
            index = len(additions) - 1
            x, y = (index % 3) * 480, (index // 3) * 1100
            draw = ImageDraw.Draw(gallery)
            draw.text((x + 12, y + 8), f"{scene} / {VARIANTS[variant]}", font=_font(20), fill="#333333")
            picture = Image.open(path)
            picture.thumbnail((460, 1040), Image.Resampling.LANCZOS)
            gallery.paste(picture, (x + 10, y + 48))
    gallery.save(OUT / "00_multibook_new_screens_contact.png", optimize=True)
    (OUT / "comparison_manifest.json").write_text(json.dumps({
        "kind": "Flutter Widget offscreen", "device_verified": False,
        "pairs": pairs, "new_screens": additions,
        "current_sources": {str(path.relative_to(ROOT)): digest(path) for path in [
            ROOT / "lib/views/books/book_sheet.dart",
            ROOT / "lib/views/books/transaction_books_sheet.dart",
            ROOT / "lib/views/home/manual_add_sheet.dart",
            ROOT / "lib/views/quick_add/category_grid.dart",
            ROOT / "test/multibook_ui_test.dart",
        ]},
        "notes": "Original initial/before-verified PNGs retained. Book-new uses before-final/after-final from an isolated project with identical fonts/data, explicit precacheImage and decoded RawImage assertions. Other pairs retain before-verified/after. Existing 200% remark vertical wrapping remains unaccepted."
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{len(pairs)} same-font comparison pairs, {len(additions)} new-screen captures; original hashes unchanged.")


def make_refinement_comparisons(*, book_picker=False, filter_toolbar=False):
    """Compare the shipped sheets against the user's compact-layout revision."""
    previous_candidate = book_picker or filter_toolbar
    directory = ROOT / ('outputs/ui_comparisons/2026-10-23-book-filter-toolbar'
                        if filter_toolbar else
                        'outputs/ui_comparisons/2026-10-23-book-picker-dialog'
                        if book_picker else
                        'outputs/ui_comparisons/2026-10-23-multibook-refinement')
    pairs = []
    scenes = {
        'history-add': ('添加已有账单', '1 顶部移除账本副标题；分段与搜索同行，筛选左对齐＋向下箭头。  2 复用主页按日账单组件，仅增加勾选；删除底部说明。'),
        'history-remove': ('移除账本关联', '1 相同紧凑工具栏。  2 同一公共账单组件与多选状态；移除关联的数据逻辑保持不变。'),
        'book-select': ('选择账本', '1 保留真实账本名称和多选。  2 移除底部重复说明。'),
    }
    if book_picker:
        scenes = {'book-select': ('选择账本 · 小弹窗多选',
                  '1 底部半屏改为居中主题磨砂小弹窗；紧凑多选列表，取消不保存、确定后提交。浅深主题与大字号使用同一公共弹窗外壳。')}
    if filter_toolbar:
        scenes = {
            'history-add': ('添加已有 · 默认状态', '1 类型、日期与全选合并为同一工具行；未筛选、未勾选时不显示笔数。200% 大字空间不足时换行，保留完整文字。'),
            'history-remove': ('移除关联 · 默认状态', '1 相同工具行及显示规则；复用主页账单行，勾选与原账数据保持。'),
            'history-filtered': ('已有账单 · 筛选状态', '1 搜索“设备”后才显示“筛选出 2 笔”；清除入口移到搜索框右侧，不占工具行。'),
            'history-selected': ('已有账单 · 勾选优先', '1 有勾选时只显示“已选 1 笔”，不再显示筛选结果数；状态与全选位于类型、日期同一行。'),
        }
    for scene, (title, note) in scenes.items():
        variants = [*VARIANTS]
        if scene == 'history-add':
            variants.append('keyboard-large')
        for variant in variants:
            sources = [directory / f'{scene}_{variant}_{phase}.png'
                       for phase in ('before', 'after')]
            hashes = [digest(path) for path in sources]
            pictures = [Image.open(path).convert('RGB') for path in sources]
            if pictures[0].size != pictures[1].size:
                raise ValueError(f'Scene dimensions differ: {scene}/{variant}')
            w, h = pictures[0].size
            index = len(pairs) + 1
            canvas = Image.new('RGB', (2 * w + 96, h + 330), '#f7f7f8')
            draw = ImageDraw.Draw(canvas)
            label = VARIANTS.get(variant, '320dp / 200% / 键盘')
            draw.text((24, 12), f'{index:02d} {title} · {label}',
                      font=_font(30), fill='#202124')
            for side, picture in enumerate(pictures):
                x = 24 + side * (w + 48)
                baseline = '改前 / 上一版本地候选' if previous_candidate else '改前 / 331 生产源码'
                draw.text((x, 60), baseline if side == 0 else '改后 / 当前候选',
                          font=_font(24), fill='#555555')
                canvas.paste(picture, (x, 104))
                markers = ([(1, .16)] if filter_toolbar else
                           [(1, .26)] if book_picker else [(1, .16), (2, .40)])
                if filter_toolbar:
                    draw.rectangle((x + 6, 104 + int(h * .16),
                                    x + w - 6, 104 + int(h * .46)),
                                   outline='#a75530', width=4)
                if book_picker:
                    draw.rectangle((x + 6, 104 + int(h * .26),
                                    x + w - 6, 104 + h - 6),
                                   outline='#a75530', width=4)
                for number, relative_y in markers:
                    y = 104 + int(h * relative_y)
                    draw.ellipse((x + 8, y, x + 52, y + 44), fill='#a75530')
                    draw.text((x + 22, y + 4), str(number), font=_font(27), fill='white')
            y = h + 128
            for line in _wrap(draw, note, _font(24), canvas.width - 48):
                draw.text((24, y), line, font=_font(24), fill='#444444')
                y += 34
            draw.text((24, y + 12), '同数据 / 字体 / 主题 / 尺寸；Flutter Widget 离屏，非装机截图。原始 PNG 未修改。',
                      font=_font(22), fill='#666666')
            name = f'{index:02d}_{scene}_{variant}_comparison.png'
            canvas.save(directory / name, optimize=True)
            if hashes != [digest(path) for path in sources]:
                raise ValueError('Original screenshots were changed')
            pairs.append({'scene': scene, 'variant': variant, 'comparison': name,
                          'before': sources[0].name, 'after': sources[1].name,
                          'before_sha256': hashes[0], 'after_sha256': hashes[1],
                          'size': [w, h]})
    contact = Image.new('RGB', (1440, ((len(pairs) + 2) // 3) * 650), '#f7f7f8')
    for index, pair in enumerate(pairs):
        picture = Image.open(directory / pair['comparison'])
        picture.thumbnail((480, 650), Image.Resampling.LANCZOS)
        contact.paste(picture, ((index % 3) * 480, (index // 3) * 650))
    contact.save(directory / ('00_filter_toolbar_contact.png' if filter_toolbar else
                             '00_book_picker_contact.png' if book_picker else
                             '00_refinement_contact.png'), optimize=True)
    paths = ['lib/views/books/transaction_books_sheet.dart',
             'test/multibook_ui_test.dart'] if previous_candidate else [
             'lib/data/app_repository.dart', 'lib/views/books/transaction_books_sheet.dart',
             'lib/widgets/transaction_day_list.dart', 'test/multibook_ui_test.dart']
    (directory / 'comparison_manifest.json').write_text(json.dumps({
        'kind': 'Flutter Widget offscreen', 'device_verified': False,
        **({'before_baseline': 'previous local refinement candidate, not shipped 331'}
           if previous_candidate else
           {'before_production_commit': '3c33bc3c901711e49e32a142cae2dd423fc86d49'}),
        'pairs': pairs, 'current_sources': {path: digest(ROOT / path) for path in paths},
        'notes': ('Previous local toolbar candidate compared with conditional counts and compact controls; same fonts, theme, fixture and dimensions. Original PNGs retained. No device or iOS acceptance.'
                  if filter_toolbar else
                  'Previous local sheet candidate compared with centered dialog; same fonts, theme, fixture and dimensions. Original PNGs retained. No device or iOS acceptance.'
                  if book_picker else
                  'Baseline captured before production UI edits using the same expanded fixture. Normal home TxDayCard behavior retained. No DB or account data modifications. No device or iOS acceptance.'),
    }, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'{len(pairs)} refinement comparison pairs; original hashes unchanged.')


def make_anchored_comparisons():
    directory = ROOT / 'outputs/ui_comparisons/2026-10-23-anchored-selection'
    scenes = {
        'entry-books': ('账本选择', '1 居中确认框改为账户同款锚定菜单；保留多选，点外部收起，保存原账时才写库。'),
        'entry-tags': ('标签选择', '1 底部标签条改为相同锚定菜单；保留多选与快速新建，取消父表单不写账单。'),
        'budget_typography': ('预算字体', '1 主金额44/w800改为42/w600。 2 仅“每月”700改550，后面的金额仍为700。'),
    }
    pairs = []
    for scene, (title, note) in scenes.items():
        for variant, label in VARIANTS.items():
            budget = scene == 'budget_typography'
            phases = ('before-menu', 'after-menu') if budget else ('before', 'after')
            sources = [directory / f'{scene}_{variant}_{phase}.png' for phase in phases]
            hashes = [digest(path) for path in sources]
            pictures = [Image.open(path).convert('RGB') for path in sources]
            if pictures[0].size != pictures[1].size:
                raise ValueError(f'Dimensions differ: {scene}/{variant}')
            w, h = pictures[0].size
            index = len(pairs) + 1
            canvas = Image.new('RGB', (2 * w + 96, h + 330), '#f7f7f8')
            draw = ImageDraw.Draw(canvas)
            draw.text((24, 12), f'{index:02d} {title} · {label}', font=_font(30), fill='#202124')
            for side, picture in enumerate(pictures):
                x = 24 + side * (w + 48)
                draw.text((x, 60), '改前 / 前批本地候选' if side == 0 else '改后 / 当前候选', font=_font(24), fill='#555555')
                canvas.paste(picture, (x, 104))
                regions = [(1, .56, .78)] if not budget else [(1, .08, .27), (2, .78, .95)]
                if budget and variant == 'large':
                    regions = [(1, .08, .30)]
                for number, top, bottom in regions:
                    y = 104 + int(h * top)
                    draw.rectangle((x + 8, y, x + w - 8, 104 + int(h * bottom)), outline='#a75530', width=4)
                    draw.ellipse((x + 12, y, x + 56, y + 44), fill='#a75530')
                    draw.text((x + 26, y + 4), str(number), font=_font(27), fill='white')
            y = h + 128
            for line in _wrap(draw, note, _font(24), canvas.width - 48):
                draw.text((24, y), line, font=_font(24), fill='#444444')
                y += 34
            draw.text((24, y + 8), '同数据 / 主题 / 尺寸 / 字号；Flutter Widget离屏，非装机截图；原始PNG保留。', font=_font(22), fill='#666666')
            if budget and variant == 'large':
                draw.text((24, y + 42), '200%首屏规则位于下方；另有滚动后字重断言，不将首屏截图当作规则可见证据。', font=_font(22), fill='#666666')
            name = f'{index:02d}_{scene}_{variant}_comparison.png'
            canvas.save(directory / name, optimize=True)
            if hashes != [digest(path) for path in sources]:
                raise ValueError('Original screenshots changed')
            pairs.append({'scene': scene, 'variant': variant, 'comparison': name,
                          'before': sources[0].name, 'after': sources[1].name,
                          'before_sha256': hashes[0], 'after_sha256': hashes[1], 'size': [w, h]})
    contact = Image.new('RGB', (1440, 1950), '#f7f7f8')
    for index, pair in enumerate(pairs):
        picture = Image.open(directory / pair['comparison'])
        picture.thumbnail((480, 650), Image.Resampling.LANCZOS)
        contact.paste(picture, ((index % 3) * 480, (index // 3) * 650))
    contact.save(directory / '00_anchored_selection_contact.png', optimize=True)
    paths = ['lib/widgets/ios_menu.dart', 'lib/widgets/tag_selector.dart',
             'lib/views/home/manual_add_sheet.dart', 'lib/views/books/transaction_books_sheet.dart',
             'lib/views/budget/budget_hero_card.dart', 'lib/views/budget/budget_view.dart',
             'assets/fonts/BudgetUnits-VF.ttf', 'pubspec.yaml',
             'test/multibook_ui_test.dart', 'test/budget_view_visual_test.dart']
    (directory / 'comparison_manifest.json').write_text(json.dumps({
        'kind': 'Flutter Widget offscreen', 'device_verified': False,
        'before_baseline': 'previous local candidate, not shipped 331',
        'pairs': pairs, 'current_sources': {path: digest(ROOT / path) for path in paths},
        'notes': 'Account menu component reused. Original PNGs unchanged. Budget has a dedicated 3.3KB Noto OFL variable subset for the requested weight550. No device or iOS acceptance.',
    }, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'{len(pairs)} anchored-selection comparison pairs; original hashes unchanged.')


if __name__ == "__main__":
    main()
