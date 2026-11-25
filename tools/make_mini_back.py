"""Generate Media/Notifications/mini_back.tga: the dark fill that sits exactly
inside the mini notification frame (mini_frame.tga).

Everything not reachable from the image edge through transparent pixels is
treated as "inside the frame" and painted with the background colour, so the
fill reaches the gold lines and never sticks out past the end caps.
Run: python3 tools/make_mini_back.py
"""
from collections import deque
from PIL import Image

SRC = "Media/Notifications/mini_frame.tga"
DST = "Media/Notifications/mini_back.tga"
COLOR = (0x1B, 0x18, 0x15, 248)  # theme background, ~0.97 alpha
THRESHOLD = 24  # alpha at or above this counts as part of the frame

frame = Image.open(SRC).convert("RGBA")
w, h = frame.size
px = frame.load()

outside = set()
queue = deque()
for x in range(w):
    for y in (0, h - 1):
        if px[x, y][3] < THRESHOLD:
            outside.add((x, y)); queue.append((x, y))
for y in range(h):
    for x in (0, w - 1):
        if px[x, y][3] < THRESHOLD and (x, y) not in outside:
            outside.add((x, y)); queue.append((x, y))
while queue:
    x, y = queue.popleft()
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in outside \
                and px[nx, ny][3] < THRESHOLD:
            outside.add((nx, ny)); queue.append((nx, ny))

back = Image.new("RGBA", (w, h), (0, 0, 0, 0))
bp = back.load()
for y in range(h):
    for x in range(w):
        if (x, y) not in outside:
            bp[x, y] = COLOR
back.save(DST, compression=None)
print("wrote", DST)
