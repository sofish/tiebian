#!/usr/bin/env python3
"""Regenerate the native icon master and canonical macOS icon sizes."""
from pathlib import Path
import shutil
import tempfile

from build_app import ROOT, run


def main():
    master = ROOT / "Resources/icon-1024.png"
    run(["swift", ROOT / "scripts/make-icon.swift", master])
    if shutil.which("oxipng"):
        run(["oxipng", "-o", "4", "--strip", "safe", master])
    else:
        print("oxipng unavailable; PNG compression skipped")
    with tempfile.TemporaryDirectory(prefix="edgepeek-icon-") as temporary:
        iconset = Path(temporary) / "AppIcon.iconset"
        iconset.mkdir()
        for size in [16, 32, 128, 256, 512]:
            for factor in [1, 2]:
                suffix = "@2x" if factor == 2 else ""
                target = iconset / f"icon_{size}x{size}{suffix}.png"
                run(["sips", "-z", size * factor, size * factor, master, "--out", target])
        run(["iconutil", "-c", "icns", iconset, "-o", ROOT / "Resources/AppIcon.icns"])
    print("Wrote Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
