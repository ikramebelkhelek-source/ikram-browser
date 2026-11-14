"""Fast checks for the native harness; these are NOT emulator evidence."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOL / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BackupTransferTests(unittest.TestCase):
    def setUp(self):
        self.harness = load("verify_backup_transfer")
        self.backup = {
            "format": "ikram-profile-configurations", "version": 1,
            "profiles": [
                {"id": "1", "name": self.harness.SOURCE_NAME,
                 "proxy": "", "proxyNeedsReview": False},
                {"id": "source-second", "name": self.harness.SECOND_NAME,
                 "proxy": "socks://192.0.2.42:1080", "proxyNeedsReview": False},
            ],
        }

    def test_oracle_compares_unicode_configuration_and_default_id(self):
        self.assertEqual(self.harness.backup_profiles(json.dumps(self.backup)),
                         self.backup["profiles"])
        for key, value in (("name", "damaged"), ("id", "replaced"), ("proxy", "http://other:80")):
            bad = copy.deepcopy(self.backup)
            bad["profiles"][0][key] = value
            with self.subTest(key=key), self.assertRaises(AssertionError):
                self.harness.backup_profiles(json.dumps(bad))

    def test_oracle_rejects_session_fields_at_every_level(self):
        for key in ("cookies", "localStorage", "password", "session"):
            for nested in (False, True):
                bad = copy.deepcopy(self.backup)
                (bad["profiles"][0] if nested else bad)[key] = "secret"
                with self.subTest(key=key, nested=nested), self.assertRaises(AssertionError):
                    self.harness.backup_profiles(json.dumps(bad))

    def test_oracle_rejects_duplicate_ids_and_changed_proxy(self):
        for kind in ("duplicate", "proxy"):
            bad = copy.deepcopy(self.backup)
            if kind == "duplicate":
                bad["profiles"][1]["id"] = "1"
            else:
                bad["profiles"][1]["proxy"] = ""
            with self.subTest(kind=kind), self.assertRaises(AssertionError):
                self.harness.backup_profiles(json.dumps(bad))

    def test_directory_comparison_ignores_metadata_but_detects_loss_or_mutation(self):
        def archive(entries, mtime):
            output = io.BytesIO()
            with tarfile.open(fileobj=output, mode="w") as tar:
                for name, content in entries.items():
                    entry = tarfile.TarInfo(name)
                    entry.mtime = mtime
                    entry.size = len(content)
                    tar.addfile(entry, io.BytesIO(content))
            return self.harness.file_hashes(output.getvalue())
        entries = {"app_webview/Cookies": b"cookie", "app_webview/Local Storage/data": b"local"}
        original = archive(entries, 0)
        self.assertEqual(original, archive(entries, 123))
        self.assertNotEqual(original, archive({"app_webview/Cookies": b"cookie"}, 0))
        self.assertNotEqual(original, archive({**entries, "app_webview/Cookies": b"changed"}, 0))

    def test_editor_shell_is_idempotent_and_separate_from_browser(self):
        with tempfile.TemporaryDirectory() as tmp:
            android = Path(tmp)
            settings = android / "settings.gradle.kts"
            settings.write_text('include(":app")\n')
            configure = load("configure_backup_editor").configure
            configure(android)
            configure(android)
            self.assertEqual(settings.read_text().count('include(":backup_editor")'), 1)
            manifest = (android / "backup_editor/src/main/AndroidManifest.xml").read_text()
            self.assertIn('android:allowBackup="false"', manifest)
            self.assertIn('com.ikram.backupeditor',
                          (android / "backup_editor/build.gradle.kts").read_text())
            self.assertFalse((android / "app").exists())

    def test_harness_never_injects_preferences_or_session_fixtures(self):
        source = (TOOL / "verify_backup_transfer.py").read_text()
        self.assertNotIn('"pm", "clear"', source)
        self.assertNotIn('"uninstall"', source)
        self.assertNotIn('"tee"', source)
        self.assertIn('"ro.kernel.qemu"', source)
        self.assertIn('"Refusing existing installation"', source)
        destination = source.split("def destination(")[1].split("def main(")[0]
        self.assertEqual(destination.count("seed_session("), 1)
        self.assertIn('device.probe("verify", token', destination)

    def test_ci_uses_two_wiped_avds_and_never_protected_signing(self):
        workflow = (TOOL.parents[2] / ".github/workflows/android-backup-transfer.yml").read_text()
        self.assertIn("avd-name: backup-source", workflow)
        self.assertIn("avd-name: backup-destination", workflow)
        self.assertEqual(workflow.count("-wipe-data"), 2)
        self.assertNotIn("secrets.", workflow)
        self.assertNotIn("android-signing", workflow)
        self.assertNotIn("verify_android_update", workflow)


if __name__ == "__main__":
    unittest.main()
