#!/usr/bin/env python3
import argparse, json, os, math
import cv2
import numpy as np
from PIL import Image

POSITIVE = {
    "back_bumper","back_door","back_left_door","back_right_door",
    "front_bumper","front_door","front_left_door","front_right_door",
    "hood","left_mirror","right_mirror","tailgate","trunk"
}
NEGATIVE = {
    "back_glass","front_glass",
    "back_left_light","back_light","back_right_light",
    "front_left_light","front_light","front_right_light",
    "wheel"
}

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

def broad_paint_prior(img):
    rgba=np.array(img.convert("RGBA"))
    rgb=rgba[:,:,:3]
    alpha=rgba[:,:,3].astype(np.float32)/255.0
    gray=cv2.cvtColor(rgb,cv2.COLOR_RGB2GRAY).astype(np.float32)
    hsv=cv2.cvtColor(rgb,cv2.COLOR_RGB2HSV)
    sat=hsv[:,:,1].astype(np.float32)

    # Source assets are intentionally white/silver. This prior keeps continuous
    # painted surfaces while de-emphasizing dark glass/tires and colorful lamps.
    light=np.clip((gray-38.0)/115.0,0.0,1.0)
    neutral=np.clip((150.0-sat)/150.0,0.0,1.0)

    gx=cv2.Sobel(gray,cv2.CV_32F,1,0,ksize=3)
    gy=cv2.Sobel(gray,cv2.CV_32F,0,1,ksize=3)
    grad=cv2.magnitude(gx,gy)
    smooth=1.0-0.48*np.clip(grad/120.0,0.0,1.0)

    prior=alpha*np.power(light,0.62)*np.power(neutral,0.35)*smooth
    prior=cv2.GaussianBlur(prior,(0,0),1.4)
    return np.clip(prior,0.0,1.0)

def resize_mask(mask, size):
    w,h=size
    return cv2.resize(mask.astype(np.float32),(w,h),interpolation=cv2.INTER_LINEAR)

def ai_masks(model, image):
    rgb=np.array(image.convert("RGB"))
    result=model.predict(source=rgb,imgsz=640,conf=0.12,iou=0.65,retina_masks=True,verbose=False)[0]
    h,w=rgb.shape[:2]
    pos=np.zeros((h,w),np.float32)
    neg=np.zeros((h,w),np.float32)
    detected=[]

    if result.masks is None or result.boxes is None:
        return pos,neg,detected

    data=result.masks.data.detach().cpu().numpy()
    classes=result.boxes.cls.detach().cpu().numpy().astype(int)
    names=result.names

    for i,cls in enumerate(classes):
        name=str(names[int(cls)])
        m=resize_mask(data[i],(w,h))
        if name in POSITIVE:
            pos=np.maximum(pos,m)
            detected.append("+"+name)
        elif name in NEGATIVE:
            neg=np.maximum(neg,m)
            detected.append("-"+name)

    return np.clip(pos,0,1),np.clip(neg,0,1),detected

def refine_mask(image, prior, pos, neg):
    rgba=np.array(image.convert("RGBA"))
    alpha=rgba[:,:,3].astype(np.float32)/255.0
    gray=cv2.cvtColor(rgba[:,:,:3],cv2.COLOR_RGB2GRAY).astype(np.float32)

    # The AI part model provides hard semantic guidance. The source-image prior
    # fills body regions not represented as explicit classes (roof/fenders).
    score=np.maximum(prior*0.78,pos*0.98)

    # Semantic exclusions are decisive: windows, wheels and lamps stay original.
    score*=np.power(1.0-np.clip(neg,0,1),2.8)

    # Extra safeguard for black rubber/glass when the part model misses an edge.
    dark_guard=np.clip((gray-24.0)/58.0,0.0,1.0)
    score*=0.35+0.65*dark_guard

    # Chrome / grille protection:
    # grilles and chrome have dense local edges and usually low saturation.
    # Body paint is much smoother. Reduce paint alpha in those high-detail,
    # neutral regions without touching large smooth panels.
    hsv=cv2.cvtColor(rgba[:,:,:3],cv2.COLOR_RGB2HSV)
    sat=hsv[:,:,1].astype(np.float32)
    gx=cv2.Sobel(gray,cv2.CV_32F,1,0,ksize=3)
    gy=cv2.Sobel(gray,cv2.CV_32F,0,1,ksize=3)
    edge=np.clip(cv2.magnitude(gx,gy)/120.0,0.0,1.0)
    texture=cv2.GaussianBlur(edge,(0,0),3.0)
    neutral=np.clip((125.0-sat)/125.0,0.0,1.0)
    midtone=np.clip((gray-45.0)/70.0,0.0,1.0)*np.clip((250.0-gray)/70.0,0.0,1.0)
    chrome_guard=np.clip((texture-0.16)/0.28,0.0,1.0)*neutral*(0.45+0.55*midtone)

    # Do not erase explicit semantic body panels completely; only soften
    # textured chrome/grille areas. This keeps doors/hood solid.
    score*=1.0-0.82*chrome_guard*(1.0-0.35*pos)
    score*=alpha

    # Convert to a stable soft paint alpha with continuous panels.
    hard=(score>0.22).astype(np.uint8)*255
    hard=cv2.morphologyEx(hard,cv2.MORPH_CLOSE,np.ones((9,9),np.uint8),iterations=1)
    hard=cv2.morphologyEx(hard,cv2.MORPH_OPEN,np.ones((3,3),np.uint8),iterations=1)

    # Remove tiny isolated chrome/wheel fragments while keeping real body panels.
    num,labels,stats,_=cv2.connectedComponentsWithStats(hard,8)
    clean=np.zeros_like(hard)
    visible=max(1,int(np.count_nonzero(alpha>0.05)))
    for i in range(1,num):
        area=int(stats[i,cv2.CC_STAT_AREA])
        if area>=max(45,int(visible*0.0012)):
            clean[labels==i]=255

    soft=cv2.GaussianBlur(clean,(0,0),1.2).astype(np.float32)/255.0
    # Restore semantic positives inside the clean vehicle alpha.
    soft=np.maximum(soft,pos*0.92)
    soft*=np.power(1.0-neg,3.2)
    soft*=alpha
    return np.clip(soft*255.0,0,255).astype(np.uint8)

def debug_overlay(image, mask):
    rgba=np.array(image.convert("RGBA"))
    rgb=rgba[:,:,:3].astype(np.float32)
    a=(mask.astype(np.float32)/255.0*0.52)[:,:,None]
    red=np.zeros_like(rgb); red[:]=[255,35,35]
    rgba[:,:,:3]=(rgb*(1-a)+red*a).clip(0,255).astype(np.uint8)
    return Image.fromarray(rgba,"RGBA")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--profiles",required=True)
    ap.add_argument("--input-root",required=True)
    ap.add_argument("--mask-root",required=True)
    ap.add_argument("--mode",choices=["xcassets","directory"],required=True)
    ap.add_argument("--debug-dir")
    args=ap.parse_args()

    from huggingface_hub import hf_hub_download
    from ultralytics import YOLO

    weights=hf_hub_download("konst22/yolo11n-carparts-seg","best.pt")
    model=YOLO(weights)

    with open(args.profiles,encoding="utf-8") as f:
        profiles=json.load(f)

    if args.debug_dir:
        os.makedirs(args.debug_dir,exist_ok=True)

    debug_assets={
        "toyota_landcruiser_300",
        "chevrolet_silverado_1500",
        "chevrolet_tahoe",
        "toyota_camry_xv80",
        "hyundai_elantra_cn7"
    }

    done=0
    for p in profiles:
        asset=p["assetKey"]
        img=load_image(args,asset)
        prior=broad_paint_prior(img)
        pos,neg,detected=ai_masks(model,img)
        mask=refine_mask(img,prior,pos,neg)
        save_mask(args,asset,mask)
        done+=1

        coverage=float(np.count_nonzero(mask>20))/mask.size
        semantic=float(np.count_nonzero(pos>0.25))/mask.size
        excluded=float(np.count_nonzero(neg>0.25))/mask.size
        print(f"[AI_PAINT_V3_1 {done:02d}/{len(profiles)}] {asset} coverage={coverage:.3f} positive={semantic:.3f} excluded={excluded:.3f} detections={','.join(detected[:10])}")

        if args.debug_dir and asset in debug_assets:
            debug_overlay(img,mask).save(os.path.join(args.debug_dir,asset+"_paintmask.png"),optimize=True)

    if done!=len(profiles):
        raise SystemExit("AI Paint v3 mask count mismatch")

if __name__=="__main__":
    main()
