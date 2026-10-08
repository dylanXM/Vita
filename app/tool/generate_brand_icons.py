"""Generate Vita's geometric brand mark and platform icon sizes.

Requires Pillow. Run from any directory with: python3 app/tool/generate_brand_icons.py
"""

from pathlib import Path
import json
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
SCALE = 4
BACKGROUND = (26, 21, 48, 255)
LEFT = (247, 243, 255, 255)
RIGHT = (173, 153, 237, 255)
STAR = (255, 139, 122, 255)


def bezier(a, b, c, d, t):
    u = 1 - t
    return (
        u**3 * a[0] + 3 * u**2 * t * b[0] + 3 * u * t**2 * c[0] + t**3 * d[0],
        u**3 * a[1] + 3 * u**2 * t * b[1] + 3 * u * t**2 * c[1] + t**3 * d[1],
    )


def render(foreground=False, on_light=False):
    side = SIZE * SCALE
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0) if foreground else BACKGROUND)
    draw = ImageDraw.Draw(image)

    def stroke(points, color, width):
        points = [(round(x * SCALE), round(y * SCALE)) for x, y in points]
        draw.line(points, fill=color, width=width * SCALE, joint="curve")
        r = width * SCALE // 2
        for x, y in (points[0], points[-1]):
            draw.ellipse((x - r, y - r, x + r, y + r), fill=color)

    left = [bezier((431, 277), (255, 336), (255, 688), (431, 747), i / 160) for i in range(161)]
    right = [bezier((593, 277), (769, 336), (769, 688), (593, 747), i / 160) for i in range(161)]
    stroke(left, BACKGROUND if on_light else LEFT, 98)
    stroke(right, (105, 79, 169, 255) if on_light else RIGHT, 98)

    # A single spark stands for a living character in the shared world.
    cx = cy = 512 * SCALE
    radius = 73 * SCALE
    pinch = 17 * SCALE
    vertices = [
        (cx, cy - radius), (cx + pinch, cy - pinch),
        (cx + radius, cy), (cx + pinch, cy + pinch),
        (cx, cy + radius), (cx - pinch, cy + pinch),
        (cx - radius, cy), (cx - pinch, cy - pinch),
    ]
    draw.polygon(vertices, fill=STAR)
    return image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def save_scaled(source, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    source.resize((size, size), Image.Resampling.LANCZOS).save(path)


def main():
    icon = render()
    foreground = render(foreground=True)
    brand_mark = render(foreground=True, on_light=True)
    save_scaled(icon, ROOT / "assets/branding/vita_app_icon_1024.png", 1024)
    save_scaled(brand_mark, ROOT / "assets/branding/vita_brand_mark.png", 512)

    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for item in json.loads((ios / "Contents.json").read_text())["images"]:
        if "filename" not in item:
            continue
        points = float(item["size"].split("x")[0])
        pixels = round(points * float(item["scale"].removesuffix("x")))
        save_scaled(icon, ios / item["filename"], pixels)

    android = ROOT / "android/app/src/main/res"
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, size in densities.items():
        folder = android / f"mipmap-{density}"
        save_scaled(icon, folder / "ic_launcher.png", size)
        save_scaled(foreground, folder / "ic_launcher_foreground.png", round(size * 2.25))

    mac = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_scaled(icon, mac / f"app_icon_{size}.png", size)

    web = ROOT / "web"
    for size in (192, 512):
        save_scaled(icon, web / f"icons/Icon-{size}.png", size)
        save_scaled(icon, web / f"icons/Icon-maskable-{size}.png", size)
    save_scaled(icon, web / "favicon.png", 48)
    icon.save(ROOT / "windows/runner/resources/app_icon.ico", sizes=[(s, s) for s in (16, 32, 48, 64, 128, 256)])


if __name__ == "__main__":
    main()
