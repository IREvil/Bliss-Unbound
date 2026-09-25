"""Temporal stability of screenshot sequences: mean |frame(i+1) - frame(i)| per variant and pose.

usage: py tools/shimmer.py PREFIX[,PREFIX...] POSE[,POSE...] [N] [--crop=x0,y0,x1,y1] [--sheet=NAME]
Fetches PREFIX-POSE-1..N.png from the capture server, prints the metric, and optionally saves a sheet of
the per-pixel temporal std (x8) next to frame 1 for each variant.
"""
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image

BASE = "http://192.168.1.254:18743/"
OUT = Path(__file__).parent / "cap-20260924"


def fetch(name):
    path = OUT / (name + ".png")
    with urllib.request.urlopen(BASE + name + ".png", timeout=20) as response:
        path.write_bytes(response.read())
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    prefixes, poses = args[0].split(","), args[1].split(",")
    n = int(args[2]) if len(args) > 2 else 5
    crop = tuple(int(v) for v in opts["crop"].split(",")) if "crop" in opts else None
    rows = []
    for pose in poses:
        for prefix in prefixes:
            frames = np.stack([fetch("%s-%s-%d" % (prefix, pose, i + 1)) for i in range(n)])
            if crop:
                frames = frames[:, crop[1]:crop[3], crop[0]:crop[2]]
            diff = np.abs(np.diff(frames, axis=0)).mean()
            std = frames.std(axis=0).mean(axis=2)
            print("%-6s %-6s frame-to-frame %.2f  temporal std %.2f  p99 std %.1f" % (prefix, pose, diff, std.mean(), np.percentile(std, 99)))
            rows.append((frames[0], np.clip(std * 8.0, 0, 255)))
    if "sheet" in opts:
        h, w = rows[0][0].shape[:2]
        scale = 0.5 if not crop else 1.0
        tw, th = int(w * scale), int(h * scale)
        sheet = Image.new("RGB", (tw * 2 + 8, (th + 8) * len(rows)), "white")
        for i, (frame, std) in enumerate(rows):
            sheet.paste(Image.fromarray(frame.astype(np.uint8)).resize((tw, th)), (0, i * (th + 8)))
            sheet.paste(Image.fromarray(std.astype(np.uint8)).convert("RGB").resize((tw, th)), (tw + 8, i * (th + 8)))
        sheet.save(OUT / (opts["sheet"] + ".png"))
        print(OUT / (opts["sheet"] + ".png"))


if __name__ == "__main__":
    main()
