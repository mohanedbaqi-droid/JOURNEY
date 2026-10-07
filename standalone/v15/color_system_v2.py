#!/usr/bin/env python3
import argparse, json, os
import cv2
import numpy as np
from PIL import Image

def load_image(args, asset):
    if args.mode == "xcassets":
        path=os.path.join(args.input_root, asset+".imageset", asset+".png")
    else:
        path=os.path.join(args.input_root, asset+".png")
    return Image.open(path).convert("RGBA")

def save_mask(args, asset, alpha_mask):
    rgba=np.zeros((alpha_mask.shape[0],alpha_mask.shape[1],4),dtype=np.uint8)
    rgba[:,:,:3]=255
    rgba[:,:,3]=alpha_mask
    out=Image.fromarray(rgba,"RGBA")
    if args.mode=="xcassets":
        folder=os.path.join(args.mask_root,asset+"_bodymask.imageset")
        os.makedirs(folder,exist_ok=True)
        name=asset+"_bodymask.png"
        out.save(os.path.join(folder,name),optimize=True)
        with open(os.path.join(folder,"Contents.json"),"w") as f:
            json.dump({
                "images":[
                    {"filename":name,"idiom":"universal","scale":"1x"},
                    {"idiom":"universal","scale":"2x"},
                    {"idiom":"universal","scale":"3x"}
                ],
                "info":{"author":"xcode","version":1}
            },f)
    else:
        os.makedirs(args.mask_root,exist_ok=True)
        out.save(os.path.join(args.mask_root,asset+".png"),optimize=True)

def full_body_shadow_mask(img):
    rgba=np.array(img.convert("RGBA"))
    rgb=rgba[:,:,:3]
    alpha=rgba[:,:,3].astype(np.float32)/255.0
    gray=cv2.cvtColor(rgb,cv2.COLOR_RGB2GRAY).astype(np.float32)

    # Color System v2:
    # use the whole visible vehicle silhouette as the base, but fade out very
    # dark glass/tires/grille. This is deliberately much broader than the
    # previous "paint-panel detector" so the selected color covers the body
    # continuously instead of appearing in patches.
    weight=np.clip((gray-24.0)/82.0,0.0,1.0)
    weight=np.power(weight,0.72)

    mask=(alpha*weight*255.0).astype(np.uint8)

    # Fill small gaps inside painted panels while keeping large dark windows
    # and tires excluded.
    support=((mask>24).astype(np.uint8)*255)
    support=cv2.morphologyEx(support,cv2.MORPH_CLOSE,np.ones((9,9),np.uint8),iterations=1)
    support=cv2.GaussianBlur(support,(0,0),2.0).astype(np.float32)/255.0

    mask=np.maximum(mask.astype(np.float32), support*alpha*210.0)
    mask=cv2.GaussianBlur(np.clip(mask,0,255).astype(np.uint8),(0,0),1.3)
    return mask

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--profiles",required=True)
    ap.add_argument("--input-root",required=True)
    ap.add_argument("--mask-root",required=True)
    ap.add_argument("--mode",choices=["xcassets","directory"],required=True)
    args=ap.parse_args()

    with open(args.profiles,encoding="utf-8") as f:
        profiles=json.load(f)

    done=0
    for p in profiles:
        asset=p["assetKey"]
        img=load_image(args,asset)
        mask=full_body_shadow_mask(img)
        save_mask(args,asset,mask)
        done+=1
        coverage=float(np.count_nonzero(mask>18))/mask.size
        print(f"[COLOR_V2 {done:02d}/{len(profiles)}] {asset} coverage={coverage:.3f}")

    if done!=len(profiles):
        raise SystemExit("mask count mismatch")

if __name__=="__main__":
    main()
