from pathlib import Path
import re
f=Path("PunisherAndroid/app/src/main/assets/index.html")
s=f.read_text(encoding="utf-8")
s=s.replace("Android 0.4.3 (14)","Android 0.4.5 (16)")
# Avoid oversizing plates; preserve physical width/height on all car previews.
s=s.replace("plateH=plateW*0.2214*1.5;","plateH=plateW*0.2214;")
# Keep full number visible in plate flex layout, including six digits.
s=re.sub(r"(\.iraqi-plate\{)",r"\1max-width:100%;",s,count=1)
f.write_text(s,encoding="utf-8")
print("plate v20 updated")
