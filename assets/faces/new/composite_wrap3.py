"""Zombie wrap v3: front photo + neck-skin sides (mirror-tiled, no face
features) + keyed real-ear decals + hair/nape back. Veteran wrap kept
from v2 (already good)."""
from PIL import Image, ImageFilter
import os, math

BASE = os.path.expanduser("~/workspace/bombies-dead-zone/assets/faces")
W, H = 2048, 1024
TOP, BOT = 82, 800
PH = BOT - TOP
FEATHER = 48

def load(name):
    return Image.open(os.path.join(BASE, name)).convert("RGB")

def crop_frac(im, x0, y0, x1, y1):
    w, h = im.size
    return im.crop((int(w*x0), int(h*y0), int(w*x1), int(h*y1)))

def panel(im, box):
    return crop_frac(im, *box).resize((512, PH), Image.LANCZOS)

def mirror_tile(patch, w=512, h=PH):
    pw, ph = patch.size
    tile = Image.new("RGB", (w, h))
    x, col = 0, 0
    while x < w:
        y, row = 0, 0
        while y < h:
            p = patch
            if col % 2 == 1:
                p = p.transpose(Image.FLIP_LEFT_RIGHT)
            if row % 2 == 1:
                p = p.transpose(Image.FLIP_TOP_BOTTOM)
            tile.paste(p, (x, y))
            y += ph; row += 1
        x += pw; col += 1
    return tile.filter(ImageFilter.GaussianBlur(1.2))

def key_ear(crop_img, skin_tone, size=(120, 170)):
    """Remove photo-background grey (keyed to skin tone), return decal
    with soft elliptical alpha."""
    im = crop_img.resize(size, Image.LANCZOS)
    w, h = size
    # bg colour from corners
    px = im.load()
    corners = [px[2, 2], px[w-3, 2], px[2, h-3], px[w-3, h-3]]
    bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3))
    out = Image.new("RGB", size, skin_tone)
    op = out.load()
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            d = math.sqrt(sum((p[i] - bg[i]) ** 2 for i in range(3)))
            if d < 34:
                # background -> skin tone, keep luminance shading
                lum = (0.299*p[0] + 0.587*p[1] + 0.114*p[2]) / 255.0
                bl = (0.299*bg[0] + 0.587*bg[1] + 0.114*bg[2]) / 255.0
                f = lum / max(bl, 0.05)
                op[x, y] = tuple(max(0, min(255, int(skin_tone[i] * f))) for i in range(3))
            else:
                op[x, y] = p
    mask = Image.new("L", size, 0)
    md = mask.load()
    cx, cy = w / 2, h / 2
    for y in range(h):
        for x in range(w):
            nx, ny = (x - cx) / (w * 0.52), (y - cy) / (h * 0.52)
            r = math.sqrt(nx*nx + ny*ny)
            a = 255 if r <= 0.7 else max(0, int(255 * (1 - (r - 0.7) / 0.3)))
            md[x, y] = a
    mask = mask.filter(ImageFilter.GaussianBlur(4))
    return out, mask

Z = load("media-generation-bombie-face-0-a0039a1d-4176-45e3-bf6f-b5b7a5ec8e2b.webp")
z_front = panel(Z, (0.12, 0.02, 0.88, 0.80))
neck_patch = crop_frac(Z, 0.35, 0.83, 0.65, 0.93)
skin_tone = neck_patch.resize((1, 1)).getpixel((0, 0))
z_side = mirror_tile(neck_patch)
hair = crop_frac(Z, 0.30, 0.02, 0.70, 0.13).resize((512, 430), Image.LANCZOS)
nape = neck_patch.resize((512, 288), Image.LANCZOS)
z_back = Image.new("RGB", (512, PH))
z_back.paste(hair, (0, 0))
z_back.paste(nape, (0, 430))

ear_r_crop = crop_frac(Z, 0.185, 0.41, 0.265, 0.58)  # person's right ear
ear_l_crop = crop_frac(Z, 0.735, 0.41, 0.815, 0.58)  # person's left ear
ear_r, mask_r = key_ear(ear_r_crop, skin_tone)
ear_l, mask_l = key_ear(ear_l_crop, skin_tone)

strips = {"front": z_front, "right": z_side, "left": z_side, "back": z_back}
canvas = Image.new("RGB", (W, H), skin_tone)
canvas.paste(z_side, (256, TOP))
canvas.paste(z_front, (768, TOP))
canvas.paste(z_side, (1280, TOP))
canvas.paste(z_back.crop((0, 0, 256, PH)), (1792, TOP))
canvas.paste(z_back.crop((256, 0, 512, PH)), (0, TOP))
def strip_px(name, x, y):
    py = y - TOP
    if name == "back":
        sx = (x - 1792) % 512
    elif name == "right":
        sx = x - 256
    elif name == "front":
        sx = x - 768
    else:
        sx = x - 1280
    return strips[name].getpixel((max(0, min(511, sx)), max(0, min(PH - 1, py))))
for bx, ln, rn in [(256, "back", "right"), (768, "right", "front"),
                   (1280, "front", "left"), (1792, "left", "back")]:
    for dx in range(-FEATHER // 2, FEATHER // 2):
        x = bx + dx
        if x < 0 or x >= W:
            continue
        a = (dx + FEATHER // 2) / FEATHER
        for y in range(TOP, BOT):
            lp = strip_px(ln, x, y)
            rp = strip_px(rn, x, y)
            canvas.putpixel((x, y), tuple(int(lp[i] * (1 - a) + rp[i] * a) for i in range(3)))
# Ear decals at side-panel centres, ear height y=524
canvas.paste(ear_r, (512 - 60, 524 - 85), mask_r)
canvas.paste(ear_l, (1536 - 60, 524 - 85), mask_l)
top_row = canvas.crop((0, TOP, W, TOP + 1))
canvas.paste(top_row.resize((W, TOP)), (0, 0))
bot_row = canvas.crop((0, BOT - 1, W, BOT))
canvas.paste(bot_row.resize((W, H - BOT)), (0, BOT))
canvas.save(os.path.join(BASE, "zombie-head-wrap.webp"), "WEBP", quality=92)
print("saved zombie-head-wrap.webp, skin tone", skin_tone)
