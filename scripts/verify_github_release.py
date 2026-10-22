#!/usr/bin/env python3
"""Probe the published GitHub Release that carries this source commit."""
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = "sofish/tiebian"
VERSION = "1.3.2"
TAG = f"v{VERSION}"
ASSETS = {
    f"EdgePeek-{VERSION}-macOS-universal.dmg",
    f"EdgePeek-{VERSION}-macOS-universal.zip",
    "release-proof.json",
    "SHA256SUMS.txt",
}


def command(args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"command failed: {' '.join(args)}")
    return result.stdout


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def release_state(release):
    if release.get("isDraft"):
        raise RuntimeError("Release is still a draft.")
    if release.get("isPrerelease"):
        raise RuntimeError("Release is marked prerelease.")
    return "VALID"


def verify_proof(commit, proof, files):
    if proof.get("sourceCommit") != commit:
        raise RuntimeError("release-proof.json sourceCommit does not match.")
    assets = proof.get("assets")
    if not isinstance(assets, dict) or not assets:
        raise RuntimeError("release-proof.json has no asset hashes.")
    for name, expected in assets.items():
        path = files / name
        if not path.is_file():
            raise RuntimeError(f"Missing release asset: {name}")
        if checksum(path) != expected:
            raise RuntimeError(f"Checksum mismatch: {name}")


def verify(commit, tag=TAG, repo=REPO):
    tag_commit = command(["gh", "api", f"repos/{repo}/commits/{tag}", "--jq", ".sha"]).strip()
    if tag_commit != commit:
        raise RuntimeError(f"Tag {tag} points to {tag_commit}, not {commit}.")
    release = json.loads(command([
        "gh", "release", "view", tag, "-R", repo,
        "--json", "assets,isDraft,isPrerelease,url",
    ]))
    state = release_state(release)
    names = {asset["name"] for asset in release.get("assets", [])}
    missing = ASSETS - names
    if missing:
        raise RuntimeError(f"Release is missing assets: {sorted(missing)}")
    with tempfile.TemporaryDirectory(prefix="edgepeek-release-") as temporary:
        files = Path(temporary)
        command([
            "gh", "release", "download", tag, "-R", repo,
            "--dir", str(files), "--clobber",
        ])
        verify_proof(commit, json.loads((files / "release-proof.json").read_text()), files)
    return {
        "sourceCommit": commit,
        "artifactId": f"{repo}@{tag}",
        "state": state,
        "url": release["url"],
    }


def main():
    if len(sys.argv) != 2 or len(sys.argv[1]) != 40:
        raise SystemExit("usage: verify_github_release.py <full-source-commit>")
    print(json.dumps(verify(sys.argv[1]), ensure_ascii=False))


if __name__ == "__main__":
    main()
