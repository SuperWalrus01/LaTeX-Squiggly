"""Keeps, for each mark the GuideShots UI test printed, the screenshot taken
just after it: SHOT marks a settled screen, HOLD the start of a held key."""
import glob, os, shutil, sys

root = sys.argv[1]
frames = sorted((float(os.path.basename(f)[:-4]), f) for f in glob.glob(f"{root}/frames/*.png"))
# How long after the mark to look: a held key's pop-up takes a moment.
delays = {"balloon": 0.9, "accents": 2.4, "globe": 2.4}
for line in open(f"{root}/marks.txt"):
    kind, name, time = line.split()
    target = float(time) + delays.get(name, 0.3)
    later = [f for t, f in frames if t >= target]
    if later:
        shutil.copy(later[0], f"{root}/shots/{name}.png")
        print("kept", name)
    else:
        print("no frame for", name)
