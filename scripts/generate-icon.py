#!/usr/bin/env python3
"""Render the Typewriter icon. Requires Pillow; the built icon is checked in."""
from pathlib import Path
import math
import io
import struct
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = Path(__file__).resolve().parents[1] / "Packaging/Typewriter.icns"
im = Image.new("RGBA", (SIZE, SIZE))
mask = Image.new("L", (SIZE, SIZE))
ImageDraw.Draw(mask).rounded_rectangle((67, 54, 957, 944), radius=205, fill=255)
shadow = Image.new("RGBA", im.size)
shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(25)).point(lambda x: x * 3 // 5))
im.alpha_composite(shadow, (0, 20))
base = Image.new("RGBA", im.size)
data = base.load()
for y in range(SIZE):
    for x in range(SIZE):
        h = (1 - y / SIZE) * .58 + (1 - math.hypot((x - 380) / 1000, y / 1100)) * .42
        grain = ((x * 1471 ^ y * 27101) & 7) - 3
        data[x, y] = (int(24 + h * 27 + grain / 2), int(38 + h * 29 + grain / 2), int(33 + h * 27 + grain / 2), 255)
base.putalpha(mask)
im.alpha_composite(base)
draw = ImageDraw.Draw(im)
draw.rounded_rectangle((69, 56, 954, 941), radius=205, outline=(125, 151, 127, 255), width=3)
draw.rounded_rectangle((112, 99, 911, 898), radius=164, outline=(140, 150, 122, 115), width=2)
draw.rounded_rectangle((225, 716, 800, 773), radius=25, fill=(18, 34, 27))
draw.rounded_rectangle((338, 208, 686, 496), radius=22, fill=(21, 35, 28))
draw.rounded_rectangle((350, 197, 674, 479), radius=19, fill=(247, 234, 203))
draw.rounded_rectangle((350, 197, 674, 479), radius=19, outline=(255, 246, 225), width=4)
for y, end in [(260, 604), (302, 627), (344, 569)]:
    draw.rounded_rectangle((400, y, end, y + 8), radius=4, fill=(148, 120, 85))
draw.rounded_rectangle((400, 388, 494, 401), radius=5, fill=(163, 82, 53))
draw.rounded_rectangle((264, 431, 758, 500), radius=31, fill=(20, 32, 26), outline=(98, 118, 101), width=4)
draw.rounded_rectangle((285, 442, 736, 464), radius=10, fill=(70, 90, 76))
draw.polygon([(270, 483),(752, 483),(792, 680),(232, 680)], fill=(245, 223, 183))
draw.rounded_rectangle((228, 659, 796, 736), radius=28, fill=(211, 183, 139), outline=(254, 233, 193), width=5)
draw.rounded_rectangle((248, 682, 776, 716), radius=13, fill=(159, 119, 76))
draw.polygon([(290, 508),(734, 508),(763, 655),(261, 655)], fill=(43, 58, 47))
for y, count, step in [(535, 8, 46), (580, 7, 49), (624, 6, 53)]:
    for i in range(count):
        x = int(512 + (i - (count - 1) / 2) * step)
        draw.rounded_rectangle((x-16, y-13, x+16, y+12), radius=8, fill=(238, 223, 187))
        draw.line((x - 7, y - 4, x + 7, y - 4), fill=(255, 243, 217), width=3)
draw.rounded_rectangle((703, 593, 741, 640), radius=9, fill=(165, 80, 48))
draw.rounded_rectangle((417, 682, 607, 713), radius=10, fill=(235, 211, 171))
blocks = []
for tag, edge in [(b"icp4", 16), (b"icp5", 32), (b"icp6", 64), (b"ic07", 128),
                  (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024)]:
    with io.BytesIO() as stream:
        im.resize((edge, edge), Image.Resampling.LANCZOS).save(stream, format="PNG")
        image = stream.getvalue()
    blocks.append(tag + struct.pack(">I", len(image) + 8) + image)
payload = b"".join(blocks)
OUT.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
