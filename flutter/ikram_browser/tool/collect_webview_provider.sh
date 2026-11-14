#!/usr/bin/env bash
# Run on the separate, freshly created AOSP donor emulator only.
set -Eeuo pipefail
test "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = "1"
evidence=generated-artifacts/android-webview-update
destination=generated-artifacts/webview-provider
tool_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$evidence" "$destination"
adb shell getprop ro.build.fingerprint > "$evidence/provider-donor-image.txt"
adb shell dumpsys webviewupdate > "$evidence/provider-donor.txt"
adb shell pm path com.android.webview > "$evidence/provider-donor-paths.txt"
mapfile -t paths < <(sed -n 's/^package://p' "$evidence/provider-donor-paths.txt" | tr -d '\r')
if [ "${#paths[@]}" -ne 1 ]; then
  python3 "$tool_dir/webview_provider.py" outcome "$evidence" unsupported donor \
    "SDK image has no standalone AOSP WebView APK (missing provider or split package)"
  exit 0
fi
adb pull "${paths[0]}" "$destination/provider.apk"
# Keep only public metadata in uploaded evidence, not another large binary.
sha256sum "$destination/provider.apk" > "$evidence/provider-donor-sha256.txt"
