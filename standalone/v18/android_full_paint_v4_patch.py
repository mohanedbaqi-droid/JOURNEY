#!/usr/bin/env python3
from pathlib import Path
import re

p=Path("PunisherAndroid/app/src/main/assets/index.html")
s=p.read_text(encoding="utf-8")

s=s.replace("Android 0.4.0 (11)","Android 0.4.2 (13)")
s=s.replace("Android 0.3.2 (6)","Android 0.4.2 (13)")

# Natural plate size: metadata from dedicated plate detector owns width/height.
s=s.replace("height:23px;min-width:92px","height:auto;min-width:0")
s=s.replace("font:1000 11.5px/1","font:1000 8.5px/1")
s=s.replace("font-size:5.4px","font-size:4.6px")
s=s.replace("font-size:11.8px","font-size:8.8px")

old=r'''async function paintCanvas\(canvas\)\{.*?\n\}
function paintVehicleCanvases'''
new=r'''async function paintCanvas(canvas){
  var src=canvas.dataset.image,maskSrc=canvas.dataset.mask,color=(canvas.dataset.color||'#F2F2F2').toUpperCase();
  if(!src)return;
  var key=src+'|v4|'+maskSrc+'|'+color;
  var ctx=canvas.getContext('2d',{willReadFrequently:true});
  canvas.width=750;canvas.height=500;
  if(paintBitmapCache[key]){
    try{
      var cached=await loadPaintImage(paintBitmapCache[key]);
      ctx.clearRect(0,0,750,500);ctx.drawImage(cached,0,0,750,500);return
    }catch(e){}
  }
  try{
    var base=await loadPaintImage(src);
    ctx.clearRect(0,0,750,500);ctx.drawImage(base,0,0,750,500);
    if(color==='#F2F2F2'||!maskSrc){
      paintBitmapCache[key]=canvas.toDataURL('image/png');return
    }

    var baseData=ctx.getImageData(0,0,750,500);
    var off=document.createElement('canvas');off.width=750;off.height=500;
    var ox=off.getContext('2d',{willReadFrequently:true});
    var mask=await loadPaintImage(maskSrc);
    ox.clearRect(0,0,750,500);ox.drawImage(mask,0,0,750,500);
    var maskData=ox.getImageData(0,0,750,500);

    var d=baseData.data,m=maskData.data,t=paintRGB(color);
    var black=color==='#161616',silver=color==='#A8ADB3',gray=color==='#5C6268';

    for(var i=0;i<d.length;i+=4){
      var ma=m[i+3]/255;
      if(ma<.01)continue;

      // Source RGB is NOT blended into painted pixels. We retain only luminance.
      var r=d[i],g=d[i+1],b=d[i+2];
      var lum=(.2126*r+.7152*g+.0722*b)/255;
      lum=Math.max(0,Math.min(1,(lum-.05)*1.10));

      var shadow=black?.22:(gray?.22:(silver?.36:.14));
      var high=black?1.65:(gray?1.22:(silver?1.16:1.20));
      var lift=black?.025:(silver?.06:.015);
      var gain=shadow+(high-shadow)*Math.pow(lum,.92);

      var pr=clamp255(t[0]*gain+255*lift*Math.pow(lum,2.2));
      var pg=clamp255(t[1]*gain+255*lift*Math.pow(lum,2.2));
      var pb=clamp255(t[2]*gain+255*lift*Math.pow(lum,2.2));

      // Hard AI body mask means ma≈1 through the panel interior; original
      // white paint cannot show underneath. Soft alpha exists only at edges.
      d[i]=clamp255(pr*ma+r*(1-ma));
      d[i+1]=clamp255(pg*ma+g*(1-ma));
      d[i+2]=clamp255(pb*ma+b*(1-ma));
    }
    ctx.putImageData(baseData,0,0);
    paintBitmapCache[key]=canvas.toDataURL('image/png')
  }catch(e){
    try{var fallback=await loadPaintImage(src);ctx.drawImage(fallback,0,0,750,500)}catch(_){}
  }
}
function paintVehicleCanvases'''
s,n=re.subn(old,new,s,count=1,flags=re.S)
if n!=1:
    raise SystemExit("AI Paint v4 canvas function not found")

# Do not force a huge plate. Dedicated detector metadata controls it.
s=s.replace("var plateW=Math.max(.235,Number(m.plateW||.235));","var plateW=Math.max(.045,Number(m.plateW||.10));")
s=s.replace("var plateH=Math.max(.080,Number(m.plateH||.080));","var plateH=Math.max(.018,Number(m.plateH||.028));")

p.write_text(s,encoding="utf-8")
print("patched Full Paint Replacement + natural plate sizing",p)
