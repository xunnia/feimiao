"""Numbered comparisons from real Widget captures; originals stay untouched."""
from pathlib import Path
from PIL import Image, ImageDraw
import make_ui_comparisons as ui

OUT = Path(__file__).resolve().parents[1] / 'outputs/ui_comparisons/2026-10-06-concept'
GROUPS = [
    ('page-warm', '资产总览 / 浅色', '-before', '-after', [(0.04, .08, .96, .62), (.04, .62, .96, .98)], ['主卡合并为真实三列摘要，去掉重复四卡；核对与趋势明确分开。', '待处理与资产结构统一，原有核对和质量说明仍保留。']),
    ('page-night', '资产总览 / 深色', '-before', '-after', [(0.04, .08, .96, .62), (.04, .62, .96, .98)], ['同款层级跟随深色主题，不使用白底；主金额和摘要保持可读。', '结构与操作入口保留。']),
    ('funds-warm-420-1', '资金 / 浅色', '-before', '-after', [(0.04, .08, .96, .36), (.04, .36, .96, .97)], ['新增全局人民币资金净值、搜索、分类与排序，不随过滤改金额。', '分组名移到卡外；校准副标题、方圆角图标和完整右对齐金额。']),
    ('funds-night-420-1', '资金 / 深色', '-before', '-after', [(0.04, .08, .96, .36), (.04, .36, .96, .97)], ['摘要与筛选同款；深色主题取色。', '保留权益、借贷、清零折叠和归档入口。']),
    ('funds-quality-warm', '资金摘要组件 / 物品待确认 / 浅色', '-before', '-after', [(0.04, .04, .96, .55)], ['同一固定测试账本：改前沿用全净资产质量，改后只提示资金相关问题；金额不变。']),
    ('funds-quality-night', '资金摘要组件 / 物品待确认 / 深色', '-before', '-after', [(0.04, .04, .96, .55)], ['这是资金摘要组件对比，不是整页或装机图；账户、权益和负债待确认仍保留提示。']),
    ('physical_detail_light', '物品详情 / 浅色', '_before', '_after', [(0.04, .06, .96, .51), (.04, .52, .96, .99)], ['无照片用68方形占位，日均与三项指标收进主卡，真实持有天数。', '保修、资料和生命周期操作保留。']),
    ('physical_detail_dark', '物品详情 / 深色', '_before', '_after', [(0.04, .06, .96, .51), (.04, .52, .96, .99)], ['同款主卡、字重和原生菜单入口。', '深色保修和资料仍可读。']),
    ('physical_detail_photo', '物品详情 / 有照片', '_before', '_after', [(0.04, .06, .96, .78)], ['真实照片仍可预览，不缩成无图占位；操作和指标同款。']),
    ('physical_detail_narrow_large_text', '物品详情 / 窄屏大字', '_before', '_after', [(0.04, .06, .96, .94)], ['三指标与操作在大字号时分行，未知成本不是假零。']),
    ('budget_main', '预算 / 浅色', '_before', '_after', [(0.04, .05, .96, .25), (.04, .25, .96, .55), (.04, .56, .96, .81)], ['44字重主金额，真实已花/预算/节奏数据不变。', '紧凑日历，中文年月、今天主色、超支橙色下划线。', '日常和特别规则、月底结余放在同组，保留编辑与提示。']),
    ('budget_main_dark', '预算 / 深色', '_before', '_after', [(0.04, .05, .96, .55), (.04, .56, .96, .81)], ['深色主题与日历状态同款。', '规则和月底结余同组。']),
    ('budget_narrow_large_text', '预算 / 窄屏大字', '_before', '_after', [(0.04, .04, .96, .94)], ['大金额与月份必要时换行，保留完整金额、翻月和日历交互。']),
    ('budget_day_sheet', '预算 / 日期详情', '_before', '_after', [(0.04, .62, .96, .98)], ['日期详情和真实账单保持一致；新的日历入口仍能打开。']),
    ('budget_rule_sheet', '预算 / 编辑规则', '_before', '_after', [(0.04, .37, .96, .98)], ['新规则表单与历史影响提示保持一致，不改保存逻辑。']),
    ('budget_calendar_short_rule', '预算 / 短安排', '_before', '_after', [(0.04, .06, .96, .97)], ['日历保留安排覆盖展示；长标题可打开查看。']),
]

def build(group):
    name, title, left, right, boxes, notes = group
    originals = [Image.open(OUT / f'{name}{suffix}.png').convert('RGB') for suffix in (left, right)]
    if originals[0].size != originals[1].size:
        raise ValueError(f'Incomparable dimensions: {name}')
    images = [im.resize((420, round(im.height * 420 / im.width)), Image.Resampling.LANCZOS) for im in originals]
    height = images[0].height
    result = Image.new('RGB', (936, height + 150 + len(notes) * 48), '#f7f7f8')
    draw = ImageDraw.Draw(result)
    draw.text((24, 12), title, font=ui._font(23, bold=True), fill='#202124')
    draw.text((24, 48), '改前', font=ui._font(17), fill='#7c4d3a')
    draw.text((492, 48), '改后', font=ui._font(17), fill='#315f78')
    draw.text((24, 73), 'Flutter Widget离屏图，非装机图；同场景等比预览，原图未改', font=ui._font(14), fill='#70757a')
    rects = [(int(a * 420), int(b * height), int(c * 420), int(d * height)) for a, b, c, d in boxes]
    for x, screenshot in zip((24, 492), images):
        result.paste(ui._annotate(screenshot, rects), (x, 104))
    y = height + 116
    for index, note in enumerate(notes, 1):
        for line in ui._wrap(draw, f'{index}. {note}', ui._font(16), 880):
            draw.text((24, y), line, font=ui._font(16), fill='#4e5156')
            y += 22
    path = OUT / f'{name}_before_after.png'
    result.save(path, optimize=True)
    return path

if __name__ == '__main__':
    ui.OUT = OUT
    outputs = [build(group) for group in GROUPS]
    print(ui.build_contact_sheet(outputs))
    print(f'{len(outputs)} comparison pairs; originals preserved')
