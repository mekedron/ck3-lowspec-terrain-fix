"""Workshop preview generator shared by the low spec mods.

Layout, 1024x1024, built to read at Steam's ~200 px listing size:
  top band     : mod name (bold, ~90 px) and ADVANCED SHADERS OFF (bold, ~60 px)
  two halves   : BEFORE / AFTER screenshots, each labelled with a ~100 px bold word
All text sits on solid dark backing so it survives any screenshot underneath.
"""
from PIL import Image, ImageDraw, ImageFont

FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
S = 1024
BAND = 190
HALF = (S - BAND) // 2            # 417
CROP_H = 853                      # 2120 x 853 keeps the halves' 2.54:1 aspect from a 5120x1440 shot
GOLD = (222, 190, 120, 255)
CREAM = (248, 242, 230, 255)
DARK = (14, 12, 10, 255)

def crop_half(path, crop):
    return Image.open(path).convert("RGB").crop(crop).resize((S, HALF), Image.LANCZOS)

def label(d, y, text, font, pad=22):
    tw = d.textlength(text, font=font)
    box = [26, y, 26 + tw + pad * 2, y + font.size + pad * 2 - 10]
    d.rectangle(box, fill=(14, 12, 10, 215))
    d.text((26 + pad, y + pad - 8), text, font=font, fill=CREAM)

def make(out, title, before, after, crop_before, crop_after, sub="ADVANCED SHADERS OFF"):
    canvas = Image.new("RGB", (S, S), DARK[:3])
    canvas.paste(crop_half(before, crop_before), (0, BAND))
    canvas.paste(crop_half(after, crop_after), (0, BAND + HALF))
    d = ImageDraw.Draw(canvas, "RGBA")
    f_title = ImageFont.truetype(FB, 92)
    f_sub = ImageFont.truetype(FB, 58)
    f_tag = ImageFont.truetype(FB, 104)
    # top band: centred title, gold subtitle
    tw = d.textlength(title, font=f_title); d.text(((S - tw) / 2, 18), title, font=f_title, fill=CREAM)
    sw = d.textlength(sub, font=f_sub); d.text(((S - sw) / 2, 118), sub, font=f_sub, fill=GOLD)
    # half labels
    # labels at the bottom of each half, so the top of the screenshot stays clear
    tag_h = f_tag.size + 22 * 2 - 10
    label(d, BAND + HALF - tag_h - 22, "BEFORE", f_tag)
    label(d, S - tag_h - 22, "AFTER", f_tag)
    # seams
    d.rectangle([0, BAND - 4, S, BAND], fill=GOLD)
    d.rectangle([0, BAND + HALF - 3, S, BAND + HALF + 2], fill=GOLD)
    clean = Image.new("RGB", canvas.size); clean.putdata(list(canvas.getdata()))
    clean = clean.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)
    clean.save(out, "PNG", optimize=True)
    import os
    check = os.path.join(os.path.dirname(os.path.abspath(__file__)), "thumbnail-200px.png")
    clean.convert("RGB").resize((200, 200), Image.LANCZOS).save(check)
    import os; print(out, os.path.getsize(out), "bytes")
