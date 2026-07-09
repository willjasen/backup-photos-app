import json
import tempfile
import time
import unittest
from pathlib import Path

from app import AppError, PhotoExportApp, active_entries, validate_lists


class ListTests(unittest.TestCase):
    def test_active_entries_ignores_comments_and_blank_lines(self):
        self.assertEqual(
            active_entries("# note\n\nFamily\n  Friends  \n"),
            ["Family", "Friends"],
        )

    def test_album_commas_are_rejected(self):
        with self.assertRaisesRegex(AppError, "line\\(s\\): 2"):
            validate_lists({"albums": "Family\nTrips, 2025\n", "people": "Sam\n"})

    def test_lists_are_saved_in_configured_backup_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backup = root / "backup"
            (root / "config.json").write_text(
                json.dumps(
                    {
                        "photo_backup_dir": str(backup),
                        "photos_library_dir": "/tmp/Photos Library.photoslibrary",
                        "reports_dir_name": "-reports-",
                        "checkpoints": 100,
                    }
                ),
                encoding="utf-8",
            )
            app = PhotoExportApp(root=root, script=root / "fake.zsh")
            result = app.save_lists(
                {"albums": "# favorites\nFamily", "people": "Alex\nJordan\n"}
            )
            self.assertEqual(result["counts"], {"albums": 1, "people": 2})
            self.assertEqual(
                (backup / "albums.txt").read_text(encoding="utf-8"),
                "# favorites\nFamily\n",
            )


class ExportTests(unittest.TestCase):
    def test_export_manager_runs_selected_modes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            backup = root / "backup"
            script = root / "fake.zsh"
            script.write_text(
                "#!/bin/zsh\n"
                "echo \"modes: $@\"\n"
                "echo done\n",
                encoding="utf-8",
            )
            script.chmod(0o755)
            (root / "config.json").write_text(
                json.dumps(
                    {
                        "photo_backup_dir": str(backup),
                        "photos_library_dir": "/tmp/Photos Library.photoslibrary",
                        "reports_dir_name": "-reports-",
                        "checkpoints": 100,
                    }
                ),
                encoding="utf-8",
            )
            app = PhotoExportApp(root=root, script=script)
            app.validate_export(["albums", "people"])
            app.manager.start(["albums", "people"])
            for _ in range(100):
                status = app.manager.status()
                if not status["running"]:
                    break
                time.sleep(0.01)
            text = "\n".join(line["text"] for line in status["lines"])
            self.assertEqual(status["exit_code"], 0)
            self.assertIn("modes: --albums --people", text)
            self.assertIn("Export finished successfully.", text)

    def test_date_export_requires_dates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "config.json").write_text(
                json.dumps(
                    {
                        "photo_backup_dir": "/tmp/backup",
                        "photos_library_dir": "/tmp/Photos Library.photoslibrary",
                        "reports_dir_name": "-reports-",
                        "checkpoints": 100,
                    }
                ),
                encoding="utf-8",
            )
            app = PhotoExportApp(root=root)
            with self.assertRaisesRegex(AppError, "from_date"):
                app.validate_export(["date"])


if __name__ == "__main__":
    unittest.main()
