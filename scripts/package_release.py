#!/usr/bin/env python3
"""Package a pushed primary commit as a signed, notarized universal macOS release."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tempfile

from build_app import ROOT, build, capture, run


def verify_source():
    if capture(["git", "status", "--porcelain"]):
        raise RuntimeError("Release source must be clean, committed and pushed to origin's primary branch.")
    remote = capture(["git", "ls-remote", "--symref", "origin", "HEAD"])
    commit = capture(["git", "rev-parse", "HEAD"])
    primary = next((line.split()[1] for line in remote.splitlines() if line.startswith("ref:")), None)
    remote_commit = next((line.split()[0] for line in remote.splitlines()
                          if line.endswith("\tHEAD") and not line.startswith("ref:")), None)
    if primary is None or remote_commit != commit:
        raise RuntimeError("HEAD does not match origin's live primary commit; merge and push before packaging.")
    return commit


def notary_credentials():
    profile = os.environ.get("NOTARY_PROFILE")
    if profile:
        return ["--keychain-profile", profile]
    key = os.environ.get("NOTARY_KEY_PATH")
    key_id = os.environ.get("NOTARY_KEY_ID")
    issuer = os.environ.get("NOTARY_ISSUER")
    if key and key_id and issuer:
        return ["--key", key, "--key-id", key_id, "--issuer", issuer]
    raise RuntimeError("Set NOTARY_PROFILE or NOTARY_KEY_PATH / NOTARY_KEY_ID / NOTARY_ISSUER.")


def notarize(path, credentials):
    print(f"Notarizing {path.name}…", flush=True)
    result = json.loads(capture([
        "xcrun", "notarytool", "submit", path, *credentials, "--wait", "--timeout", "10m", "--output-format", "json"
    ]))
    if result.get("status") != "Accepted":
        raise RuntimeError(f"Notarization failed: {result}")
    return result["id"]


def archive_app(app, archive):
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive])


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def package(destination, identity):
    commit = verify_source()
    credentials = notary_credentials()
    if identity == "-":
        raise RuntimeError("A Developer ID Application identity is required for a user release.")
    version = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    destination.mkdir(parents=True, exist_ok=True)
    name = f"EdgePeek-{version}-macOS-universal"
    zip_path = destination / f"{name}.zip"
    dmg_path = destination / f"{name}.dmg"
    if zip_path.exists() or dmg_path.exists():
        raise RuntimeError("Release artifacts already exist; use a fresh output directory.")
    app = build("release", destination / "贴边.app", identity, universal=True)
    # A release cannot silently acquire source edits during its build.
    if verify_source() != commit:
        raise RuntimeError("The source commit changed during the release build.")
    with tempfile.TemporaryDirectory(prefix=".notary-", dir=destination) as temporary:
        archive = Path(temporary) / "notary.zip"
        archive_app(app, archive)
        app_submission = notarize(archive, credentials)
    run(["xcrun", "stapler", "staple", app])
    run(["xcrun", "stapler", "validate", app])
    run(["spctl", "--assess", "--type", "execute", "--verbose=2", app])
    archive_app(app, zip_path)
    with tempfile.TemporaryDirectory(prefix=".dmg-", dir=destination) as temporary:
        staging = Path(temporary)
        run(["ditto", app, staging / app.name])
        (staging / "Applications").symlink_to("/Applications", target_is_directory=True)
        (staging / "安装说明.txt").write_bytes((ROOT / "Resources/安装说明.txt").read_bytes())
        run(["hdiutil", "create", "-volname", f"贴边 {version}", "-srcfolder", staging,
             "-format", "UDZO", "-fs", "HFS+", dmg_path])
    run(["codesign", "--force", "--sign", identity, "--timestamp", dmg_path])
    dmg_submission = notarize(dmg_path, credentials)
    run(["xcrun", "stapler", "staple", dmg_path])
    run(["xcrun", "stapler", "validate", dmg_path])
    run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature",
         "--verbose=2", dmg_path])
    proof = {
        "version": version, "sourceCommit": commit, "architectures": ["arm64", "x86_64"],
        "minimumMacOS": "14.0", "notarization": {"app": app_submission, "dmg": dmg_submission},
        "assets": {path.name: checksum(path) for path in [zip_path, dmg_path]}
    }
    proof_path = destination / "release-proof.json"
    proof_path.write_text(json.dumps(proof, ensure_ascii=False, indent=2) + "\n")
    assets = [zip_path, dmg_path, proof_path]
    (destination / "SHA256SUMS.txt").write_text("".join(f"{checksum(path)}  {path.name}\n" for path in assets))
    print(json.dumps(proof, ensure_ascii=False, indent=2), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--identity", default=os.environ.get("CODESIGN_IDENTITY"), required=False)
    args = parser.parse_args()
    if not args.identity:
        parser.error("--identity or CODESIGN_IDENTITY is required")
    package(args.output.resolve(), args.identity)


if __name__ == "__main__":
    main()
