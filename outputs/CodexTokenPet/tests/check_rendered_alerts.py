from pathlib import Path
import sys

root = Path(sys.argv[1])
for role in ("aemis",):
    for kind in ("complete", "problem"):
        english = root / f"{role}-{kind}-en.png"
        chinese = root / f"{role}-{kind}-zh.png"
        assert english.read_bytes() == chinese.read_bytes(), f"task title leaked into {role}/{kind} bubble"
        from PIL import Image
        assert Image.open(english).size == (458, 514), f"wrong bubble frame for {role}/{kind}"
print("PASS: Aemis and both alerts stay compact and independent of task title language")
