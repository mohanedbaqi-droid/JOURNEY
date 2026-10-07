#!/usr/bin/env python3
from pathlib import Path

p=Path("PunisherAndroid/app/src/main/assets/index.html")
s=p.read_text(encoding="utf-8")

s=s.replace("Android 0.3.6 (10)","Android 0.4.0 (11)")
s=s.replace("Android 0.3.2 (6)","Android 0.4.0 (11)")

old_css=".vehicle-canvas .vehicle-photo{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;margin:0;z-index:1;filter:drop-shadow(0 10px 14px rgba(0,0,0,.52))}\n.vehicle-canvas .vehicle-photo.paint-base{filter:grayscale(1) saturate(0) contrast(1.05) brightness(.985) drop-shadow(0 10px 14px rgba(0,0,0,.52))}\n.vehicle-color-layer{position:absolute;inset:0;z-index:2;pointer-events:none;-webkit-mask-repeat:no-repeat;-webkit-mask-position:center;-webkit-mask-size:contain;mask-repeat:no-repeat;mask-position:center;mask-size:contain}\n.vehicle-detail-layer{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;z-index:3;pointer-events:none;filter:grayscale(1) brightness(1.12) contrast(1.25);opacity:.17;mix-blend-mode:screen}"
new_css=".vehicle-canvas .paint-canvas{position:absolute;inset:0;width:100%;height:100%;z-index:1;filter:drop-shadow(0 10px 14px rgba(0,0,0,.52))}"
if old_css not in s:
    raise SystemExit("AI Paint v3 CSS anchor not found")
s=s.replace(old_css,new_css)

anchor="function imageMask(v){var p=profile(v);return p?'vehicle_masks/'+encodeURIComponent(p.assetKey)+'.png':''}"
helpers=r'''function imageMask(v){var p=profile(v);return p?'vehicle_masks/'+encodeURIComponent(p.assetKey)+'.png':''}
var paintBitmapCache={};
var paintImagePromiseCache={};
function loadPaintImage(src){
  if(paintImagePromiseCache[src])return paintImagePromiseCache[src];
  paintImagePromiseCache[src]=new Promise(function(resolve,reject){
    var im=new Image();
    im.onload=function(){resolve(im)};
    im.onerror=reject;
    im.src=src
  });
  return paintImagePromiseCache[src]
}
function paintRGB(hex){
  var h=String(hex||'#F2F2F2').replace('#','');
  if(h.length===3)h=h.split('').map(function(x){return x+x}).join('');
  var n=parseInt(h,16);
  return [(n>>16)&255,(n>>8)&255,n&255]
}
function clamp255(x){return x<0?0:(x>255?255:x)}
async function paintCanvas(canvas){
  var src=canvas.dataset.image,maskSrc=canvas.dataset.mask,color=(canvas.dataset.color||'#F2F2F2').toUpperCase();
  if(!src)return;
  var key=src+'|'+maskSrc+'|'+color;
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
    ctx.clearRect(0,0,750,500);
    ctx.drawImage(base,0,0,750,500);
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
    var black=color==='#161616', silver=(color==='#A8ADB3'||color==='#5C6268');
    for(var i=0;i<d.length;i+=4){
      var ma=m[i+3]/255;
      if(ma<.015)continue;
      var r=d[i],g=d[i+1],b=d[i+2];
      var lum=(.2126*r+.7152*g+.0722*b)/255;
      var shade=.20+.88*Math.pow(Math.max(0,Math.min(1,lum)),.86);
      var spec=Math.pow(Math.max(0,(lum-.70)/.30),1.45);
      var specGain=black?.58:(silver?.44:.36);
      var pr=t[0]*shade+(255-t[0])*spec*specGain;
      var pg=t[1]*shade+(255-t[1])*spec*specGain;
      var pb=t[2]*shade+(255-t[2])*spec*specGain;
      if(silver){
        var gl=(pr+pg+pb)/3;
        pr=pr*.30+gl*.70;pg=pg*.30+gl*.70;pb=pb*.30+gl*.70
      }
      d[i]=clamp255(r*(1-ma)+pr*ma);
      d[i+1]=clamp255(g*(1-ma)+pg*ma);
      d[i+2]=clamp255(b*(1-ma)+pb*ma)
    }
    ctx.putImageData(baseData,0,0);
    paintBitmapCache[key]=canvas.toDataURL('image/png')
  }catch(e){
    try{var fallback=await loadPaintImage(src);ctx.drawImage(fallback,0,0,750,500)}catch(_){}
  }
}
function paintVehicleCanvases(){
  document.querySelectorAll('canvas.paint-canvas').forEach(function(c){paintCanvas(c)})
}'''
if anchor not in s:
    raise SystemExit("imageMask anchor not found")
s=s.replace(anchor,helpers)

new_stage='''function vehicleStage(v){
  var c=v.colorHex||'#F2F2F2';
  var canvas='<canvas class="paint-canvas" data-image="'+image(v)+'" data-mask="'+imageMask(v)+'" data-color="'+esc(c)+'"></canvas>';
  return '<div class="vehicle-stage"><div class="vehicle-canvas">'+canvas+(plateText(v)?plateHtml(v,false):'')+'</div></div>'
}'''
s,n=re.subn(r"function vehicleStage\(v\)\{.*?\n\}(?=\nfunction updateHeader)",lambda m:new_stage,s,count=1,flags=re.S)
if n!=1:
    raise SystemExit("AI Paint v3 vehicleStage regex anchor not found")

old_render="function render(){updateHeader();var c=document.getElementById('content');if(tab==='garage')c.innerHTML=garageHtml();else if(tab==='map'){c.innerHTML=mapHtml();setTimeout(loadMap,20)}else if(tab==='settings')c.innerHTML=settingsHtml();else if(tab==='ai')c.innerHTML=aiHtml();else if(tab==='about')c.innerHTML=aboutHtml();else c.innerHTML=homeHtml();bind();applyLang()}"
new_render="function render(){updateHeader();var c=document.getElementById('content');if(tab==='garage')c.innerHTML=garageHtml();else if(tab==='map'){c.innerHTML=mapHtml();setTimeout(loadMap,20)}else if(tab==='settings')c.innerHTML=settingsHtml();else if(tab==='ai')c.innerHTML=aiHtml();else if(tab==='about')c.innerHTML=aboutHtml();else c.innerHTML=homeHtml();bind();applyLang();paintVehicleCanvases()}"
if old_render not in s:
    raise SystemExit("render anchor not found")
s=s.replace(old_render,new_render)

old_modal="function openModal(html){document.getElementById('sheet').innerHTML=html;document.getElementById('modal').classList.add('open');bindModal()}"
new_modal="function openModal(html){document.getElementById('sheet').innerHTML=html;document.getElementById('modal').classList.add('open');bindModal();paintVehicleCanvases()}"
if old_modal in s:
    s=s.replace(old_modal,new_modal)

p.write_text(s,encoding="utf-8")
print("patched AI Paint v3 Android",p)
