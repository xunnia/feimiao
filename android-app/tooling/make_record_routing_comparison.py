from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

folder = Path(__file__).resolve().parents[1] / 'outputs/ui_comparisons/2026-09-13'
before = Image.open(folder / 'record_routing_before_verified.png').convert('RGB')
after = Image.open(folder / 'record_routing_after_verified.png').convert('RGB')
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
canvas = Image.new('RGB', (before.width + after.width + 30, max(before.height, after.height) + 90), 'white')
canvas.paste(before, (0, 55))
canvas.paste(after, (before.width + 30, 55))
draw = ImageDraw.Draw(canvas)
draw.text((10, 8), '修改前', font=font, fill='black')
draw.text((before.width + 40, 8), '修改后：1 移除用途分配入口', font=font, fill='black')
draw.rectangle((8, 180, before.width - 8, 236), outline='#cf6b27', width=3)
draw.text((14, 180), '1', font=font, fill='#cf6b27')
draw.text((10, canvas.height - 30), '离屏 Widget 对比；记账请求跟随输入框模型和思考强度。', font=font, fill='black')
canvas.save(folder / 'record_routing_before_after.png')
