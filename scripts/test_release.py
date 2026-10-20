import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

from build_app import populate_bundle, signing_arguments, verify_universal
from package_release import notary_credentials, notarize, verify_source


class ReleaseTests(unittest.TestCase):
    def test_universal_verification_rejects_missing_architecture(self):
        for output in ["arm64", "x86_64"]:
            with patch("build_app.capture", return_value=output):
                with self.assertRaisesRegex(RuntimeError, "not a universal"):
                    verify_universal(Path("EdgePeek"))
        with patch("build_app.capture", return_value="x86_64 arm64"):
            verify_universal(Path("EdgePeek"))

    def test_bundle_contains_both_executables_resources_and_source_proof(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binaries = root / "binaries"
            resources = root / "resources"
            binaries.mkdir()
            resources.mkdir()
            for name in ["EdgePeek", "edgepeek-mcp"]:
                (binaries / name).write_bytes(name.encode())
            for name in ["AppIcon.icns", "KingHwaOldSong.ttf", "KingHwaOldSong-LICENSE.txt"]:
                (resources / name).write_bytes(name.encode())
            (resources / "not-for-distribution.secret").write_text("do not copy")
            (resources / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.1.0"}))
            app = root / "贴边.app"
            populate_bundle(app, binaries, resources, "abc123", False)
            info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            self.assertEqual(info["EdgePeekSourceCommit"], "abc123")
            self.assertFalse(info["EdgePeekSourceDirty"])
            self.assertEqual((app / "Contents/MacOS/edgepeek-mcp").read_bytes(), b"edgepeek-mcp")
            self.assertEqual(len(list((app / "Contents/Resources").iterdir())), 3)
            self.assertFalse((app / "Contents/Resources/not-for-distribution.secret").exists())

    def test_published_primary_is_required_and_live_head_is_parsed(self):
        commit = "a" * 40
        remote = f"ref: refs/heads/main\tHEAD\n{commit}\tHEAD"
        with patch("package_release.capture", side_effect=["", remote, commit]):
            self.assertEqual(verify_source(), commit)
        with patch("package_release.capture", return_value=" M source.swift"):
            with self.assertRaisesRegex(RuntimeError, "clean"):
                verify_source()
        with patch("package_release.capture", side_effect=["", remote, "b" * 40]):
            with self.assertRaisesRegex(RuntimeError, "live primary"):
                verify_source()

    def test_developer_id_signing_enables_hardened_runtime_and_timestamp(self):
        self.assertEqual(signing_arguments("-"), ["--sign", "-", "--timestamp=none"])
        signing = signing_arguments("Developer ID Application: Test")
        self.assertIn("runtime", signing)
        self.assertIn("--timestamp", signing)
        self.assertNotIn("--timestamp=none", signing)

    def test_notarization_requires_credentials(self):
        with patch.dict("os.environ", {}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "NOTARY_PROFILE"):
                notary_credentials()
        with patch.dict("os.environ", {"NOTARY_PROFILE": "release"}, clear=True):
            self.assertEqual(notary_credentials(), ["--keychain-profile", "release"])
        with patch.dict("os.environ", {"NOTARY_KEY_PATH": "/private/key.p8", "NOTARY_KEY_ID": "key",
                                        "NOTARY_ISSUER": "issuer"}, clear=True):
            self.assertEqual(notary_credentials(), ["--key", "/private/key.p8", "--key-id", "key",
                                                    "--issuer", "issuer"])

    def test_notarization_only_accepts_apple_accepted_state(self):
        with patch("package_release.capture", return_value=json.dumps({"id": "submission", "status": "Accepted"})):
            self.assertEqual(notarize(Path("app.zip"), ["--keychain-profile", "release"]), "submission")
        for status in ["Invalid", "In Progress"]:
            with patch("package_release.capture", return_value=json.dumps({"id": "submission", "status": status})):
                with self.assertRaisesRegex(RuntimeError, "Notarization failed"):
                    notarize(Path("app.zip"), ["--keychain-profile", "release"])


if __name__ == "__main__":
    unittest.main()
