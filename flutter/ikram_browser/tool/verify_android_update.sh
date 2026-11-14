#!/usr/bin/env bash
# Run only on a disposable emulator. Never uninstall or clear the app between APKs.
set -Eeuo pipefail
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 FIRST_APK SECOND_APK (disposable emulator only)" >&2
  exit 2
fi
first="$(realpath "$1")"
second="$(realpath "$2")"
package=com.ikram.ikram_browser
tool_dir="$(cd "$(dirname "$0")" && pwd)"
evidence=generated-artifacts/android-update
# Refuse personal hardware: this script seeds and replaces synthetic app data.
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = "1"
if adb shell pm path "$package" | grep -q '^package:'; then
  echo "Refusing to overwrite an existing emulator installation." >&2
  exit 1
fi
mkdir -p "$evidence"
trap 'echo "Update verification failed at line $LINENO" >&2; adb exec-out screencap -p > "$evidence/failure.png" || true; adb logcat -d -t 500 > "$evidence/logcat.txt" || true' ERR
tools="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
scratch="$(mktemp -d)"
trap 'adb forward --remove tcp:9222 >/dev/null 2>&1 || true; rm -rf "$scratch"' EXIT
adb shell getprop ro.build.version.sdk > "$evidence/api.txt"
adb shell dumpsys webviewupdate > "$evidence/webview-provider.txt"
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
# Seed only profile preferences. Cookies and localStorage MUST be created by
# the running WebView through the controlled HTTPS-origin page, not fake files.
cat > "$scratch/FlutterSharedPreferences.xml" <<'XML'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map><string name="flutter.ikram_profiles">[{"id":"upgrade-test","name":"Saved before update","proxy":"","proxyNeedsReview":false},{"id":"second-test","name":"Second saved profile","proxy":"","proxyNeedsReview":false}]</string></map>
XML
adb shell run-as "$package" mkdir -p shared_prefs app_webview/Default
adb shell run-as "$package" tee shared_prefs/FlutterSharedPreferences.xml < "$scratch/FlutterSharedPreferences.xml" >/dev/null
tap_label() {
  local label="$1" point
  for attempt in $(seq 1 30); do
    adb shell uiautomator dump /sdcard/upgrade-ui.xml >/dev/null 2>&1 || true
    adb pull /sdcard/upgrade-ui.xml "$scratch/ui.xml" >/dev/null 2>&1 || true
    if point="$(python3 "$tool_dir/update_ui.py" "$scratch/ui.xml" "$label" 2>/dev/null)"; then
      adb shell input tap $point
      return
    fi
    sleep 1
  done
  echo "Could not find visible control: $label" >&2
  return 1
}
open_profile() {
  adb shell am start -W -n "$package/.MainActivity" >/dev/null
  # This both proves the saved profile is visible and opens it through the UI.
  tap_label 'Saved before update'
  grep -q 'Second saved profile' "$scratch/ui.xml"
  cp "$scratch/ui.xml" "$evidence/profile-$1.xml"
  tap_label 'تأكيد'
  for attempt in $(seq 1 40); do
    pid="$(adb shell pidof "$package" | tr -d '\r' | awk '{print $1}')"
    if [ -n "$pid" ] && adb shell cat /proc/net/unix | grep -q "@webview_devtools_remote_$pid"; then
      adb forward tcp:9222 "localabstract:webview_devtools_remote_$pid"
      if curl --fail --silent http://127.0.0.1:9222/json | grep -q webSocketDebuggerUrl; then
        return
      fi
    fi
    sleep 1
  done
  echo "No inspectable native WebView appeared" >&2
  return 1
}
stop_and_flush() {
  # Pause the activity and give WebView's asynchronous persistent stores time to
  # flush before killing the process. The cold-start probe below tests the flush.
  adb shell input keyevent KEYCODE_HOME
  sleep 35
  adb shell am force-stop "$package"
}
token="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
open_profile seed
node "$tool_dir/probe_webview.mjs" seed "$token" "$evidence/seed.json"
adb exec-out screencap -p > "$evidence/seed.png"
stop_and_flush
# Verify the writes actually reached persistent storage BEFORE updating. This
# distinguishes a fixture/flush failure from an update regression.
open_profile cold-start
node "$tool_dir/probe_webview.mjs" verify "$token" "$evidence/cold-start.json"
stop_and_flush
printf 'webview-upgrade-fixture' | adb shell run-as "$package" tee app_webview/Default/upgrade-sentinel >/dev/null
# Snapshot the WHOLE native WebView directory, including any databases created
# on launch; no app process runs between this snapshot and the post-update one.
adb exec-out run-as "$package" tar -cf - shared_prefs app_webview > "$scratch/before.tar"
uid_before="$(adb shell run-as "$package" id -u | tr -d '\r')"
# A freshly generated, disposable identity must NOT be able to replace the app.
# Never touch the permanent signing key or print any protected signing values.
keytool -genkeypair -noprompt -keystore "$scratch/wrong.jks" \
  -storepass disposable-test -keypass disposable-test -alias wrong \
  -dname "CN=Disposable incompatible update test" -keyalg RSA -validity 1 >/dev/null 2>&1
"$tools/apksigner" sign --ks "$scratch/wrong.jks" --ks-key-alias wrong \
  --ks-pass pass:disposable-test --key-pass pass:disposable-test \
  --out "$scratch/wrong.apk" "$second"
"$tools/apksigner" verify --print-certs "$scratch/wrong.apk" > "$scratch/wrong.cert"
PYTHONPATH="$tool_dir" python3 - "$scratch" <<'PY'
from pathlib import Path
import sys
from verify_apk_certificate import fingerprint
root = Path(sys.argv[1])
assert fingerprint((root / "wrong.cert").read_text()) != fingerprint((root / "second.cert").read_text()), "Negative-control certificate must differ"
PY
if adb install -r "$scratch/wrong.apk" > "$evidence/rejected-install.txt" 2>&1; then
  echo "Android accepted a differently signed update!" >&2
  exit 1
fi
grep -q INSTALL_FAILED_UPDATE_INCOMPATIBLE "$evidence/rejected-install.txt"
test "$uid_before" = "$(adb shell run-as "$package" id -u | tr -d '\r')"
adb exec-out run-as "$package" tar -cf - shared_prefs app_webview > "$scratch/rejected.tar"
adb install -r "$second" | tee "$evidence/accepted-install.txt"
uid_after="$(adb shell run-as "$package" id -u | tr -d '\r')"
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
assert contents(root / "before.tar") == contents(root / "rejected.tar"), "Rejected update changed app data"
PY
open_profile after-update
node "$tool_dir/probe_webview.mjs" verify "$token" "$evidence/after-update.json"
adb exec-out screencap -p > "$evidence/after-update.png"
adb shell run-as "$package" cat app_webview/Default/upgrade-sentinel | grep -q 'webview-upgrade-fixture'
echo "PASS: Different certificate rejected; same-key update retained UID, files, visible profile, Secure/HttpOnly cookies and localStorage." | tee "$evidence/result.txt"
