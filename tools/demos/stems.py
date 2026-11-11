"""各トラックをソロで書き出して RMS を比べる（ミックスバランスの確認用）。

  python3 tools/demos/stems.py app/assets/demos/technopop.json 8 16
リポジトリの直下から実行する（build/mdaw_render と kits/ を読む）。
"""
import json
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
proj, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
d = json.load(open(proj))
render = os.path.join(ROOT, "build", "mdaw_render")
for tr in d["tracks"]:
    dd = json.loads(json.dumps(d))
    for x in dd["tracks"]:
        x["mixer"]["solo"] = x["id"] == tr["id"]
    json.dump(dd, open("/tmp/_stem.json", "w"))
    subprocess.run([render, "/tmp/_stem.json", "/tmp/_stem.wav"], capture_output=True, cwd=ROOT)
    r, a = wavfile.read("/tmp/_stem.wav")
    a = a.astype(float) / (2**31 if a.dtype == np.int32 else 32768 if a.dtype == np.int16 else 1)
    seg = a[int(t0 * r):int(t1 * r)]
    rms = 10 * np.log10(np.mean(seg**2) + 1e-12)
    print(f"{tr['name']:10s} rms {rms:6.1f} dB  peak {np.abs(seg).max():.3f}")
