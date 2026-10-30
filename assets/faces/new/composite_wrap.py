"""Build 2048x1024 whole-head wrap textures for veteran + bombie.
Layout (u -> x): back 0..256 + 1792..2048, right side 256..768,
front 768..1280, left side 1280..1792. v: head crop -> y 82..800,
top/bottom filled by row extension. Panel boundaries feathered 48px.
Veteran: true front/side/back photos. Bombie: front photo + blurred
skin sides with real ear decals + hair/nape back (no new Bombie angle
generations: one was refused and is not retried).
"""
from PIL import Image, ImageFilter, ImageDraw
import os

BASE = os.path.expanduser("~/workspace/bombies-dead-zone/assets/faces")
NEW = os.path.join(BASE, "new")
W, H = 2048, 1024
TOP, BOT = 82, 800
FEATHER = 48

def load(name):
    return Image.open(os.path.join(BASE, name) if not name.startswith("new/") else os.path.join(NEW, name[4:])).convert("RGB")

def crop_frac(im, x0, y0, x1, y1):
    w, h = im.size
    return im.crop((int(w*x0), int(h*y0), int(w*x1), int(h*y1)))

def panel(im, box):
    c = crop_frac(im, *box)
    return c.resize((512, BOT - TOP), Image.LANCZOS)

def feather_paste(canvas, panel_img, x0):
    """Paste panel at x0..x0+512 with 48px feather on both vertical edges."""
    canvas.paste(panel_img, (x0, TOP))
    # left edge feather: blend with what's already there
    for dx in range(FEATHER):
        a = dx / FEATHER
        x = x0 + dx
        for y in range(TOP, BOT):
            l = canvas.getpixel((x, y))
            # NOTE: paste already overwrote; we blend panel vs underlying by
            # re-reading from a saved copy -- handled by caller via layers.
            pass
    return canvas

def build_wrap(front, right, left, back, out_path, ear_decals=None):
    # Build per-panel full-height strips first (718 tall), then assemble
    # with cross-faded boundaries using strip images.
    strips = {}
    strips["front"] = front
    strips["right"] = right
    strips["left"] = left
    strips["back"] = back  # 512 wide, will be split across seam
    # Canvas: start with skin-tone base (average of front centre)
    base_col = front.getpixel((256, 500))
    canvas = Image.new("RGB", (W, H), base_col)
    # Place strips (y TOP..BOT)
    canvas.paste(strips["right"], (256, TOP))
    canvas.paste(strips["front"], (768, TOP))
    canvas.paste(strips["left"], (1280, TOP))
    canvas.paste(strips["back"].crop((0, 0, 256, BOT - TOP)), (1792, TOP))
    canvas.paste(strips["back"].crop((256, 0, 512, BOT - TOP)), (0, TOP))
    # Feather boundaries by cross-fading neighbouring strips
    bounds = [(256, "back", "right"), (768, "right", "front"),
              (1280, "front", "left"), (1792, "left", "back")]
    # For blending we need strip pixel access by canvas x:
    def strip_px(name, x, y):
        # x: canvas x; y: canvas y in TOP..BOT
        py = y - TOP
        if name == "back":
            sx = (x - 1792) % 512
        elif name == "right":
            sx = x - 256
        elif name == "front":
            sx = x - 768
        else:
            sx = x - 1280
        return strips[name].getpixel((max(0, min(511, sx)), max(0, min(BOT - TOP - 1, py))))
    for bx, ln, rn in bounds:
        for dx in range(-FEATHER // 2, FEATHER // 2):
            x = bx + dx
            if x < 0 or x >= W:
                continue
            a = (dx + FEATHER // 2) / FEATHER  # 0 at left -> 1 at right
            for y in range(TOP, BOT):
                lp = strip_px(ln, x, y)
                rp = strip_px(rn, x, y)
                canvas.putpixel((x, y), tuple(int(lp[i] * (1 - a) + rp[i] * a) for i in range(3)))
    # Ear decals (bombie): paste with soft elliptical alpha mask
    if ear_decals:
        for (panel_cx, ear_img) in ear_decals:
            ew, eh = ear_img.size
            mask = Image.new("L", (ew, eh), 0)
            ImageDraw.Draw(mask).ellipse((0, 0, ew, eh), fill=255)
            mask = mask.filter(ImageFilter.GaussianBlur(8))
            canvas.paste(ear_img, (panel_cx - ew // 2, 441 - eh // 2), mask)
    # Top/bottom extension: nearest row
    top_row = canvas.crop((0, TOP, W, TOP + 1))
    canvas.paste(top_row.resize((W, TOP)), (0, 0))
    bot_row = canvas.crop((0, BOT - 1, W, BOT))
    canvas.paste(bot_row.resize((W, H - BOT)), (0, BOT))
    canvas.save(out_path, "WEBP", quality=92)
    print("saved", out_path, canvas.size)
    return canvas

# ---------------- Veteran: true multi-view ----------------
V_FRONT = load("media-generation-veteran-face-0-7f7a4ff7-7935-4dc1-9970-a00f4d3cb6c3.webp")
V_R = load("new/media-generation-veteran-side-right-0-b23d8c09-5a4c-44db-bc22-01185715e8a1.webp")
V_L = load("new/media-generation-veteran-side-left-0-e69dd877-b638-4065-b30d-71abfd1486a0.webp")
V_B = load("new/media-generation-veteran-back-0-25f8704d-3081-4562-858a-d50cc337c86d.webp")
v_front = panel(V_FRONT, (0.12, 0.04, 0.88, 0.84))
v_right = panel(V_R, (0.05, 0.03, 0.95, 0.85))
v_left = panel(V_L, (0.05, 0.03, 0.95, 0.85))
v_back = panel(V_B, (0.12, 0.03, 0.88, 0.80))
build_wrap(v_front, v_right, v_left, v_back,
           os.path.join(BASE, "veteran-head-wrap.webp"))

# ---------------- Bombie: front-derived ----------------
Z_FRONT = load("media-generation-bombie-face-0-a0039a1d-4176-45e3-bf6f-b5b7a5ec8e2b.webp")
z_front = panel(Z_FRONT, (0.12, 0.02, 0.88, 0.84))
# Side panels: heavily blurred front crop = featureless pallid skin tones
z_side_base = z_front.filter(ImageFilter.GaussianBlur(28))
# Back panel: hair strip (top of front crop) over neck tones
hair = z_front.crop((0, 0, 512, 260)).filter(ImageFilter.GaussianBlur(6))
neck = z_front.crop((0, 560, 512, 718)).filter(ImageFilter.GaussianBlur(24))
z_back = Image.new("RGB", (512, BOT - TOP))
z_back.paste(hair.resize((512, 430)), (0, 0))
z_back.paste(neck.resize((512, 288)), (0, 430))
# Ear decals from the front photo: person's right ear = image-left,
# person's left ear = image-right. Ears at ~y 0.42-0.58 of full photo.
W0, H0 = Z_FRONT.size
ear_r = Z_FRONT.crop((int(W0*0.10), int(H0*0.40), int(W0*0.22), int(H0*0.60))).resize((96, 140), Image.LANCZOS)  # person's right ear
ear_l = Z_FRONT.crop((int(W0*0.78), int(H0*0.40), int(W0*0.90), int(H0*0.60))).resize((96, 140), Image.LANCZOS)  # person's left ear
# Right-side panel centre x=512 (person's right ear), left-side centre x=1536
build_wrap(z_front, z_side_base, z_side_base, z_back,
           os.path.join(BASE, "zombie-head-wrap.webp"),
           ear_decals=[(512, ear_r), (1536, ear_l)])

# Bombie iris -> az/phi for glow placement (front crop 0.12..0.88, 0.02..0.84):
for fx in (0.38, 0.63):
    uc = (fx - 0.12) / 0.76
    x = 768 + uc * 512
    u = x / 2048
    az = (u - 0.5) * 360
    v = (82 + ((0.42 - 0.02) / 0.82) * 718) / 1024
    phi = 90 - v * 180
    print(f"iris fx={fx}: canvas x={x:.0f} u={u:.3f} az={az:.1f} phi={phi:.1f}")
