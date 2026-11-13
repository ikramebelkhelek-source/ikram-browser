import importlib.util
from pathlib import Path
import tempfile
import os
import subprocess
import unittest

TOOL = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOL / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class UpdateProbeTests(unittest.TestCase):
    def test_debug_probe_configuration_is_idempotent(self):
        configure = load("configure_update_probe").configure
        for suffix in ("", " {}"):
            with self.subTest(suffix=suffix), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                activity = root / "com/ikram/ikram_browser/MainActivity.kt"
                activity.parent.mkdir(parents=True)
                activity.write_text("class MainActivity : FlutterActivity()" + suffix)
                configure(root)
                source = activity.read_text()
                self.assertIn("FLAG_DEBUGGABLE", source)
                self.assertEqual(source.count("override fun onCreate"), 1)
                configure(root)
                self.assertEqual(activity.read_text(), source)

    def test_unexpected_shell_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            activity = root / "com/ikram/ikram_browser/MainActivity.kt"
            activity.parent.mkdir(parents=True)
            activity.write_text("unexpected native project")
            with self.assertRaises(ValueError):
                load("configure_update_probe").configure(root)
            self.assertEqual(activity.read_text(), "unexpected native project")

    def test_ui_label_and_rtl_coordinates(self):
        center = load("update_ui").center
        xml = ('<hierarchy><node content-desc="تأكيد" bounds="[300,10][400,50]"/>'
               '<node text="Saved before update" bounds="[10,80][300,160]"/></hierarchy>')
        self.assertEqual(center(xml, "تأكيد"), (350, 30))
        self.assertEqual(center(xml, "Saved before update"), (155, 120))
        with self.assertRaises(ValueError):
            center(xml, "missing")
        with self.assertRaises(ValueError):
            center('<hierarchy><node text="hidden" bounds="[0,0][0,0]"/></hierarchy>', "hidden")
        self.assertEqual(center(
            '<hierarchy><node content-desc="Saved before update&#10;System network" '
            'bounds="[10,80][300,160]"/></hierarchy>', "Saved before update"), (155, 120))

    def test_verification_page_never_reseeds_lost_storage(self):
        page = (TOOL / "update_test_page.html").read_text()
        seed = page.split('if (location.pathname === "/seed") {')[1].split("}")[0]
        self.assertIn("document.cookie =", seed)
        self.assertIn('localStorage.setItem("android_update_token", token)', page)
        self.assertEqual(page.count("localStorage.setItem"), 1)
        self.assertEqual(page.count("document.cookie ="), 1)
        self.assertIn("window.isSecureContext", page)

    def test_script_refuses_personal_device_and_existing_installation(self):
        script = TOOL / "verify_android_update.sh"
        for emulator in (False, True):
            with self.subTest(emulator=emulator), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                apk = root / "test.apk"
                apk.touch()
                log = root / "adb.log"
                adb = root / "adb"
                adb.write_text(
                    '#!/bin/sh\n'
                    f'echo "$*" >> "{log}"\n'
                    f'if [ "$*" = "shell getprop ro.kernel.qemu" ]; then echo {int(emulator)}; '
                    'elif [ "$*" = "shell pm path com.ikram.ikram_browser" ]; then '
                    'echo package:/data/app/existing.apk; else exit 99; fi\n')
                adb.chmod(0o755)
                result = subprocess.run(
                    ["bash", str(script), str(apk), str(apk)],
                    env={**os.environ, "PATH": f"{tmp}:{os.environ['PATH']}"},
                    capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("install", log.read_text())
                self.assertNotIn("run-as", log.read_text())
                if emulator:
                    self.assertIn("Refusing to overwrite", result.stderr)


if __name__ == "__main__":
    unittest.main()
