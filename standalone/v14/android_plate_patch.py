#!/usr/bin/env python3
from pathlib import Path

p = Path("PunisherAndroid/app/src/main/assets/index.html")
s = p.read_text(encoding="utf-8")

s = s.replace("Android 0.3.2 (6)", "Android 0.3.5 (9)")

old = ".plate-on-car{position:absolute;left:30%;top:68%;transform:translate(-50%,-50%);height:18px;min-width:0;display:flex;direction:ltr;align-items:stretch;background:#fff;color:#050505;border:1px solid #555;border-radius:3px;font:900 7px ui-monospace,monospace;box-shadow:0 1px 4px rgba(0,0,0,.42);overflow:hidden;z-index:4}"
new = ".plate-on-car{position:absolute;left:30%;top:68%;transform:translate(-50%,-50%);height:23px;min-width:92px;display:flex;direction:ltr;align-items:stretch;background:#fff;color:#050505;border:1px solid #555;border-radius:3px;font:1000 11.5px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:-.15px;box-shadow:0 1px 4px rgba(0,0,0,.42);overflow:hidden;z-index:4}"
if old not in s:
    raise SystemExit("plate-on-car css not found")
s = s.replace(old, new)

s = s.replace(
    ".plate-on-car .irq{width:12px;display:grid;place-items:center;border-right:1px solid #555;font-size:5px;line-height:5px;padding:1px 0}",
    ".plate-on-car .irq{width:12%;min-width:8px;display:grid;place-items:center;border-right:1px solid #555;font-size:5.4px;line-height:5px;padding:1px 0}"
)
s = s.replace(
    ".plate-on-car .pc,.plate-on-car .pl,.plate-on-car .pn{display:grid;place-items:center;padding:0 4px;border-right:1px solid #aaa}",
    ".plate-on-car .pc,.plate-on-car .pl,.plate-on-car .pn{display:grid;place-items:center;padding:0 1px;border-right:1px solid #aaa;white-space:nowrap;overflow:hidden}"
)
s = s.replace(
    ".plate-on-car .pc{width:25px}.plate-on-car .pl{width:19px}.plate-on-car .pn{min-width:42px;border-right:0}",
    ".plate-on-car .pc{width:23%}.plate-on-car .pl{width:18%}.plate-on-car .pn{flex:1;min-width:0;border-right:0;font-size:11.8px}"
)

old_func = '''function plateHtml(v,preview){
  migratePlate(v);
  var cls=preview?'iraq-plate-preview':'plate-on-car';
  var st='';
  if(!preview){
    var m=visualMeta(v);
    if(m){
      st=' style="left:'+(m.plateX*100).toFixed(2)+'%;top:'+(m.plateY*100).toFixed(2)+'%;min-width:0;width:'+(m.plateW*100).toFixed(2)+'%;height:'+(m.plateH*100).toFixed(2)+'%;transform:translate(-50%,-50%) rotate('+m.plateAngle+'deg)"'
    }
  }
  return '<span class="'+cls+'"'+st+'><span class="irq">I<br>R<br>Q</span><span class="pc">'+esc(v.plateGovernorateCode)+'</span><span class="pl">'+esc(v.plateLetter)+'</span><span class="pn">'+esc(v.plateNumber||'000000')+'</span></span>'
}'''
new_func = '''function plateHtml(v,preview){
  migratePlate(v);
  var cls=preview?'iraq-plate-preview':'plate-on-car';
  var st='';
  if(!preview){
    var m=visualMeta(v);
    if(m){
      var plateW=Math.max(.235,Number(m.plateW||.235));
      var plateH=Math.max(.080,Number(m.plateH||.080));
      st=' style="left:'+(m.plateX*100).toFixed(2)+'%;top:'+(m.plateY*100).toFixed(2)+'%;width:'+(plateW*100).toFixed(2)+'%;height:'+(plateH*100).toFixed(2)+'%;transform:translate(-50%,-50%) rotate('+m.plateAngle+'deg)"'
    }
  }
  return '<span class="'+cls+'"'+st+'><span class="irq">I<br>R<br>Q</span><span class="pc">'+esc(v.plateGovernorateCode)+'</span><span class="pl">'+esc(v.plateLetter)+'</span><span class="pn">'+esc(v.plateNumber||'000000')+'</span></span>'
}'''
if old_func not in s:
    raise SystemExit("plateHtml function not found")
s = s.replace(old_func, new_func)

p.write_text(s, encoding="utf-8")
print("patched larger Iraqi plate text", p)
