#!/usr/bin/env python3
"""Generates the DROPVERSE app icon (1024x1024, no alpha) procedurally."""
import json, math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 4096                      # supersampled canvas
OUT = 1024
CYAN = (25, 240, 255); MAGENTA = (255, 43, 214); VIOLET = (138, 92, 255)
BG = (7, 10, 20); LANE_A = (17, 24, 41); LANE_B = (11, 16, 29); WHITE = (232, 253, 255)
random.seed(7)

def glow(layer, radius):
    return layer.filter(ImageFilter.GaussianBlur(radius))

img = Image.new("RGB", (S, S), BG)
d = ImageDraw.Draw(img)
# piano-roll lanes
lane = S // 26
for i in range(27):
    d.rectangle([0, i * lane, S, (i + 1) * lane], fill=LANE_B if i % 12 in (1, 3, 6, 8, 10) else LANE_A)
    d.line([0, (i + 1) * lane, S, (i + 1) * lane], fill=(26, 35, 64), width=6)
for i in range(17):
    x = i * S // 16
    d.line([x, 0, x, S], fill=(60, 82, 144) if i % 4 == 0 else (36, 50, 90), width=14 if i % 4 == 0 else 6)

# glowing MIDI notes (background)
notes = Image.new("RGB", (S, S), (0, 0, 0))
nd = ImageDraw.Draw(notes)
for k in range(26):
    row = random.randint(1, 24); x = random.randint(-200, S - 300); w = random.choice([256, 512, 768])
    col = CYAN if k % 2 else MAGENTA
    nd.rounded_rectangle([x, row * lane + 18, x + w, row * lane + lane - 18], radius=30, fill=tuple(int(c * 0.55) for c in col))
img = ImageChops.add(img, glow(notes, 40))
img = ImageChops.add(img, notes)

# diagonal light streak
streak = Image.new("RGB", (S, S), (0, 0, 0))
sd = ImageDraw.Draw(streak)
sd.polygon([(0, S * 0.78), (S, S * 0.36), (S, S * 0.5), (0, S * 0.92)], fill=(90, 20, 110))
img = ImageChops.add(img, glow(streak, 120))

# character
cx, cy, side = S // 2, int(S * 0.52), int(S * 0.5)
x0, y0, x1, y1 = cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2
halo = Image.new("RGB", (S, S), (0, 0, 0))
hd = ImageDraw.Draw(halo)
hd.rounded_rectangle([x0 - 60, y0 - 60, x1 + 60, y1 + 60], radius=side // 6, fill=CYAN)
img = ImageChops.add(img, glow(halo, 160))
d = ImageDraw.Draw(img)
# side modules
for mx in (x0 - 150, x1 + 40):
    d.rounded_rectangle([mx, cy - 260, mx + 110, cy + 260], radius=36, fill=MAGENTA)
# body gradient
body = Image.new("RGB", (side, side))
bd = ImageDraw.Draw(body)
for i in range(side):
    t = i / side
    c = tuple(int(a * (1 - t) + b * t) for a, b in zip((11, 22, 48), (70, 20, 90)))
    bd.line([(0, i), (side, i)], fill=c)
mask = Image.new("L", (side, side), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, side, side], radius=side // 7, fill=255)
img.paste(body, (x0, y0), mask)
d = ImageDraw.Draw(img)
d.rounded_rectangle([x0, y0, x1, y1], radius=side // 7, outline=CYAN, width=110)
inset = int(side * 0.1)
d.rounded_rectangle([x0 + inset, y0 + inset, x1 - inset, y1 - inset], radius=side // 12, outline=(200, 60, 180), width=40)

# face (excited "jump" expression)
face = Image.new("RGB", (S, S), (0, 0, 0))
fd = ImageDraw.Draw(face)
ew, eh = int(side * 0.15), int(side * 0.25)
ey = y0 + int(side * 0.4)
for ex in (cx - int(side * 0.17), cx + int(side * 0.17)):
    fd.rounded_rectangle([ex - ew // 2, ey - eh // 2, ex + ew // 2, ey + eh // 2], radius=ew // 2, fill=WHITE)
my = y0 + int(side * 0.66)
fd.ellipse([cx - int(side * 0.13), my - int(side * 0.08), cx + int(side * 0.13), my + int(side * 0.1)], fill=(20, 10, 30), outline=WHITE, width=60)
img = ImageChops.add(img, glow(face.point(lambda v: v * 0.8), 50))
fmask = face.convert("L").point(lambda v: 255 if v > 10 else 0)
img.paste(face, (0, 0), fmask)
d = ImageDraw.Draw(img)
# core
d.ellipse([cx - 70, y1 - inset - 230, cx + 70, y1 - inset - 90], fill=MAGENTA)

# motion trail on the left
trail = Image.new("RGB", (S, S), (0, 0, 0))
td = ImageDraw.Draw(trail)
for i in range(9):
    r = 120 - i * 10; x = x0 - 330 - i * 170; y = cy + 80 + int(math.sin(i * 0.8) * 60)
    td.ellipse([x - r, y - r, x + r, y + r], fill=CYAN if i % 2 == 0 else MAGENTA)
img = ImageChops.add(img, glow(trail, 60))
img = ImageChops.add(img, trail.point(lambda v: v * 0.6))

# spikes at the bottom right (hazard hint)
d = ImageDraw.Draw(img)
base = int(S * 0.93)
for i in range(3):
    sx = int(S * 0.70) + i * 330
    d.polygon([(sx, base), (sx + 300, base), (sx + 150, base - 330)], fill=(60, 8, 30), outline=(255, 59, 107), width=40)
d.rectangle([0, base, S, S], fill=(5, 7, 14))
d.line([0, base, S, base], fill=CYAN, width=36)

icon = img.resize((OUT, OUT), Image.LANCZOS).convert("RGB")
dst = os.path.join(os.path.dirname(__file__), "..", "DROPVERSE", "Resources", "Assets.xcassets", "AppIcon.appiconset")
icon.save(os.path.join(dst, "AppIcon-1024.png"), optimize=True)
json.dump({"images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(dst, "Contents.json"), "w"), indent=2)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(dst, "..", "Contents.json"), "w"), indent=2)
icon.save("/home/claude/AppIcon-preview.png")
print("ok", icon.size, icon.mode)
