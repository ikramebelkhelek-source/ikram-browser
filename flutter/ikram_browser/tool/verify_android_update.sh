#!/usr/bin/env bash
# Run only on a disposable emulator. Never uninstall or clear the app between APKs.
set -euo pipefail
first="$(realpath "$1")"
second="$(realpath "$2")"
package=com.ikram.ikram_browser
# Refuse personal hardware: this script seeds and replaces synthetic app data.
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = "1"
if adb shell pm path "$package" | grep -q '^package:'; then
  echo "Refusing to overwrite an existing emulator installation." >&2
  exit 1
fi
tools="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
for index in first second; do
  apk="${!index}"
  "$tools/apksigner" verify --print-certs "$apk" > "$scratch/$index.cert"
  "$tools/aapt" dump badging "$apk" > "$scratch/$index.badging"
done
python3 - "$scratch" <<'PY'
from pathlib import Path
import re
import sys
sys.path.insert(0, "flutter/ikram_browser/tool")
from verify_apk_certificate import fingerprint
root = Path(sys.argv[1])
assert fingerprint((root / "first.cert").read_text()) == fingerprint((root / "second.cert").read_text()), "Signing identity changed"
versions = []
for name in ("first", "second"):
    line = (root / f"{name}.badging").read_text().splitlines()[0]
    match = re.search(r"package: name='([^']+)' versionCode='(\d+)'", line)
    assert match and match[1] == "com.ikram.ikram_browser", "Application ID changed"
    versions.append(int(match[2]))
assert versions[1] > versions[0], "The update must have a newer versionCode"
PY
adb install "$first"
adb shell am start -W -n "$package/.MainActivity" >/dev/null
sleep 10
adb shell am force-stop "$package"
# Seed the actual SharedPreferences format plus representative native WebView
# data. These are synthetic test fixtures, never real user credentials.
cat > "$scratch/FlutterSharedPreferences.xml" <<'XML'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map><string name="flutter.ikram_profiles">[{"id":"upgrade-test","name":"Saved before update","proxy":"","proxyNeedsReview":false}]</string></map>
XML
adb shell run-as "$package" mkdir -p shared_prefs app_webview/Default
adb shell run-as "$package" tee shared_prefs/FlutterSharedPreferences.xml < "$scratch/FlutterSharedPreferences.xml" >/dev/null
printf 'webview-upgrade-fixture' | adb shell run-as "$package" tee app_webview/Default/upgrade-sentinel >/dev/null
# Snapshot the WHOLE native WebView directory, including any databases created
# on launch; no app process runs between this snapshot and the post-update one.
adb exec-out run-as "$package" tar -cf - shared_prefs app_webview > "$scratch/before.tar"
uid_before="$(adb shell dumpsys package "$package" | grep -m1 'userId=' | tr -d '\r')"
adb install -r "$second"
uid_after="$(adb shell dumpsys package "$package" | grep -m1 'userId=' | tr -d '\r')"
test "$uid_before" = "$uid_after"
adb exec-out run-as "$package" tar -cf - shared_prefs app_webview > "$scratch/after.tar"
python3 - "$scratch" <<'PY'
import hashlib
from pathlib import Path
import sys
import tarfile
def contents(path):
    with tarfile.open(path) as archive:
        return {entry.name: hashlib.sha256(archive.extractfile(entry).read()).hexdigest()
                for entry in archive if entry.isfile()}
root = Path(sys.argv[1])
assert contents(root / "before.tar") == contents(root / "after.tar"), "App data changed during update"
PY
adb shell am start -W -n "$package/.MainActivity" >/dev/null
sleep 10
adb shell uiautomator dump /sdcard/upgrade-ui.xml >/dev/null
adb pull /sdcard/upgrade-ui.xml "$scratch/ui.xml" >/dev/null
grep -q 'Saved before update' "$scratch/ui.xml"
adb shell run-as "$package" cat app_webview/Default/upgrade-sentinel | grep -q 'webview-upgrade-fixture'
echo "PASS: Same signing certificate, newer version, in-place install, retained profile and native WebView data."
