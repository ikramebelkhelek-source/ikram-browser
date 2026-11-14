"""Add a disposable clipboard/editor APK to the generated CI Android shell."""
from pathlib import Path
import shutil


def configure(android=Path("android")):
    settings = android / "settings.gradle.kts"
    source = settings.read_text()
    include = 'include(":backup_editor")'
    if include not in source:
        settings.write_text(source + "\n" + include + "\n")
    module = android / "backup_editor"
    java = module / "src/main/java/com/ikram/backupeditor"
    java.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).parent / "backup_editor/BackupEditor.java",
                    java / "BackupEditor.java")
    (module / "build.gradle.kts").write_text("""
plugins { id("com.android.application") }
android {
    namespace = "com.ikram.backupeditor"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.ikram.backupeditor"
        minSdk = 24
        targetSdk = 28
        versionCode = 1
        versionName = "1"
    }
}
""")
    (module / "src/main/AndroidManifest.xml").write_text("""
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="Synthetic backup editor"
      android:theme="@android:style/Theme.Material.Light.NoActionBar"
      android:allowBackup="false">
    <activity android:name=".BackupEditor" android:exported="true"
        android:windowSoftInputMode="stateAlwaysHidden">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
""")


if __name__ == "__main__":
    configure()
