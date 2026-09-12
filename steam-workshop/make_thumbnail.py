"""Rebuilds thumbnail.png (Workshop preview) and thumbnail-200px.png (a legibility check
at Steam's listing size, not uploaded). Layout lives in thumbnail_layout.py."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from thumbnail_layout import make

OLD = "/home/nikita/Pictures/Screenshots/Screenshot_20260912_133213.png"  # blurry, vanilla
NEW = "/home/nikita/Pictures/Screenshots/Screenshot_20260912_135317.png"  # sharp, modded
CROP = (1500, 280, 3620, 1133)   # 2120x853, clear of every UI element
OUT = os.path.join(os.path.dirname(__file__), "..", "thumbnail.png")
make(OUT, "SHARP TERRAIN", OLD, NEW, CROP, CROP)
