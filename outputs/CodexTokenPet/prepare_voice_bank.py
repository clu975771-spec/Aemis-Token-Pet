import json, shutil, sys
from pathlib import Path
root=Path(sys.argv[1])
data=json.loads((root/'voice-assets/unified/manifest.json').read_text())
for clip in data['clips']:
 if clip['percent']==100:
  target=root/clip['source']
  if not target.exists():
   target.parent.mkdir(parents=True,exist_ok=True)
   shutil.copyfile(root/'voice-assets/unified'/clip['file'],target)
