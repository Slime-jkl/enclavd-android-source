#!/usr/bin/env python3
"""Make the site's flame-vortex.lottie play in this app.

  python3 tool/translate_flame.py path/to/flame-vortex.lottie

Two numbers differ from the file the site ships: the precomp scale (the player
here divides layer scales by 100, which shrinks the vortex to a speck) and the
mask modes (every mask is 'difference', which is mapped to add here).
"""

import json
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, "assets", "animations", "flame-vortex.lottie")
SCALE = 520.8


def main(source):
    with zipfile.ZipFile(source) as archive:
        name = [n for n in archive.namelist() if n.endswith(".json") and "manifest" not in n][0]
        data = json.loads(archive.read(name))
        manifest = archive.read("manifest.json")

    data["layers"][1]["ks"]["s"]["k"] = [SCALE, SCALE, 100]

    rewritten = 0
    for layer in data["assets"][0]["layers"]:
        for mask in layer.get("masksProperties") or []:
            if mask["mode"] == "f":
                mask["mode"] = "s"
                rewritten += 1

    with zipfile.ZipFile(TARGET, "w", zipfile.ZIP_DEFLATED) as out:
        out.writestr("manifest.json", manifest)
        for entry in archive.namelist():
            if entry != "manifest.json":
                out.writestr(entry, json.dumps(data, separators=(",", ":"))
                             if entry == name else archive.read(entry))

    print("scale %s, %d difference masks -> subtract" % (SCALE, rewritten))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
