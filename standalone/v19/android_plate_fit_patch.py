from pathlib import Path
import re
p=Path("PunisherAndroid/app/src/main/assets/index.html")
s=p.read_text(encoding="utf-8")
s=s.replace("Android 0.4.2 (13)","Android 0.4.3 (14)")
s=re.sub(r"\.iraqi-plate\{", ".iraqi-plate{box-sizing:border-box;overflow:visible;white-space:nowrap;",s,count=1)
# The displayed plate must not be constrained by the detected height when it is
# too shallow to fit its serial. Keep a consistent physical aspect ratio.
s=s.replace("var plateH=Math.max(.018,Number(m.plateH||.028));","var plateH=Math.max(.018,Number(m.plateH||.028));plateH=plateW*0.2214*1.5;")
p.write_text(s,encoding="utf-8")
print("Android plate overflow and aspect ratio patch applied")
