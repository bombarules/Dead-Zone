"""Zombie wrap v4: NO mirror tiling anywhere. Side panels = hair top
+ blurred stretched neck skin (smooth pallid tones, no features, no
symmetric artifacts) + keyed real-ear decals. Front + back as v3."""
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

def key_ear(crop_img, skin_tone, size=(120, 170)):
    im = crop_img.resize(size, Image.LANCZOS)
    w, h = size
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
            md[x, y] = 255 if r <= 0.7 else max(0, int(255 * (1 - (r - 0.7) / 0.3)))
    return out, mask.filter(ImageFilter.GaussianBlur(4))

Z = load("media-generation-bombie-face-0-a0039a1d-4176-45e3-bf6f-b5b7a5ec8e2b.webp")
z_front = panel(Z, (0.12, 0.02, 0.88, 0.80))
neck_patch = crop_frac(Z, 0.35, 0.83, 0.65, 0.93)
skin_tone = neck_patch.resize((1, 1)).getpixel((0, 0))
# Side panel: hair top (250px) + smooth neck skin below (468px)
hair_top = crop_frac(Z, 0.30, 0.02, 0.70, 0.13).resize((512, 250), Image.LANCZOS)
neck_skin = neck_patch.resize((512, 468), Image.LANCZOS).filter(ImageFilter.GaussianBlur(7))
z_side = Image.new("RGB", (512, PH))
z_side.paste(hair_top, (0, 0))
z_side.paste(neck_skin, (0, 250))
# feather the hair/skin join
for dy in range(-16, 16):
    y = 250 + dy
    a = (dy + 16) / 32
    for x in range(512):
        hp = hair_top.getpixel((x, min(249, y))) if y < 250 else None
        np_ = neck_skin.getpixel((x, y - 250)) if y >= 250 else None
        if y < 250:
            # blend hair row y with neck row 0
            n0 = neck_skin.getpixel((x, 0))
            z_side.putpixel((x, y), tuple(int(hair_top.getpixel((x, y))[i] * (1 - a) + n0[i] * a) for i in range(3)))
        else:
            hlast = hair_top.getpixel((x, 249))
            z_side.putpixel((x, y), tuple(int(hlast[i] * (1 - a) + neck_skin.getpixel((x, y - 250))[i] * a) for i in range(3)))
# Back: hair over nape (plain resizes, no tiling)
hair = crop_frac(Z, 0.30, 0.02, 0.70, 0.13).resize((512, 430), Image.LANCZOS)
nape = neck_patch.resize((512, 288), Image.LANCZOS)
z_back = Image.new("RGB", (512, PH))
z_back.paste(hair, (0, 0))
z_back.paste(nape, (0, 430))

ear_r, mask_r = key_ear(crop_frac(Z, 0.185, 0.41, 0.265, 0.58), skin_tone)
ear_l, mask_l = key_ear(crop_frac(Z, 0.735, 0.41, 0.815, 0.58), skin_tone)

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
canvas.paste(ear_r, (512 - 60, 524 - 85), mask_r)
canvas.paste(ear_l, (1536 - 60, 524 - 85), mask_l)
top_row = canvas.crop((0, TOP, W, TOP + 1))
canvas.paste(top_row.resize((W, TOP)), (0, 0))
bot_row = canvas.crop((0, BOT - 1, W, BOT))
canvas.paste(bot_row.resize((W, H - BOT)), (0, BOT))
canvas.save(os.path.join(BASE, "zombie-head-wrap.webp"), "WEBP", quality=92)
print("saved zombie-head-wrap v4")
