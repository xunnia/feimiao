"""Build the tiny Noto Sans SC variable subset used for exact budget-unit weight.

Usage: python tooling/subset_budget_units.py <NotoSansSC-VF.ttf>
The source font is OFL licensed; retain assets/fonts/OFL.txt with the output.
"""
import argparse
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    font = TTFont(args.source, recalcTimestamp=False)
    if not any(a.axisTag == 'wght' and a.minValue <= 550 <= a.maxValue
               for a in font['fvar'].axes):
        raise ValueError('The source must support variable weight 550')
    glyphs = '每月'
    if not all(ord(c) in font.getBestCmap() for c in glyphs):
        raise ValueError('The source is missing required Chinese glyphs')
    worker = subset.Subsetter()
    worker.populate(text=glyphs)
    worker.subset(font)
    target = Path(__file__).resolve().parents[1] / 'assets/fonts/BudgetUnits-VF.ttf'
    font.save(target)
    font.close()
    print(f'Generated {target.name}: {target.stat().st_size} bytes')


if __name__ == '__main__':
    main()
