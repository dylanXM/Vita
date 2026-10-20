"""Generate platform icons from Vita's approved source artwork.

Requires Pillow. Run from any directory with: python3 app/tool/generate_brand_icons.py
"""

from pathlib import Path
import json
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
SOURCE = ROOT / "assets/branding/vita_app_icon_source.png"


def render():
    """Use the approved artwork rather than regenerating the previous mark."""
    with Image.open(SOURCE) as source:
        return source.convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def adaptive_foreground(icon):
    # Android masks the central 72/108 area. Keep the whole approved artwork
    # within that area so the heart and speech bubble cannot be clipped.
    foreground = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    inset = round(SIZE / 6)
    artwork = icon.resize((SIZE - 2 * inset, SIZE - 2 * inset), Image.Resampling.LANCZOS)
    foreground.paste(artwork, (inset, inset))
    return foreground


def save_scaled(source, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    source.resize((size, size), Image.Resampling.LANCZOS).save(path)


def main():
    icon = render()
    foreground = adaptive_foreground(icon)
    brand_mark = icon
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
        save_scaled(foreground.convert("RGB"), web / f"icons/Icon-maskable-{size}.png", size)
    save_scaled(icon, web / "favicon.png", 48)
    icon.save(ROOT / "windows/runner/resources/app_icon.ico", sizes=[(s, s) for s in (16, 32, 48, 64, 128, 256)])


if __name__ == "__main__":
    main()
