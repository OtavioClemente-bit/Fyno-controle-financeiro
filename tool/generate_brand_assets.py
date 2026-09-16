"""Builds every raster brand asset from the approved Fyno master mark.

The source artwork stays untouched in assets/brand/source. Running this script
keeps launcher, adaptive, splash and in-app images optically consistent.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "brand" / "source"
OUTPUT = ROOT / "assets" / "brand"


def _hex(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    return tuple(int(value[index : index + 2], 16) for index in (0, 2, 4))


def _contain_mark(source: Image.Image, size: int, occupancy: float) -> Image.Image:
    alpha = source.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("The master mark has no visible pixels")

    cropped = source.crop(bounds)
    target = int(size * occupancy)
    ratio = min(target / cropped.width, target / cropped.height)
    resized = cropped.resize(
        (round(cropped.width * ratio), round(cropped.height * ratio)),
        Image.Resampling.LANCZOS,
    )

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - resized.width) // 2
    y = (size - resized.height) // 2
    canvas.alpha_composite(resized, (x, y))
    return canvas


def _vertical_gradient(size: int, top: str, bottom: str) -> Image.Image:
    start = _hex(top)
    end = _hex(bottom)
    image = Image.new("RGB", (size, size), start)
    draw = ImageDraw.Draw(image)
    for y in range(size):
        amount = y / max(size - 1, 1)
        color = tuple(round(a + (b - a) * amount) for a, b in zip(start, end))
        draw.line((0, y, size, y), fill=color)
    return image


def _tinted_mark(mark: Image.Image, top: str, bottom: str) -> Image.Image:
    tint = _vertical_gradient(mark.height, top, bottom).convert("RGBA")
    tint.putalpha(mark.getchannel("A"))
    return tint


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)

    master = Image.open(SOURCE / "fyno_mark_master.png").convert("RGBA")
    mark = _contain_mark(master, 1024, 0.70)
    mark.save(OUTPUT / "fyno_mark.png", optimize=True)

    compact_mark = _contain_mark(master, 1024, 0.94)
    compact_mark.save(OUTPUT / "fyno_mark_compact.png", optimize=True)
    _tinted_mark(compact_mark, "#D8FFF0", "#61DBAE").save(
        OUTPUT / "fyno_mark_compact_on_dark.png", optimize=True
    )

    adaptive = _contain_mark(master, 1024, 0.62)
    adaptive.save(OUTPUT / "fyno_adaptive_foreground.png", optimize=True)
    _tinted_mark(adaptive, "#FFFFFF", "#FFFFFF").save(
        OUTPUT / "fyno_monochrome.png", optimize=True
    )

    mark_on_dark = _tinted_mark(mark, "#D8FFF0", "#61DBAE")
    mark_on_dark.save(OUTPUT / "fyno_mark_on_dark.png", optimize=True)

    icon = _vertical_gradient(1024, "#F8FCFA", "#DDF4EA").convert("RGBA")
    halo = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    halo_draw = ImageDraw.Draw(halo)
    halo_draw.ellipse((190, 170, 834, 814), fill=(54, 211, 153, 34))
    halo = halo.filter(ImageFilter.GaussianBlur(72))
    icon.alpha_composite(halo)
    icon.alpha_composite(_contain_mark(master, 1024, 0.66))
    icon.convert("RGB").save(OUTPUT / "fyno_app_icon.png", quality=96, optimize=True)

    dark_background = Image.open(
        SOURCE / "fyno_splash_dark_master.png"
    ).convert("RGB")
    light_background = Image.open(
        SOURCE / "fyno_splash_light_master.png"
    ).convert("RGB")
    target = (1080, 1920)
    dark_background.resize(target, Image.Resampling.LANCZOS).save(
        OUTPUT / "fyno_splash_dark.jpg", quality=91, optimize=True, progressive=True
    )
    light_background.resize(target, Image.Resampling.LANCZOS).save(
        OUTPUT / "fyno_splash_light.jpg", quality=91, optimize=True, progressive=True
    )


if __name__ == "__main__":
    main()
