"""Wrap textures v2. Veteran: true multi-view (tighter crops, no shirt
slivers). Bombie: front photo + cheek-patch skin sides (mirror-tiled,
no ghost face) + rectangular feathered ear patches at correct height +
hair/nape back. No new Bombie angle generations (one refused, not retried)."""
from PIL import Image, ImageFilter
import os

BASE = os.path.expanduser("~/workspace/bombies-dead-zone/assets/faces")
NEW = os.path.join(BASE, "new")
W, H = 2048, 1024
TOP, BOT = 82, 800
PH = BOT - TOP
FEATHER = 48

def load(name):
    p = os.path.join(NEW, name[4:]) if name.startswith("new/") else os.path.join(BASE, name)
    return Image.open(p).convert("RGB")

def crop_frac(im, x0, y0, x1, y1):
    w, h = im.size
    return im.crop((int(w*x0), int(h*y0), int(w*x1), int(h*y1)))

def panel(im, box):
    return crop_frac(im, *box).resize((512, PH), Image.LANCZOS)

def build_wrap(front, right, left, back, out_path, ear_patches=None):
    strips = {"front": front, "right": right, "left": left, "back": back}
    base_col = front.getpixel((256, 500))
    canvas = Image.new("RGB", (W, H), base_col)
    canvas.paste(right, (256, TOP))
    canvas.paste(front, (768, TOP))
    canvas.paste(left, (1280, TOP))
    canvas.paste(back.crop((0, 0, 256, PH)), (1792, TOP))
    canvas.paste(back.crop((256, 0, 512, PH)), (0, TOP))
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
    if ear_patches:
        for (cx, cy, patch) in ear_patches:
            ew, eh = patch.size
            mask = Image.new("L", (ew, eh), 0)
            # feathered rectangle: full alpha inside, gradient at edges
            px = mask.load()
            for mx in range(ew):
                for my in range(eh):
                    d = min(mx, ew - 1 - mx, my, eh - 1 - my, 14)
                    px[mx, my] = int(255 * max(0, d) / 14)
            mask = mask.filter(ImageFilter.GaussianBlur(3))
            canvas.paste(patch, (cx - ew // 2, cy - eh // 2), mask)
    top_row = canvas.crop((0, TOP, W, TOP + 1))
    canvas.paste(top_row.resize((W, TOP)), (0, 0))
    bot_row = canvas.crop((0, BOT - 1, W, BOT))
    canvas.paste(bot_row.resize((W, H - BOT)), (0, BOT))
    canvas.save(out_path, "WEBP", quality=92)
    print("saved", out_path)

def mirror_tile(patch, w=512, h=PH):
    """Tile a small skin patch with mirroring so pores keep scale and
    no hard repetition lines appear."""
    pw, ph = patch.size
    tile = Image.new("RGB", (w, h))
    x = 0
    col = 0
    while x < w:
        y = 0
        row = 0
        while y < h:
            p = patch
            if col % 2 == 1:
                p = p.transpose(Image.FLIP_LEFT_RIGHT)
            if row % 2 == 1:
                p = p.transpose(Image.FLIP_TOP_BOTTOM)
            tile.paste(p, (x, y))
            y += ph
            row += 1
        x += pw
        col += 1
    return tile.filter(ImageFilter.GaussianBlur(1.5))

# ---- Veteran (tighter crops) ----
V_FRONT = load("media-generation-veteran-face-0-7f7a4ff7-7935-4dc1-9970-a00f4d3cb6c3.webp")
V_R = load("new/media-generation-veteran-side-right-0-b23d8c09-5a4c-44db-bc22-01185715e8a1.webp")
V_L = load("new/media-generation-veteran-side-left-0-e69dd877-b638-4065-b30d-71abfd1486a0.webp")
V_B = load("new/media-generation-veteran-back-0-25f8704d-3081-4562-858a-d50cc337c86d.webp")
build_wrap(panel(V_FRONT, (0.12, 0.04, 0.88, 0.80)),
           panel(V_R, (0.05, 0.03, 0.95, 0.82)),
           panel(V_L, (0.05, 0.03, 0.95, 0.82)),
           panel(V_B, (0.12, 0.03, 0.88, 0.80)),
           os.path.join(BASE, "veteran-head-wrap.webp"))

# ---- Bombie (front-derived, no ghost face) ----
Z_FRONT = load("media-generation-bombie-face-0-a0039a1d-4176-45e3-bf6f-b5b7a5ec8e2b.webp")
z_front = panel(Z_FRONT, (0.12, 0.02, 0.88, 0.80))
W0, H0 = Z_FRONT.size
# Cheek patches (featureless pallid skin): person's right cheek =
# image-left; person's left cheek = image-right.
cheek_r = crop_frac(Z_FRONT, 0.22, 0.52, 0.40, 0.72)  # person's right cheek
cheek_l = crop_frac(Z_FRONT, 0.60, 0.52, 0.78, 0.72)  # person's left cheek
z_right = mirror_tile(cheek_r)
z_left = mirror_tile(cheek_l)
# Back: hair top over neck tones
hair = crop_frac(Z_FRONT, 0.12, 0.02, 0.88, 0.14).resize((512, 430), Image.LANCZOS)
neck = crop_frac(Z_FRONT, 0.30, 0.62, 0.70, 0.80).resize((512, 288), Image.LANCZOS)
z_back = Image.new("RGB", (512, PH))
z_back.paste(hair, (0, 0))
z_back.paste(neck, (0, 430))
# Ear patches: tight boxes around the real ears, rectangular feather.
ear_r = crop_frac(Z_FRONT, 0.115, 0.405, 0.215, 0.585).resize((110, 150), Image.LANCZOS)
ear_l = crop_frac(Z_FRONT, 0.785, 0.405, 0.885, 0.585).resize((110, 150), Image.LANCZOS)
# Ear centre y on canvas: photo y 0.495 -> crop (0.02..0.80) -> panel
# y = 82 + ((0.495-0.02)/0.78)*718 = 524
build_wrap(z_front, z_right, z_left, z_back,
           os.path.join(BASE, "zombie-head-wrap.webp"),
           ear_patches=[(512, 524, ear_r), (1536, 524, ear_l)])
print("done")
