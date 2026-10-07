#!/usr/bin/env python3
from pathlib import Path

p=Path("PunisherAndroid/app/src/main/assets/index.html")
s=p.read_text(encoding="utf-8")

s=s.replace("Android 0.3.5 (9)","Android 0.3.6 (10)")
s=s.replace("Android 0.3.2 (6)","Android 0.3.6 (10)")

old_css=".vehicle-canvas .vehicle-photo{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;margin:0;z-index:1;filter:saturate(.72) contrast(1.04) drop-shadow(0 10px 14px rgba(0,0,0,.52))}\n.vehicle-color-layer{position:absolute;inset:0;z-index:2;pointer-events:none;-webkit-mask-repeat:no-repeat;-webkit-mask-position:center;-webkit-mask-size:contain;mask-repeat:no-repeat;mask-position:center;mask-size:contain;mix-blend-mode:multiply}"
new_css=".vehicle-canvas .vehicle-photo{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;margin:0;z-index:1;filter:drop-shadow(0 10px 14px rgba(0,0,0,.52))}\n.vehicle-canvas .vehicle-photo.paint-base{filter:grayscale(1) saturate(0) contrast(1.05) brightness(.985) drop-shadow(0 10px 14px rgba(0,0,0,.52))}\n.vehicle-color-layer{position:absolute;inset:0;z-index:2;pointer-events:none;-webkit-mask-repeat:no-repeat;-webkit-mask-position:center;-webkit-mask-size:contain;mask-repeat:no-repeat;mask-position:center;mask-size:contain}\n.vehicle-detail-layer{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;z-index:3;pointer-events:none;filter:grayscale(1) brightness(1.12) contrast(1.25);opacity:.17;mix-blend-mode:screen}"
if old_css not in s:
    raise SystemExit("Color System v2 CSS anchor not found")
s=s.replace(old_css,new_css)

old_stage='''function vehicleStage(v){
  var c=v.colorHex||'#F2F2F2';
  var m=visualMeta(v);
  var opacity=m&&m.colorStrength?Math.max(.86,m.colorStrength):.90;
  var layer=c.toUpperCase()==='#F2F2F2'?'':'<span class="vehicle-color-layer" style="background:'+esc(c)+';opacity:'+opacity+';-webkit-mask-image:url(\\''+imageMask(v)+'\\');mask-image:url(\\''+imageMask(v)+'\\')"></span>';
  return '<div class="vehicle-stage"><div class="vehicle-canvas">'+vehiclePic(v)+layer+(plateText(v)?plateHtml(v,false):'')+'</div></div>'
}'''
new_stage='''function vehicleStage(v){
  var c=v.colorHex||'#F2F2F2';
  var hex=c.toUpperCase();
  var painted=hex!=='#F2F2F2';
  var neutral=(hex==='#161616'||hex==='#A8ADB3'||hex==='#5C6268');
  var mode=neutral?'multiply':'color';
  var opacity=hex==='#161616'?.92:(neutral?.84:.98);
  var base='<img class="vehicle-photo '+(painted?'paint-base':'')+'" src="'+image(v)+'" alt="'+esc(name(v))+'">';
  var layer=painted?'<span class="vehicle-color-layer" style="background:'+esc(c)+';opacity:'+opacity+';mix-blend-mode:'+mode+';-webkit-mask-image:url(\\''+imageMask(v)+'\\');mask-image:url(\\''+imageMask(v)+'\\')"></span>':'';
  var detail=painted?'<img class="vehicle-detail-layer" src="'+image(v)+'" alt="">':'';
  return '<div class="vehicle-stage"><div class="vehicle-canvas">'+base+layer+detail+(plateText(v)?plateHtml(v,false):'')+'</div></div>'
}'''
if old_stage not in s:
    raise SystemExit("Color System v2 vehicleStage anchor not found")
s=s.replace(old_stage,new_stage)

p.write_text(s,encoding="utf-8")
print("patched Color System v2",p)
