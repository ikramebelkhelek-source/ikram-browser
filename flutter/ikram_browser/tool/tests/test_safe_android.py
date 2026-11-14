import importlib.util
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).parents[1] / "configure_safe_android.py"
spec = importlib.util.spec_from_file_location("safe_android", TOOL)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SafeAndroidTests(unittest.TestCase):
    def test_name_and_cleanup_hook_keep_update_identity_and_signing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = root / "src/main/AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                                '<application android:label="ikram_browser"/></manifest>')
            activity = root / "src/main/kotlin/com/ikram/ikram_browser/MainActivity.kt"
            activity.parent.mkdir(parents=True)
            activity.write_text("package com.ikram.ikram_browser\n"
                                "class MainActivity : FlutterActivity() {\n}\n")
            gradle = root / "build.gradle.kts"
            original = 'applicationId = "com.ikram.ikram_browser"\n// signing stays unchanged\n'
            gradle.write_text(original)
            module.configure(root)
            first = activity.read_text(), gradle.read_text(), manifest.read_text()
            module.configure(root)
            self.assertEqual(first, (activity.read_text(), gradle.read_text(), manifest.read_text()))
            self.assertIn("إكرام سيف", manifest.read_text())
            self.assertTrue(gradle.read_text().startswith(original))
            self.assertEqual(activity.read_text().count("IkramPrivacy.install"), 1)
            self.assertIn("WebStorageCompat.deleteBrowsingData",
                          activity.with_name("IkramPrivacy.kt").read_text())


if __name__ == "__main__":
    unittest.main()
