#!/usr/bin/env python3
"""Build a macOS bundle; publication is handled separately."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(args, *, cwd=ROOT):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def capture(args, *, cwd=ROOT):
    return subprocess.check_output([str(arg) for arg in args], cwd=cwd, text=True).strip()


def signing_arguments(identity):
    if identity == "-":
        return ["--sign", "-", "--timestamp=none"]
    return ["--sign", identity, "--options", "runtime", "--timestamp"]


def verify_universal(binary):
    architectures = set(capture(["lipo", "-archs", binary]).split())
    if not {"arm64", "x86_64"}.issubset(architectures):
        raise RuntimeError(f"{binary.name} is not a universal arm64/x86_64 binary: {architectures}")


def populate_bundle(app, binaries, resources, commit, dirty):
    macos = app / "Contents/MacOS"
    target_resources = app / "Contents/Resources"
    macos.mkdir(parents=True)
    target_resources.mkdir()
    for executable in ["EdgePeek", "edgepeek-cli"]:
        shutil.copy2(binaries / executable, macos / executable)
    for name in ["AppIcon.icns", "KingHwaOldSong.ttf", "KingHwaOldSong-LICENSE.txt"]:
        shutil.copy2(resources / name, target_resources / name)
    skill = target_resources / "Skills/edgepeek"
    skill.mkdir(parents=True)
    shutil.copy2(resources / "Skills/edgepeek/SKILL.md", skill / "SKILL.md")
    info = plistlib.loads((resources / "Info.plist").read_bytes())
    info["EdgePeekSourceCommit"] = commit
    info["EdgePeekSourceDirty"] = dirty
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    (app / "Contents/PkgInfo").write_bytes(b"APPL????")


def build(config, destination, identity="-", universal=False):
    arguments = ["swift", "build", "-c", config]
    if universal:
        arguments += ["--arch", "arm64", "--arch", "x86_64"]
    run(arguments)
    binaries = Path(capture(arguments + ["--show-bin-path"]))
    commit = capture(["git", "rev-parse", "HEAD"])
    dirty = bool(capture(["git", "status", "--porcelain"]))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".edgepeek-build-", dir=destination.parent) as temporary:
        app = Path(temporary) / "贴边.app"
        populate_bundle(app, binaries, ROOT / "Resources", commit, dirty)
        if universal:
            for executable in ["EdgePeek", "edgepeek-cli"]:
                verify_universal(app / "Contents/MacOS" / executable)
        signing = signing_arguments(identity)
        run(["codesign", "--force", *signing, app / "Contents/MacOS/edgepeek-cli"])
        run(["codesign", "--force", *signing, app])
        run(["codesign", "--verify", "--deep", "--strict", app])
        previous = Path(temporary) / "previous.app"
        if destination.exists():
            destination.rename(previous)
        try:
            app.rename(destination)
        except OSError:
            if previous.exists():
                previous.rename(destination)
            raise
    print(f"Built {destination}", flush=True)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", nargs="?", default="release", choices=["debug", "release"])
    parser.add_argument("--output", type=Path, default=ROOT / "dist/贴边.app")
    parser.add_argument("--identity", default=os.environ.get("CODESIGN_IDENTITY", "-"))
    parser.add_argument("--universal", action="store_true")
    args = parser.parse_args()
    build(args.configuration, args.output.resolve(), args.identity, args.universal)


if __name__ == "__main__":
    main()
