#!/usr/bin/env python3
import argparse,json,os
import numpy as np
from PIL import Image

def load(args,asset):
    p=os.path.join(args.input_root,asset+".imageset",asset+".png") if args.mode=="xcassets" else os.path.join(args.input_root,asset+".png")
    return Image.open(p).convert("RGBA")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--profiles",required=True);ap.add_argument("--input-root",required=True)
    ap.add_argument("--metadata",required=True);ap.add_argument("--mode",choices=["xcassets","directory"],required=True)
    ap.add_argument("--js")
    args=ap.parse_args()

    from huggingface_hub import hf_hub_download
    from ultralytics import YOLO
    weights=hf_hub_download("Koushim/yolov8-license-plate-detection","best.pt")
    model=YOLO(weights)

    with open(args.profiles,encoding="utf-8") as f:profiles=json.load(f)
    with open(args.metadata,encoding="utf-8") as f:meta=json.load(f)
    by={x["assetKey"]:x for x in meta}

    for i,p in enumerate(profiles,1):
        asset=p["assetKey"];img=load(args,asset)
        W,H=img.size
        result=model.predict(source=np.array(img.convert("RGB")),imgsz=640,conf=.08,iou=.5,verbose=False)[0]
        candidates=[]
        if result.boxes is not None:
            boxes=result.boxes.xyxy.detach().cpu().numpy()
            confs=result.boxes.conf.detach().cpu().numpy()
            for box,cf in zip(boxes,confs):
                x0,y0,x1,y1=map(float,box)
                w=x1-x0;h=y1-y0
                if w<=2 or h<=2:continue
                ratio=w/h
                cx=(x0+x1)/2;cy=(y0+y1)/2
                # A plate should be horizontal and live in the lower body half.
                if not (1.6<=ratio<=8.5):continue
                if cy < H*.40:continue
                score=float(cf)+min(w*h/(W*H)*10,.25)+min(cy/H,.85)*.08
                candidates.append((score,cf,cx,cy,w,h))
        row=by.get(asset,{})
        if candidates:
            candidates.sort(reverse=True,key=lambda x:x[0])
            _,cf,cx,cy,w,h=candidates[0]
            # Use the detector rectangle itself: natural size + natural location.
            row["plateX"]=round(cx/W,5);row["plateY"]=round(cy/H,5)
            row["plateW"]=round(float(np.clip(w/W*.98,.045,.18)),5)
            row["plateH"]=round(float(np.clip(h/H*.98,.018,.070)),5)
            row["plateAngle"]=0.0
            row["confidence"]=round(float(max(row.get("confidence",0),cf)),3)
            row["plateSource"]="yolo-license-plate"
            print(f"[PLATE_AI {i:02d}/56] {asset} detected x={row['plateX']:.3f} y={row['plateY']:.3f} w={row['plateW']:.3f} h={row['plateH']:.3f} conf={cf:.2f}")
        else:
            # Keep the direction-aware bumper fallback but shrink it to realistic plate proportions.
            row["plateW"]=round(float(np.clip(row.get("plateW",.11),.055,.145)),5)
            target_h=row["plateW"]/4.2
            row["plateH"]=round(float(np.clip(target_h,.018,.050)),5)
            row["plateSource"]="bumper-fallback"
            print(f"[PLATE_AI {i:02d}/56] {asset} fallback")
        by[asset]=row

    out=[by[p["assetKey"]] for p in profiles]
    with open(args.metadata,"w",encoding="utf-8") as f:json.dump(out,f,ensure_ascii=False,indent=2)
    if args.js:
        with open(args.js,"w",encoding="utf-8") as f:
            f.write("window.VEHICLE_VISUAL_AI=");json.dump(out,f,ensure_ascii=False,separators=(",",":"));f.write(";")

if __name__=="__main__":main()
