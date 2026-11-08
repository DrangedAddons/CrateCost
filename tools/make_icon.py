"""CrateCost icon: Wowhead's 56x56 racial_dwarf_findtreasure (the game's Merchant's Favor
currency icon) scaled up like HoTForecast's and CraftRoute's.

Usage: python tools/make_icon.py <racial_dwarf_findtreasure.jpg>
  source: https://wow.zamimg.com/images/wow/icons/large/racial_dwarf_findtreasure.jpg

Writes icon.tga (64x64, Lanczos + light unsharp mask; the .toc IconTexture) and icon.ico
(64/48/32/16, RGBA so the DrangedAddons manager's WPF decoder accepts it).
"""
import os
import sys

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

src = Image.open(sys.argv[1]).convert("RGBA")
big = src.resize((64, 64), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
big.save(os.path.join(ROOT, "icon.tga"))
big.save(os.path.join(ROOT, "icon.ico"), sizes=[(64, 64), (48, 48), (32, 32), (16, 16)])
print("wrote icon.tga and icon.ico")
