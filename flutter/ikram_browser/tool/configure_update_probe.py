"""Enable native WebView inspection in the generated Android debug shell."""
from pathlib import Path


def configure(root=Path("android/app/src/main/kotlin")):
    activity = root / "com/ikram/ikram_browser/MainActivity.kt"
    source = activity.read_text()
    if "WebView.setWebContentsDebuggingEnabled" in source:
        return
    old = "class MainActivity : FlutterActivity()"
    if source.count(old) != 1:
        raise ValueError("Unexpected MainActivity; refusing to change native shell")
    replacement = """class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            android.webkit.WebView.setWebContentsDebuggingEnabled(true)
        }
    }
}"""
    # flutter create emits either an empty class or an empty braced body.
    source = source.replace(old + " {}", old)
    activity.write_text(source.replace(old, replacement))


if __name__ == "__main__":
    configure()
