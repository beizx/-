from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

SIZE = 1024
BG = (20, 18, 33, 255)
PURPLE_TOP = (160, 141, 255)
PURPLE_BOTTOM = (75, 58, 150)
WHITE = (248, 245, 255)
BORDER = (237, 232, 255, 150)


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        ImageDraw.Draw(img).line((0, y, size, y), fill=color + (255,))
    return img


def find_font():
    candidates = [
        r"C:\Windows\Fonts\simsun.ttc",
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\simhei.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    raise SystemExit("no CJK font found")


def build_icon(with_background: bool, tile_ratio=0.74):
    canvas = Image.new("RGBA", (SIZE, SIZE), BG if with_background else (0, 0, 0, 0))
    tile = int(SIZE * tile_ratio)
    offset = (SIZE - tile) // 2
    radius = int(tile * 0.235)

    tile_img = gradient(tile, PURPLE_TOP, PURPLE_BOTTOM).convert("RGBA")
    tile_img.putalpha(rounded_mask(tile, radius))

    if with_background:
        shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        shadow_draw = ImageDraw.Draw(shadow)
        shadow_draw.rounded_rectangle(
            (offset + 8, offset + 18, offset + tile + 8, offset + tile + 18),
            radius=radius,
            fill=(0, 0, 0, 110),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(18))
        canvas.alpha_composite(shadow)

    canvas.alpha_composite(tile_img, (offset, offset))

    draw = ImageDraw.Draw(canvas)
    inset = int(tile * 0.085)
    draw.rounded_rectangle(
        (offset + inset, offset + inset, offset + tile - inset, offset + tile - inset),
        radius=int(radius * 0.86),
        outline=BORDER,
        width=max(1, int(tile * 0.004)),
    )

    font_path = find_font()
    font_size = int(tile * 0.56)
    font = ImageFont.truetype(font_path, font_size)
    char = "读"
    bbox = draw.textbbox((0, 0), char, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = offset + (tile - tw) / 2 - bbox[0]
    ty = offset + (tile - th) / 2 - bbox[1]
    draw.text((tx, ty), char, font=font, fill=WHITE)
    return canvas


assets = os.path.join(os.path.dirname(__file__), "..", "assets")
assets = os.path.abspath(assets)
build_icon(True).convert("RGB").save(os.path.join(assets, "app_icon.png"), "PNG")
build_icon(False).save(os.path.join(assets, "app_icon_foreground.png"), "PNG")
preview = Image.new("RGBA", (760, 760), BG)
icon = build_icon(True).resize((640, 640), Image.LANCZOS)
preview.alpha_composite(icon, (60, 60))
preview.convert("RGB").save(os.path.join(assets, "icon_preview.png"), "PNG")
print("icons written to", assets)
