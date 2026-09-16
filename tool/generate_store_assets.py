from __future__ import annotations

from pathlib import Path
from textwrap import wrap

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "store_assets"
SOURCE = STORE / "source"
PHONE = STORE / "phone"

FONT_REGULAR = Path(r"C:\Windows\Fonts\segoeui.ttf")
FONT_SEMIBOLD = Path(r"C:\Windows\Fonts\seguisb.ttf")
FONT_BOLD = Path(r"C:\Windows\Fonts\segoeuib.ttf")


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size=size)


def vertical_gradient(size: tuple[int, int], top: str, bottom: str) -> Image.Image:
    width, height = size
    a = Image.new("RGB", (1, 1), top)
    b = Image.new("RGB", (1, 1), bottom)
    result = Image.new("RGB", size)
    pixels = result.load()
    ca = a.getpixel((0, 0))
    cb = b.getpixel((0, 0))
    for y in range(height):
        t = y / max(1, height - 1)
        color = tuple(round(ca[i] * (1 - t) + cb[i] * t) for i in range(3))
        for x in range(width):
            pixels[x, y] = color
    return result


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    rgba = image.convert("RGBA")
    mask = Image.new("L", rgba.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, rgba.width - 1, rgba.height - 1), radius=radius, fill=255
    )
    rgba.putalpha(mask)
    return rgba


def add_phone_frame(canvas: Image.Image, screenshot: Image.Image, crop_bottom: int) -> None:
    screenshot = screenshot.crop((0, 0, screenshot.width, min(crop_bottom, screenshot.height)))
    screenshot.thumbnail((860, 1530), Image.Resampling.LANCZOS)
    screenshot = rounded_image(screenshot, 42)

    x = (canvas.width - screenshot.width) // 2
    y = 330 + (1530 - screenshot.height) // 2

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x - 14, y - 8, x + screenshot.width + 14, y + screenshot.height + 22),
        radius=56,
        fill=(14, 71, 54, 70),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    canvas.alpha_composite(shadow)

    border = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        (x - 5, y - 5, x + screenshot.width + 5, y + screenshot.height + 5),
        radius=47,
        fill=(255, 255, 255, 245),
        outline=(117, 195, 165, 200),
        width=3,
    )
    canvas.alpha_composite(border)
    canvas.alpha_composite(screenshot, (x, y))


def add_wrapped_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    xy: tuple[int, int],
    text_font: ImageFont.FreeTypeFont,
    fill: str,
    max_chars: int,
    spacing: int = 6,
) -> int:
    lines = wrap(text, width=max_chars)
    y = xy[1]
    for line in lines:
        draw.text((xy[0], y), line, font=text_font, fill=fill)
        box = draw.textbbox((xy[0], y), line, font=text_font)
        y = box[3] + spacing
    return y


def create_phone_asset(
    filename: str,
    screenshot_name: str,
    title: str,
    subtitle: str,
    crop_bottom: int,
) -> None:
    canvas = vertical_gradient((1080, 1920), "#F8FCFA", "#DDF4E9").convert("RGBA")
    decoration = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    deco = ImageDraw.Draw(decoration)
    deco.ellipse((-160, -210, 500, 450), fill=(74, 196, 151, 22))
    deco.ellipse((750, 30, 1250, 530), fill=(1, 131, 101, 16))
    canvas.alpha_composite(decoration)

    icon = Image.open(ROOT / "assets" / "brand" / "fyno_app_icon.png").convert("RGBA")
    icon = rounded_image(ImageOps.fit(icon, (64, 64), Image.Resampling.LANCZOS), 15)
    canvas.alpha_composite(icon, (54, 52))

    draw = ImageDraw.Draw(canvas)
    draw.text((136, 50), "Fyno", font=font(FONT_BOLD, 38), fill="#10251E")
    draw.text((54, 132), title, font=font(FONT_BOLD, 52), fill="#10251E")
    add_wrapped_text(
        draw,
        subtitle,
        (56, 205),
        font(FONT_REGULAR, 27),
        "#40554D",
        max_chars=58,
        spacing=4,
    )

    screenshot = Image.open(SOURCE / screenshot_name).convert("RGB")
    add_phone_frame(canvas, screenshot, crop_bottom)
    canvas.convert("RGB").save(PHONE / filename, quality=95, optimize=True)


def create_feature_graphic() -> None:
    source = Image.open(SOURCE / "feature_generated.png").convert("RGB")
    feature = ImageOps.fit(
        source,
        (1024, 500),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    ).convert("RGBA")

    panel = Image.new("RGBA", feature.size, (0, 0, 0, 0))
    panel_draw = ImageDraw.Draw(panel)
    panel_draw.rounded_rectangle(
        (570, 105, 984, 400),
        radius=34,
        fill=(255, 255, 255, 218),
        outline=(188, 226, 211, 210),
        width=2,
    )
    feature.alpha_composite(panel)

    draw = ImageDraw.Draw(feature)
    draw.text((614, 142), "Fyno", font=font(FONT_BOLD, 62), fill="#10251E")
    draw.text(
        (614, 220),
        "Seu dinheiro, mais claro.",
        font=font(FONT_SEMIBOLD, 28),
        fill="#087E60",
    )
    draw.text(
        (614, 275),
        "Gastos • notas fiscais • backup",
        font=font(FONT_REGULAR, 20),
        fill="#40554D",
    )
    draw.text(
        (614, 312),
        "Privacidade e controle em primeiro lugar.",
        font=font(FONT_REGULAR, 17),
        fill="#53665F",
    )
    feature.convert("RGB").save(STORE / "feature_graphic_1024x500.png", optimize=True)


def create_store_icon() -> None:
    icon = Image.open(ROOT / "assets" / "brand" / "fyno_app_icon.png").convert("RGB")
    icon = ImageOps.fit(icon, (512, 512), method=Image.Resampling.LANCZOS)
    icon.save(STORE / "app_icon_512.png", optimize=True)


def main() -> None:
    PHONE.mkdir(parents=True, exist_ok=True)
    create_store_icon()
    create_feature_graphic()

    specs = [
        (
            "01_visao_do_mes.png",
            "01_dashboard.png",
            "Enxergue o mês inteiro",
            "Saldo, receitas e despesas em uma visão clara.",
            2130,
        ),
        (
            "02_extrato_inteligente.png",
            "02_transactions.png",
            "Seu histórico, sem planilhas",
            "Filtros, categorias e lançamentos fáceis de revisar.",
            2180,
        ),
        (
            "03_notificacoes_seguras.png",
            "03_notifications.png",
            "O banco avisa. Você confirma.",
            "Sugestões locais de receita ou despesa, sempre sob seu controle.",
            2200,
        ),
        (
            "04_qr_code_ao_vivo.png",
            "04_qr_scanner.png",
            "Aponte. O Fyno lê.",
            "QR Code da NFC-e detectado ao vivo, sem salvar a foto.",
            2400,
        ),
        (
            "05_temas_e_backup.png",
            "05_settings.png",
            "Do seu jeito, em qualquer tela",
            "Temas claro, escuro e automático, com backup Google opcional.",
            2250,
        ),
    ]
    for spec in specs:
        create_phone_asset(*spec)


if __name__ == "__main__":
    main()
