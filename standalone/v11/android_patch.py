#!/usr/bin/env python3
from pathlib import Path

p = Path("PunisherAndroid/app/src/main/assets/index.html")
s = p.read_text(encoding="utf-8")

s = s.replace("Android 0.3.1 (5)", "Android 0.3.2 (6)")

old_css = ".vehicle-stage{height:238px;position:relative;display:flex;align-items:center;justify-content:center;overflow:visible;margin-top:2px}\n.vehicle-stage .vehicle-photo{height:228px;margin:0;position:relative;z-index:1}\n.vehicle-color-layer{position:absolute;inset:5px 0 5px 0;z-index:2;pointer-events:none;-webkit-mask-repeat:no-repeat;-webkit-mask-position:center;-webkit-mask-size:contain;mask-repeat:no-repeat;mask-position:center;mask-size:contain;opacity:.78;mix-blend-mode:color}"
new_css = ".vehicle-stage{height:238px;position:relative;display:flex;align-items:center;justify-content:center;overflow:visible;margin-top:2px}\n.vehicle-canvas{position:relative;height:228px;width:342px;max-width:100%;aspect-ratio:3/2;flex:none}\n.vehicle-canvas .vehicle-photo{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;margin:0;z-index:1;filter:saturate(.72) contrast(1.04) drop-shadow(0 10px 14px rgba(0,0,0,.52))}\n.vehicle-color-layer{position:absolute;inset:0;z-index:2;pointer-events:none;-webkit-mask-repeat:no-repeat;-webkit-mask-position:center;-webkit-mask-size:contain;mask-repeat:no-repeat;mask-position:center;mask-size:contain;mix-blend-mode:multiply}"
if old_css not in s:
    raise SystemExit("vehicle CSS block not found")
s = s.replace(old_css, new_css)

old_stage = '''function vehicleStage(v){
  var c=v.colorHex||'#F2F2F2';
  var m=visualMeta(v);
  var opacity=m&&m.colorStrength?m.colorStrength:.72;
  var layer=c.toUpperCase()==='#F2F2F2'?'':'<span class="vehicle-color-layer" style="background:'+esc(c)+';opacity:'+opacity+';-webkit-mask-image:url(\\''+imageMask(v)+'\\');mask-image:url(\\''+imageMask(v)+'\\');mix-blend-mode:'+(c.toUpperCase()==='#161616'?'multiply':'color')+'"></span>';
  return '<div class="vehicle-stage">'+vehiclePic(v)+layer+(plateText(v)?plateHtml(v,false):'')+'</div>'
}'''
new_stage = '''function vehicleStage(v){
  var c=v.colorHex||'#F2F2F2';
  var m=visualMeta(v);
  var opacity=m&&m.colorStrength?Math.max(.86,m.colorStrength):.90;
  var layer=c.toUpperCase()==='#F2F2F2'?'':'<span class="vehicle-color-layer" style="background:'+esc(c)+';opacity:'+opacity+';-webkit-mask-image:url(\\''+imageMask(v)+'\\');mask-image:url(\\''+imageMask(v)+'\\')"></span>';
  return '<div class="vehicle-stage"><div class="vehicle-canvas">'+vehiclePic(v)+layer+(plateText(v)?plateHtml(v,false):'')+'</div></div>'
}'''
if old_stage not in s:
    raise SystemExit("vehicleStage function not found")
s = s.replace(old_stage, new_stage)

# The plate is now positioned inside a 3:2 canvas that matches the source image,
# so the metadata percentages refer to the real image rather than the outer card.
s = s.replace(
    ".plate-on-car{position:absolute;left:70%;top:70.5%;transform:translate(-50%,-50%) rotate(-1.5deg);height:22px;min-width:86px;display:flex;direction:ltr;align-items:stretch;background:#fff;color:#050505;border:1px solid #555;border-radius:3px;font:900 8px ui-monospace,monospace;box-shadow:0 1px 4px rgba(0,0,0,.42);overflow:hidden}",
    ".plate-on-car{position:absolute;left:30%;top:68%;transform:translate(-50%,-50%);height:18px;min-width:0;display:flex;direction:ltr;align-items:stretch;background:#fff;color:#050505;border:1px solid #555;border-radius:3px;font:900 7px ui-monospace,monospace;box-shadow:0 1px 4px rgba(0,0,0,.42);overflow:hidden;z-index:4}"
)

p.write_text(s, encoding="utf-8")
print("patched", p)
