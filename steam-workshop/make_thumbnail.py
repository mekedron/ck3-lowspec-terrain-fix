from PIL import Image, ImageDraw, ImageFont

OLD = "/home/nikita/Pictures/Screenshots/Screenshot_20260912_133213.png"  # blurry, vanilla
NEW = "/home/nikita/Pictures/Screenshots/Screenshot_20260912_135317.png"  # sharp, modded
OUT = "/home/nikita/Projects/ck3-lowspec-terrain-fix/thumbnail.png"

S = 1280           # square side
H = S // 2         # half height
CROP = (1500, 280, 3620, 1340)   # 2120x1060, 2:1, clear of every UI element

FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

def half(path):
    im = Image.open(path).convert("RGB").crop(CROP)
    return im.resize((S, H), Image.LANCZOS)

canvas = Image.new("RGB", (S, S))
canvas.paste(half(OLD), (0, 0))
canvas.paste(half(NEW), (0, H))

d = ImageDraw.Draw(canvas, "RGBA")
big = ImageFont.truetype(FB, 62)
small = ImageFont.truetype(FR, 30)

def badge(y_top, title, sub):
    pad_x, pad_y = 26, 18
    tw = d.textlength(title, font=big)
    sw = d.textlength(sub, font=small)
    w = int(max(tw, sw)) + pad_x * 2
    h = pad_y * 2 + 62 + 10 + 34
    d.rectangle([28, y_top, 28 + w, y_top + h], fill=(12, 10, 8, 205))
    d.text((28 + pad_x, y_top + pad_y), title, font=big, fill=(245, 238, 225, 255))
    d.text((28 + pad_x, y_top + pad_y + 70), sub, font=small, fill=(198, 176, 132, 255))

badge(30, "BEFORE", "vanilla, Advanced Shaders off")
badge(H + 30, "AFTER", "same setting, with this mod")

# seam between the two halves
d.rectangle([0, H - 3, S, H + 2], fill=(196, 168, 116, 255))

# strip every source chunk: rebuild from raw pixels
clean = Image.new("RGB", canvas.size)
clean.putdata(list(canvas.getdata()))

# 256-colour palette keeps the full 1280x1280 under Steam's 1 MB preview limit;
# at this scale the dither is invisible and downscaling would cost more detail.
clean = clean.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)
clean.save(OUT, "PNG", optimize=True)
print("saved", OUT, clean.size, OUT and __import__("os").path.getsize(OUT), "bytes")
