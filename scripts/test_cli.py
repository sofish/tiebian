"""Exercise the shipped CLI and skill against isolated note files."""
import json
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["swift", "build", "--product", "edgepeek-cli"], cwd=ROOT, check=True,
                       stdout=subprocess.DEVNULL)
        binaries = subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=ROOT, text=True).strip()
        cls.binary = Path(binaries) / "edgepeek-cli"

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="edgepeek-cli-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data = self.root / "notes.json"
        self.environment = {**os.environ, "EDGEPEEK_DATA_FILE": str(self.data)}

    def run_cli(self, command, arguments=None, *, executable=None, ok=True):
        result = subprocess.run([str(executable or self.binary), command],
                                input=json.dumps(arguments or {}, ensure_ascii=False),
                                text=True, capture_output=True, env=self.environment, cwd=self.root)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return json.loads(result.stdout if ok else result.stderr)

    def test_full_note_lifecycle_group_color_search_and_reminders(self):
        self.assertEqual(self.run_cli("list_notes")["count"], 0)
        first = self.run_cli("create_note", {"content": "交稿\n#工作", "pinned": True,
                                              "dueAt": "2020-10-28T09:00:00.123+08:00"})
        second = self.run_cli("create_note", {"content": "下一篇\n#工作"})
        self.assertEqual(first["color"], second["color"])
        self.assertTrue(first["isOverdue"])
        self.assertEqual(self.run_cli("list_groups")["groups"][0]["count"], 2)
        self.assertEqual(self.run_cli("search_notes", {"query": "交稿"})["count"], 1)
        updated = self.run_cli("update_note", {"id": first["id"], "dueAt": None, "pinned": False})
        self.assertEqual(updated["content"], first["content"])
        self.assertIsNone(updated["dueAt"])
        self.assertFalse(updated["isPinned"])
        self.assertEqual(self.run_cli("get_note", {"id": first["id"]})["id"], first["id"])
        self.assertEqual(self.run_cli("delete_note", {"id": first["id"]})["deleted"]["id"], first["id"])
        self.assertEqual(self.run_cli("list_notes")["count"], 1)
        self.run_cli("get_note", {"id": first["id"]}, ok=False)

    def test_invalid_requests_and_empty_creation_do_not_change_data(self):
        note = self.run_cli("create_note", {"content": "原样保留"})
        original = self.data.read_bytes()
        for command, arguments in [
            ("create_note", {"content": " \n\t\u3000"}),
            ("create_note", {"content": "a", "pinned": 1}),
            ("create_note", {"content": "a", "dueAt": "tomorrow"}),
            ("update_note", {"id": note["id"], "content": 12}),
            ("update_note", {"id": note["id"], "pinned": "false"}),
            ("update_note", {"id": note["id"], "dueAt": "2026-10-20"}),
            ("update_note", {"id": note["id"], "dueAt": "2026-10-20T09:00:00"}),
            ("update_note", {"id": note["id"], "contents": "typo"}),
            ("delete_note", {"id": "not-a-uuid"}),
            ("unknown", {})
        ]:
            with self.subTest(command=command, arguments=arguments):
                self.assertIn("error", self.run_cli(command, arguments, ok=False))
                self.assertEqual(self.data.read_bytes(), original)
        self.assertEqual(self.run_cli("create_note", {"content": "#标签"})["content"], "#标签")

    def test_parallel_cli_writers_do_not_lose_notes(self):
        with ThreadPoolExecutor(max_workers=8) as workers:
            notes = list(workers.map(lambda index: self.run_cli("create_note", {"content": f"Note {index}"}),
                                     range(20)))
        saved = self.run_cli("list_notes")
        self.assertEqual(saved["count"], 20)
        self.assertEqual({note["id"] for note in notes}, {note["id"] for note in saved["notes"]})

    def test_skill_installs_from_renamed_bundle_and_launcher_quotes_path(self):
        bundle = self.root / "it's 贴边 $(touch SHOULD_NOT_EXIST).app"
        executable = bundle / "Contents/MacOS/edgepeek-cli"
        executable.parent.mkdir(parents=True)
        shutil.copy2(self.binary, executable)
        skill = bundle / "Contents/Resources/Skills/edgepeek/SKILL.md"
        skill.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "Resources/Skills/edgepeek/SKILL.md", skill)
        destination = self.root / "client skills/edgepeek"
        result = subprocess.run([str(executable), "install-skill", str(destination)],
                                text=True, capture_output=True, env=self.environment, check=True)
        self.assertEqual(json.loads(result.stdout)["executable"], str(executable))
        self.assertEqual((destination / "SKILL.md").read_bytes(), skill.read_bytes())
        launcher = destination / "scripts/edgepeek"
        self.assertEqual(self.run_cli("list_notes", executable=launcher)["count"], 0)
        self.assertFalse(self.data.exists())
        help_result = subprocess.run([str(launcher), "--help"], text=True, capture_output=True, check=True)
        self.assertIn("create_note", help_result.stdout)
        self.assertFalse((self.root / "SHOULD_NOT_EXIST").exists())


if __name__ == "__main__":
    unittest.main()
