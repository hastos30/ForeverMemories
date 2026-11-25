#!/usr/bin/env python3
"""Draws the 9-slice borders of the Discovery and Legendary notifications
(v1.0.0-beta.9): an octagon with cut corners, a gold outer line, a thin
inner line and the dark background inside, so the card needs no square
backdrop. 64 x 64, corner 16 px (Notifications.lua: W.NineSlice(..., 64, 16, ...)).
Run from the addon root: python3 tools/make_borders.py
"""
from PIL import Image, ImageDraw

SIZE, SS = 64, 8            # texture size, supersampling
CUT = 10                    # corner cut, texture px
BG = (0x1B, 0x18, 0x15, 248)

def octagon(inset, cut):
    a, b = inset, SIZE - inset
    c = cut
    return [(a + c, a), (b - c, a), (b, a + c), (b, b - c), (b - c, b), (a + c, b), (a, b - c), (a, b - c), (a, a + c)]

def draw(path, outer, inner, outer_w, inner_w):
    big = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    s = lambda pts: [(x * SS, y * SS) for x, y in pts]
    d.polygon(s(octagon(1, CUT)), fill=BG)
    d.line(s(octagon(1 + outer_w / 2, CUT)) + s(octagon(1 + outer_w / 2, CUT))[:1], fill=outer, width=int(outer_w * SS), joint="curve")
    d.line(s(octagon(5, CUT - 1.5)) + s(octagon(5, CUT - 1.5))[:1], fill=inner, width=int(inner_w * SS), joint="curve")
    img = big.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(path)

draw("Media/Notifications/discovery_border_9slice.tga", (0xD0, 0xAB, 0x70, 255), (0x8A, 0x6E, 0x45, 200), 2, 1)
draw("Media/Notifications/legendary_border_9slice.tga", (0xE6, 0xB4, 0x5E, 255), (0xB1, 0x86, 0x3E, 230), 2.5, 1.2)
