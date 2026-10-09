#!/usr/bin/env python3
"""Regression tests for paint masks: glass stays original, paint remains solid."""
from pathlib import Path
import importlib.util
import numpy as np
from PIL import Image

source = Path(__file__).resolve().parents[1] / "v20" / "ai_paint_v4_2.py"
spec = importlib.util.spec_from_file_location("punisher_paint", source)
paint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paint)

# An intentionally over-broad detector labels the entire white car as paint,
# including its dark upper windows. A zero negative mask simulates a model
# that never identified glass in the scene.
h, w = 320, 640
pixels = np.zeros((h, w, 4), dtype=np.uint8)
pixels[45:270, 40:605] = (242, 242, 242, 255)
pixels[75:143, 200:460] = (72, 76, 84, 255)    # side glass
pixels[201:239, 250:410] = (85, 85, 85, 255)    # lower body shadow
image = Image.fromarray(pixels, "RGBA")
pos = np.zeros((h, w), dtype=np.float32)
pos[45:270, 40:605] = .99
neg = np.zeros_like(pos)
mask = paint.make_hard_body_mask(image, pos, neg)

assert mask[108, 310] == 0, f"side window recolored: {mask[108,310]}"
assert mask[182, 310] > 245, f"paint lost: {mask[182,310]}"
assert mask[218, 310] > 245, f"lower body shadow lost: {mask[218,310]}"
assert mask[12, 12] == 0, "transparent background recolored"
empty_mask = paint.make_hard_body_mask(image, np.zeros_like(pos), neg)
assert empty_mask.max() == 0, "unknown segmentation must preserve photograph"
print("PASS: side glass, painted panels, lower shadows, transparency and no-detection fallback")
