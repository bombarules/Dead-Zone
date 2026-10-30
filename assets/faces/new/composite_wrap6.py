"""Zombie wrap v6: TRUE side profiles. The v5 side panels were blurred
neck skin + a small keyed ear decal, which read as a blank ball from
the side (ear too small/pale, no cheek/jaw/profile structure). This
version pastes a generated true left-profile photo of the same gaunt
man into the left panel as-is, and mirrored into the right panel
(viewed from -X, the nose must point screen-right). Front + back as v5.
No ear decals: the profile carries its own large detailed ear."""
from PIL import Image, ImageFilter
import os

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

Z = load("media-generation-bombie-face-0-a0039a1d-4176-45e3-bf6f-b5b7a5ec8e2b.webp")
P = load("new/media-generation-bombie-side-profile-0-607fc243-add2-4a6e-aa09-4181c0ae0ab2.webp")
z_front = panel(Z, (0.12, 0.02, 0.88, 0.80))
neck_patch = crop_frac(Z, 0.35, 0.83, 0.65, 0.93)
skin_tone = neck_patch.resize((1, 1)).getpixel((0, 0))
# Back: hair over nape (as v5)
hair = crop_frac(Z, 0.30, 0.02, 0.70, 0.13).resize((512, 430), Image.LANCZOS)
nape = neck_patch.resize((512, 288), Image.LANCZOS)
z_back = Image.new("RGB", (512, PH))
z_back.paste(hair, (0, 0))
z_back.paste(nape, (0, 430))
# Side panels from the true profile: crop tight around the head
# (nose tip ~x0.15, hair back ~x0.88, crown ~y0.03, neck ~y0.85).
prof = crop_frac(P, 0.13, 0.02, 0.92, 0.85).resize((512, PH), Image.LANCZOS)
prof_mirror = prof.transpose(Image.FLIP_LEFT_RIGHT)
# Left panel (+X side, viewed from +X, nose points screen-left):
# profile as-is. Right panel (-X side): mirrored.
strips = {"front": z_front, "right": prof_mirror, "left": prof, "back": z_back}
canvas = Image.new("RGB", (W, H), skin_tone)
canvas.paste(prof_mirror, (256, TOP))
canvas.paste(z_front, (768, TOP))
canvas.paste(prof, (1280, TOP))
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
top_row = canvas.crop((0, TOP, W, TOP + 1))
canvas.paste(top_row.resize((W, TOP)), (0, 0))
bot_row = canvas.crop((0, BOT - 1, W, BOT))
canvas.paste(bot_row.resize((W, H - BOT)), (0, BOT))
canvas.save(os.path.join(BASE, "zombie-head-wrap.webp"), "WEBP", quality=92)
print("saved zombie-head-wrap v6 (true profiles)")
