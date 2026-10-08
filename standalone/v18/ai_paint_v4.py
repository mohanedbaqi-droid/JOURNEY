#!/usr/bin/env python3
import argparse, json, os
import cv2
import numpy as np
from PIL import Image

POSITIVE={
 "back_bumper","back_door","back_left_door","back_right_door",
 "front_bumper","front_door","front_left_door","front_right_door",
 "hood","left_mirror","right_mirror","tailgate","trunk"
}
NEGATIVE={
 "back_glass","front_glass",
 "back_left_light","back_light","back_right_light",
 "front_left_light","front_light","front_right_light",
 "wheel"
}

def load_image(args,asset):
    p=os.path.join(args.input_root,asset+".imageset",asset+".png") if args.mode=="xcassets" else os.path.join(args.input_root,asset+".png")
    return Image.open(p).convert("RGBA")

def save_mask(args,asset,mask):
    rgba=np.zeros((mask.shape[0],mask.shape[1],4),dtype=np.uint8)
    rgba[:,:,:3]=255
    rgba[:,:,3]=mask
    out=Image.fromarray(rgba,"RGBA")
    if args.mode=="xcassets":
        folder=os.path.join(args.mask_root,asset+"_bodymask.imageset"); os.makedirs(folder,exist_ok=True)
        name=asset+"_bodymask.png"; out.save(os.path.join(folder,name),optimize=True)
        with open(os.path.join(folder,"Contents.json"),"w") as f:
            json.dump({"images":[{"filename":name,"idiom":"universal","scale":"1x"},{"idiom":"universal","scale":"2x"},{"idiom":"universal","scale":"3x"}],"info":{"author":"xcode","version":1}},f)
    else:
        os.makedirs(args.mask_root,exist_ok=True)
        out.save(os.path.join(args.mask_root,asset+".png"),optimize=True)

def resize_mask(m,size):
    return cv2.resize(m.astype(np.float32),size,interpolation=cv2.INTER_LINEAR)

def semantic_masks(model,image):
    rgb=np.array(image.convert("RGB"))
    result=model.predict(source=rgb,imgsz=640,conf=.10,iou=.65,retina_masks=True,verbose=False)[0]
    h,w=rgb.shape[:2]
    pos=np.zeros((h,w),np.float32); neg=np.zeros((h,w),np.float32); names_seen=[]
    if result.masks is None or result.boxes is None:return pos,neg,names_seen
    data=result.masks.data.detach().cpu().numpy()
    classes=result.boxes.cls.detach().cpu().numpy().astype(int)
    for i,cls in enumerate(classes):
        name=str(result.names[int(cls)])
        m=resize_mask(data[i],(w,h))
        if name in POSITIVE:
            pos=np.maximum(pos,m); names_seen.append("+"+name)
        elif name in NEGATIVE:
            neg=np.maximum(neg,m); names_seen.append("-"+name)
    return np.clip(pos,0,1),np.clip(neg,0,1),names_seen

def make_hard_body_mask(image,pos,neg):
    rgba=np.array(image.convert("RGBA"))
    rgb=rgba[:,:,:3]
    alpha=rgba[:,:,3].astype(np.float32)/255.
    gray=cv2.cvtColor(rgb,cv2.COLOR_RGB2GRAY).astype(np.float32)
    hsv=cv2.cvtColor(rgb,cv2.COLOR_RGB2HSV)
    sat=hsv[:,:,1].astype(np.float32)

    # Broad source prior: source fleet images are white/silver. We use this only
    # to find the painted silhouette; it is NOT used as the final color.
    brightness=np.clip((gray-28.)/78.,0,1)
    neutral=np.clip((165.-sat)/165.,0,1)
    prior=alpha*np.power(brightness,.45)*np.power(neutral,.24)

    # Strong semantic body inclusion. This expands over complete connected panels
    # so paint is continuous and no white source color can leak through the middle.
    body=np.maximum(prior*.78,pos)
    body*=np.power(1.-neg,4.0)

    # Protect dense chrome/grille texture outside confident semantic paint panels.
    gx=cv2.Sobel(gray,cv2.CV_32F,1,0,ksize=3); gy=cv2.Sobel(gray,cv2.CV_32F,0,1,ksize=3)
    texture=cv2.GaussianBlur(np.clip(cv2.magnitude(gx,gy)/105.,0,1),(0,0),2.4)
    low_sat=np.clip((110.-sat)/110.,0,1)
    chrome=np.clip((texture-.19)/.25,0,1)*low_sat
    body*=1.-.72*chrome*(1.-.55*pos)

    binary=(body>.17).astype(np.uint8)*255
    # Connect hood/doors/fenders as one paint surface.
    binary=cv2.morphologyEx(binary,cv2.MORPH_CLOSE,np.ones((13,13),np.uint8),iterations=2)
    binary=cv2.morphologyEx(binary,cv2.MORPH_OPEN,np.ones((3,3),np.uint8),iterations=1)

    # Remove wheels/windows/lights with a small safety dilation.
    hard_neg=(neg>.18).astype(np.uint8)*255
    hard_neg=cv2.dilate(hard_neg,np.ones((5,5),np.uint8),iterations=1)
    binary[hard_neg>0]=0
    binary[alpha<.06]=0

    # Keep meaningful connected body components.
    n,labels,stats,_=cv2.connectedComponentsWithStats(binary,8)
    cleaned=np.zeros_like(binary)
    visible=max(1,int(np.count_nonzero(alpha>.06)))
    min_area=max(70,int(visible*.001))
    for i in range(1,n):
        if int(stats[i,cv2.CC_STAT_AREA])>=min_area:
            cleaned[labels==i]=255

    # Interior is fully opaque (255) so the original white RGB never blends back.
    # Only a ~1px anti-aliased edge is soft.
    edge=cv2.GaussianBlur(cleaned,(0,0),.65)
    interior=cv2.erode(cleaned,np.ones((3,3),np.uint8),iterations=1)
    edge[interior>0]=255
    edge[alpha<.06]=0
    return edge.astype(np.uint8)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--profiles",required=True); ap.add_argument("--input-root",required=True)
    ap.add_argument("--mask-root",required=True); ap.add_argument("--mode",choices=["xcassets","directory"],required=True)
    args=ap.parse_args()

    from huggingface_hub import hf_hub_download
    from ultralytics import YOLO
    weights=hf_hub_download("konst22/yolo11n-carparts-seg","best.pt")
    model=YOLO(weights)

    with open(args.profiles,encoding="utf-8") as f:profiles=json.load(f)
    for i,p in enumerate(profiles,1):
        asset=p["assetKey"]; img=load_image(args,asset)
        pos,neg,seen=semantic_masks(model,img)
        mask=make_hard_body_mask(img,pos,neg)
        save_mask(args,asset,mask)
        cov=float(np.count_nonzero(mask>245))/mask.size
        print(f"[AI_PAINT_V4 {i:02d}/{len(profiles)}] {asset} opaque={cov:.3f} parts={','.join(seen[:10])}")
    if len(profiles)!=56:raise SystemExit("expected 56 profiles")

if __name__=="__main__":main()
