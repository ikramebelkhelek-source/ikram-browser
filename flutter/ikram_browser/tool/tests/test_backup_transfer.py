"""Fast checks for the native harness; these are NOT emulator evidence."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

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

    def test_on_device_checksums_preserve_spaces_and_detect_loss_or_mutation(self):
        original = self.harness.file_hashes(
            "a" * 64 + "  app_webview/Cookies\n" +
            "b" * 64 + "  app_webview/Local Storage/data\n")
        self.assertEqual(original["app_webview/Local Storage/data"], "b" * 64)
        self.assertNotEqual(original, self.harness.file_hashes(
            "a" * 64 + "  app_webview/Cookies\n"))
        self.assertNotEqual(original, self.harness.file_hashes(
            "c" * 64 + "  app_webview/Cookies\n" +
            "b" * 64 + "  app_webview/Local Storage/data\n"))
        with self.assertRaises(AssertionError):
            self.harness.file_hashes("truncated")

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

    def test_native_fields_need_not_expose_flutter_hints(self):
        device = self.harness.Device(Path("."))
        tree = ET.fromstring(
            '<hierarchy><node class="android.widget.EditText" text="اسم" '
            'bounds="[10,20][300,80]"/><node class="android.widget.EditText" '
            'text="" content-desc="" bounds="[10,90][300,150]"/>'
            '<node class="android.widget.Button" content-desc="تأكيد الاستيراد" '
            'enabled="false" bounds="[10,160][300,220]"/></hierarchy>')
        device.dump = lambda: tree
        self.assertEqual(device.find(editable=True)[1], (155, 50))
        self.assertEqual(device.find(editable=True, index=1)[1], (155, 120))
        self.assertEqual(device.find("تأكيد الاستيراد")[0].get("enabled"), "false")

    def test_document_root_selector_excludes_background_breadcrumb(self):
        device = self.harness.Device(Path("."))
        device.dump = lambda: ET.fromstring(
            '<hierarchy><node text="Downloads" resource-id="docs:id/breadcrumb_text" '
            'bounds="[0,0][100,50]"/><node text="Downloads" resource-id="android:id/title" '
            'bounds="[0,200][100,250]"/><node text="file.json" resource-id="android:id/title" '
            'bounds="[0,300][100,350]"/></hierarchy>')
        self.assertEqual(device.find("Downloads", resource="/title")[1], (50, 225))

    def test_document_navigation_waits_for_drawer_to_close_before_file_clicks(self):
        device = self.harness.Device(Path("."))
        closed = ET.fromstring('<hierarchy><node text="Downloads"/></hierarchy>')
        opened = ET.fromstring(
            '<hierarchy><node text="Open from" bounds="[10,20][100,60]"/></hierarchy>')
        frames = iter([closed, opened, closed])
        device.dump = lambda: next(frames)
        taps = []
        device.tap = lambda label, **kwargs: taps.append(label)
        with patch.object(self.harness.time, "sleep"):
            device.downloads()
        self.assertEqual(taps, ["Show roots", "Downloads", "Downloads"])

    def test_transient_empty_accessibility_tree_is_retried(self):
        device = self.harness.Device(Path("."))
        attempts = iter([
            self.harness.subprocess.CalledProcessError(1, ["adb", "shell", "cat"]),
            ET.fromstring('<hierarchy><node text="ready" bounds="[1,2][101,102]"/></hierarchy>'),
        ])

        def dump():
            item = next(attempts)
            if isinstance(item, Exception):
                raise item
            return item

        device.dump = dump
        with patch.object(self.harness.time, "sleep"):
            self.assertEqual(device.find("ready")[1], (51, 52))

    def test_paste_dismisses_keyboard_before_reading_narrow_field(self):
        device = self.harness.Device(Path("."))
        calls = []
        device.tap = lambda *args, **kwargs: None
        device.shell = lambda *args: "mInputShown=true" if args[0] == "dumpsys" else ""
        device.back = lambda: calls.append("hide-keyboard")

        def field(*args, **kwargs):
            calls.append("read-field")
            return ET.fromstring('<node text="malformed"/>'), (0, 0)

        device.find = field
        with patch.object(self.harness.time, "sleep"):
            device.paste(expected="malformed")
        self.assertEqual(calls, ["hide-keyboard", "read-field"])

    def test_harness_never_injects_preferences_or_session_fixtures(self):
        source = (TOOL / "verify_backup_transfer.py").read_text()
        self.assertNotIn('"pm", "clear"', source)
        self.assertNotIn('"uninstall"', source)
        self.assertNotIn('"tee"', source)
        self.assertNotIn('"tar"', source)
        self.assertIn('"ro.kernel.qemu"', source)
        self.assertIn('"Refusing existing installation"', source)
        destination = source.split("def destination(")[1].split("def main(")[0]
        self.assertEqual(destination.count("seed_session("), 1)
        self.assertIn('device.probe("verify", token', destination)
        self.assertIn('"keycombination", "113", "50"', source)
        self.assertNotIn('"keyevent", "279"', source)

    def test_ci_uses_two_wiped_avds_and_never_protected_signing(self):
        workflow = (TOOL.parents[2] / ".github/workflows/android-backup-transfer.yml").read_text()
        self.assertIn("avd-name: backup-source", workflow)
        self.assertIn("avd-name: backup-destination", workflow)
        self.assertEqual(workflow.count("-wipe-data"), 2)
        self.assertIn("needs: source", workflow)
        self.assertEqual(workflow.count("runs-on: ubuntu-latest"), 2)
        self.assertIn("name: backup-documents-${{ github.run_number }}", workflow)
        self.assertNotIn("secrets.", workflow)
        self.assertNotIn("android-signing", workflow)
        self.assertNotIn("verify_android_update", workflow)


if __name__ == "__main__":
    unittest.main()
