"""Install the display name and supported all-origin WebView cleanup bridge.

Never changes applicationId, signing configuration or stored profile data.
"""
from pathlib import Path
import xml.etree.ElementTree as ET


def configure(root=Path("android/app")):
    manifest = root / "src/main/AndroidManifest.xml"
    android = "http://schemas.android.com/apk/res/android"
    ET.register_namespace("android", android)
    tree = ET.parse(manifest)
    application = tree.getroot().find("application")
    if application is None:
        raise ValueError("Missing Android application")
    application.set(f"{{{android}}}label", "إكرام سيف")
    tree.write(manifest, encoding="utf-8", xml_declaration=True)

    activity = root / "src/main/kotlin/com/ikram/ikram_browser/MainActivity.kt"
    text = activity.read_text()
    hook = """
    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        IkramPrivacy.install(this, flutterEngine.dartExecutor.binaryMessenger)
    }
"""
    if "IkramPrivacy.install" not in text:
        marker = "class MainActivity : FlutterActivity() {"
        if text.count(marker) != 1:
            raise ValueError("Unexpected MainActivity, refusing to overwrite")
        activity.write_text(text.replace(marker, marker + hook))

    source = Path(__file__).with_name("native") / "IkramPrivacy.kt"
    activity.with_name("IkramPrivacy.kt").write_text(source.read_text())
    gradle = root / "build.gradle.kts"
    if not gradle.exists():
        raise ValueError("Expected Kotlin Gradle native shell")
    text = gradle.read_text()
    dependency = 'implementation("androidx.webkit:webkit:1.13.0")'
    if dependency not in text:
        gradle.write_text(text + f"\n// Complete WebView cleanup API.\ndependencies {{ {dependency} }}\n")


if __name__ == "__main__":
    configure()
