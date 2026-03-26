#!/usr/bin/env python3
"""生成 VoiceFlow macOS 应用图标"""

import os
from PIL import Image, ImageDraw

SIZE = 1024
MARGIN = 100
CORNER = 190


def draw_icon():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    x0, y0 = MARGIN, MARGIN
    x1, y1 = SIZE - MARGIN, SIZE - MARGIN
    cx, cy = SIZE // 2, SIZE // 2

    # 1. 底色圆角矩形（春绿）
    draw.rounded_rectangle([x0, y0, x1, y1], radius=CORNER,
                           fill=(72, 195, 140, 255))

    # 2. 底部叠加一层淡蓝渐变
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    for y in range(y0, y1):
        t = (y - y0) / (y1 - y0)
        alpha = int(80 * t)  # 底部更蓝
        od.line([(x0, y), (x1, y)], fill=(40, 130, 210, alpha))
    # 用圆角遮罩裁剪
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([x0, y0, x1, y1], radius=CORNER, fill=255)
    overlay.putalpha(mask)
    img = Image.alpha_composite(img, overlay)

    # 3. 顶部高光
    hl = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    for y in range(y0, y0 + 200):
        t = (y - y0) / 200
        a = int(55 * (1 - t) ** 2)
        hd.line([(x0, y), (x1, y)], fill=(255, 255, 255, a))
    hl.putalpha(mask.copy())
    img = Image.alpha_composite(img, hl)

    # 4. 声波条
    heights = [0.28, 0.52, 0.88, 0.52, 0.28]
    bw, gap = 52, 36
    total = len(heights) * bw + (len(heights) - 1) * gap
    sx = (SIZE - total) / 2
    max_h = (y1 - y0) * 0.48

    draw2 = ImageDraw.Draw(img)
    for i, hr in enumerate(heights):
        bx = sx + i * (bw + gap)
        bh = max_h * hr
        draw2.rounded_rectangle(
            [bx, cy - bh / 2, bx + bw, cy + bh / 2],
            radius=bw // 2,
            fill=(255, 255, 255, 240)
        )

    return img


def generate_iconset(icon, out):
    os.makedirs(out, exist_ok=True)
    for sz, name in [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]:
        icon.resize((sz, sz), Image.LANCZOS).save(os.path.join(out, name))


if __name__ == "__main__":
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assets = os.path.join(base, "assets")
    os.makedirs(assets, exist_ok=True)

    icon = draw_icon()
    icon.save(os.path.join(assets, "icon.png"))

    iconset = os.path.join(assets, "VoiceFlow.iconset")
    generate_iconset(icon, iconset)

    icns = os.path.join(assets, "VoiceFlow.icns")
    os.system(f'iconutil -c icns "{iconset}" -o "{icns}"')
    print("Done: assets/icon.png + assets/VoiceFlow.icns")
