"""Measure the selection-box outline in a screenshot, in device pixels.

The box is a rounded rect: a pale clay fill (0xCC5C2E at 22% over white) with a
clayStrong outline (0xA8481F at 65% over that fill, ~ (194,123,92)). The
outline is the darkest, most saturated orange on the page, so a threshold on
saturation and darkness isolates it, and the horizontal run lengths through the
box's left and right edges ARE the drawn line width.
"""
import sys
from collections import Counter
from PIL import Image


def outline(px):
    r, g, b = px[:3]
    # strong clay: clearly orange, and darker than the fill
    return r > 140 and r < 235 and (r - g) > 45 and (r - b) > 70 and g < 175


def runs(path, sample_every=1):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    data = img.load()
    lengths = Counter()
    rows_with_boxes = 0
    for y in range(0, h, sample_every):
        row = []
        run = 0
        for x in range(w):
            if outline(data[x, y]):
                run += 1
            else:
                if run:
                    row.append(run)
                run = 0
        if run:
            row.append(run)
        # a row that crosses a box has at least two short runs (its two edges)
        short = [n for n in row if 1 <= n <= 40]
        if len(short) >= 2:
            rows_with_boxes += 1
            for n in short:
                lengths[n] += 1
    return img.size, rows_with_boxes, lengths


for path in sys.argv[1:]:
    size, rows, lengths = runs(path)
    total = sum(lengths.values())
    top = lengths.most_common(6)
    if total:
        weighted = sum(n * c for n, c in lengths.items()) / total
    else:
        weighted = 0
    print(f"{path.split('/')[-1]}  {size[0]}x{size[1]}px  rows crossing a box: {rows}")
    print(f"   edge run lengths (px): {top}")
    print(f"   mean edge width: {weighted:.2f}px   modal: "
          f"{top[0][0] if top else '-'}px")
