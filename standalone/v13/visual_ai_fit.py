#!/usr/bin/env python3
import argparse, json, os
import cv2
import numpy as np
from PIL import Image


def body_mask(img: Image.Image) -> np.ndarray:
    rgba = np.array(img.convert("RGBA"))
    rgb = rgba[:, :, :3]
    alpha = rgba[:, :, 3]
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    _, sat, val = cv2.split(hsv)

    # Vehicle assets are intentionally sourced as white/silver studio images.
    # Keep painted panels while suppressing glass, grille, tires and deep shadows.
    bright = cv2.inRange(val, 82, 255)
    not_too_saturated = cv2.inRange(sat, 0, 145)
    body = cv2.bitwise_and(bright, not_too_saturated)
    body = cv2.bitwise_and(body, alpha)
    body = cv2.morphologyEx(body, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8), iterations=2)
    body = cv2.morphologyEx(body, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8), iterations=1)
    body = cv2.GaussianBlur(body, (0, 0), 3.4)

    # Preserve panel shading. Very dark regions should not get painted.
    shade = np.clip((gray.astype(np.float32) - 35.0) / 175.0, 0.0, 1.0)
    mask = (body.astype(np.float32) * shade).clip(0, 255).astype(np.uint8)
    return mask


def front_side(rgb, alpha, bbox):
    x0, y0, x1, y1 = bbox
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    edges = cv2.Canny(gray, 55, 145)
    edges[alpha < 20] = 0

    bw = max(1, x1 - x0)
    bh = max(1, y1 - y0)
    ya = int(y0 + bh * 0.25)
    yb = int(y0 + bh * 0.78)
    lx0, lx1 = x0, int(x0 + bw * 0.43)
    rx0, rx1 = int(x0 + bw * 0.57), x1

    def score(a, b):
        roi = edges[ya:yb, a:b]
        if roi.size == 0:
            return 0.0
        density = float(np.count_nonzero(roi)) / roi.size
        # Front fascia usually has many short horizontal/vertical edges.
        gx = cv2.Sobel(gray[ya:yb, a:b], cv2.CV_32F, 1, 0, ksize=3)
        gy = cv2.Sobel(gray[ya:yb, a:b], cv2.CV_32F, 0, 1, ksize=3)
        texture = float(np.mean(np.abs(gx) + np.abs(gy))) / 255.0
        return density * 2.2 + texture

    left = score(lx0, lx1)
    right = score(rx0, rx1)
    return ("left", left, right) if left >= right else ("right", left, right)


def plate_fit(img: Image.Image):
    rgba = np.array(img.convert("RGBA"))
    rgb = rgba[:, :, :3]
    alpha = rgba[:, :, 3]
    H, W = alpha.shape
    ys, xs = np.where(alpha > 20)
    if len(xs) < 100:
        return dict(plateX=0.30, plateY=0.68, plateW=0.18, plateH=0.07,
                    plateAngle=0.0, confidence=0.20, frontSide="unknown")

    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    bw, bh = max(1, x1 - x0), max(1, y1 - y0)
    side, left_score, right_score = front_side(rgb, alpha, (x0, y0, x1, y1))

    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    sat = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)[:, :, 1]
    edges = cv2.Canny(gray, 45, 135)
    edges[alpha < 20] = 0

    if side == "left":
        rx0, rx1 = x0, int(x0 + bw * 0.49)
        target_nx = 0.18
    else:
        rx0, rx1 = int(x0 + bw * 0.51), x1
        target_nx = 0.82
    ry0, ry1 = int(y0 + bh * 0.46), int(y0 + bh * 0.84)

    roi_edges = edges[ry0:ry1, rx0:rx1]
    roi_gray = gray[ry0:ry1, rx0:rx1]
    roi_sat = sat[ry0:ry1, rx0:rx1]

    # Horizontal rectangular structures from edge geometry.
    morph = cv2.dilate(roi_edges, np.ones((2, 3), np.uint8), iterations=1)
    morph = cv2.morphologyEx(morph, cv2.MORPH_CLOSE, np.ones((5, 13), np.uint8), iterations=2)

    # White/silver plate surfaces, when the source image actually contains one.
    bright = cv2.inRange(roi_gray, 145, 255)
    desat = cv2.inRange(roi_sat, 0, 100)
    light_plate = cv2.bitwise_and(bright, desat)
    light_plate = cv2.morphologyEx(light_plate, cv2.MORPH_CLOSE, np.ones((5, 11), np.uint8), iterations=2)
    combined = cv2.bitwise_or(morph, light_plate)

    contours, _ = cv2.findContours(combined, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    best = None
    best_score = -999.0

    for cnt in contours:
        rect = cv2.minAreaRect(cnt)
        (cx, cy), (rw, rh), angle = rect
        if rw < 2 or rh < 2:
            continue
        long_side, short_side = max(rw, rh), min(rw, rh)
        aspect = long_side / max(short_side, 1.0)
        if not 1.8 <= aspect <= 7.2:
            continue

        gx, gy = rx0 + cx, ry0 + cy
        nx_box = (gx - x0) / bw
        ny_box = (gy - y0) / bh
        relw = long_side / bw
        relh = short_side / bh
        if not 0.07 <= relw <= 0.30:
            continue
        if not 0.018 <= relh <= 0.13:
            continue

        ix0 = max(0, int(cx - long_side / 2))
        ix1 = min(roi_edges.shape[1], int(cx + long_side / 2))
        iy0 = max(0, int(cy - short_side / 2))
        iy1 = min(roi_edges.shape[0], int(cy + short_side / 2))
        patch = roi_edges[iy0:iy1, ix0:ix1]
        edge_density = (float(np.count_nonzero(patch)) / patch.size) if patch.size else 0.0

        pos_score = -abs(nx_box - target_nx) * 4.0 - abs(ny_box - 0.66) * 3.2
        aspect_score = -abs(aspect - 4.1) * 0.14
        size_score = -abs(relw - 0.16) * 2.0 - abs(relh - 0.055) * 3.0
        score = pos_score + aspect_score + size_score + edge_density * 2.5
        if score > best_score:
            best_score = score
            best = (gx, gy, long_side, short_side, angle)

    direction_margin = abs(left_score - right_score)
    direction_conf = float(np.clip(0.52 + direction_margin * 1.7, 0.52, 0.92))

    if best is None or best_score < -1.0:
        # No visible source plate: put the virtual Iraqi plate on the real front-bumper zone.
        nx_box = target_nx
        ny_box = 0.66
        gx = x0 + bw * nx_box
        gy = y0 + bh * ny_box
        long_side = bw * 0.155
        short_side = bh * 0.052
        angle = 1.2 if side == "left" else -1.2
        confidence = max(0.46, direction_conf * 0.70)
    else:
        gx, gy, long_side, short_side, angle = best
        if abs(angle) > 12:
            angle = 0.0
        confidence = float(np.clip(0.66 + max(-0.15, best_score) * 0.06, 0.58, 0.95))

    # IMPORTANT: output coordinates are normalized to the FULL 1500x1000 asset canvas.
    # Runtime overlays are therefore placed inside the aspect-fitted image rect, not the outer card.
    return dict(
        plateX=round(float(gx / W), 5),
        plateY=round(float(gy / H), 5),
        plateW=round(float(np.clip(long_side / W * 1.03, 0.075, 0.205)), 5),
        plateH=round(float(np.clip(short_side / H * 1.05, 0.027, 0.085)), 5),
        plateAngle=round(float(np.clip(angle, -7.0, 7.0)), 2),
        confidence=round(confidence, 3),
        frontSide=side,
    )


def load_image(args, asset):
    if args.mode == "xcassets":
        p = os.path.join(args.input_root, asset + ".imageset", asset + ".png")
    else:
        p = os.path.join(args.input_root, asset + ".png")
    return Image.open(p).convert("RGBA")


def alpha_mask_image(mask):
    # Runtime mask APIs on SwiftUI/WebView use alpha, not grayscale luminance.
    # Store the AI segmentation in the PNG alpha channel so black background
    # is truly transparent and only painted body panels receive the new color.
    rgba = np.zeros((mask.shape[0], mask.shape[1], 4), dtype=np.uint8)
    rgba[:, :, 0:3] = 255
    rgba[:, :, 3] = mask
    return Image.fromarray(rgba, "RGBA")


def save_mask(args, asset, mask):
    rendered = alpha_mask_image(mask)
    if args.mode == "xcassets":
        maskset = os.path.join(args.mask_root, asset + "_bodymask.imageset")
        os.makedirs(maskset, exist_ok=True)
        name = asset + "_bodymask.png"
        rendered.save(os.path.join(maskset, name), optimize=True)
        with open(os.path.join(maskset, "Contents.json"), "w") as f:
            json.dump({
                "images": [
                    {"filename": name, "idiom": "universal", "scale": "1x"},
                    {"idiom": "universal", "scale": "2x"},
                    {"idiom": "universal", "scale": "3x"},
                ],
                "info": {"author": "xcode", "version": 1},
            }, f)
    else:
        os.makedirs(args.mask_root, exist_ok=True)
        rendered.save(os.path.join(args.mask_root, asset + ".png"), optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profiles", required=True)
    ap.add_argument("--input-root", required=True)
    ap.add_argument("--mask-root", required=True)
    ap.add_argument("--metadata", required=True)
    ap.add_argument("--mode", choices=["xcassets", "directory"], required=True)
    ap.add_argument("--js")
    args = ap.parse_args()

    with open(args.profiles, encoding="utf-8") as f:
        profiles = json.load(f)

    meta = []
    for i, p in enumerate(profiles, 1):
        asset = p["assetKey"]
        img = load_image(args, asset)
        save_mask(args, asset, body_mask(img))
        fit = plate_fit(img)
        rgba = np.array(img)
        alpha = rgba[:, :, 3]
        visible = rgba[alpha > 20, :3] if np.any(alpha > 20) else rgba[:, :, :3].reshape(-1, 3)
        mean = float(np.mean(visible))
        # Stronger than previous build so silver/gray/red are visibly real paint changes.
        strength = float(np.clip(0.84 + (mean / 255.0) * 0.10, 0.84, 0.94))
        row = {"assetKey": asset, **fit, "colorStrength": round(strength, 3)}
        meta.append(row)
        print(f"[{i:02d}/{len(profiles)}] {asset} front={row['frontSide']} plate=({row['plateX']:.3f},{row['plateY']:.3f}) conf={row['confidence']:.2f}")

    with open(args.metadata, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    if args.js:
        with open(args.js, "w", encoding="utf-8") as f:
            f.write("window.VEHICLE_VISUAL_AI=")
            json.dump(meta, f, ensure_ascii=False, separators=(",", ":"))
            f.write(";")

    if len(meta) != len(profiles):
        raise SystemExit("visual AI metadata count mismatch")


if __name__ == "__main__":
    main()
