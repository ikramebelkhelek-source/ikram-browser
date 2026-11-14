#!/usr/bin/env bash
# Sourced only by verify_android_update.sh, after its disposable-device guard.
provider_report() {
  python3 "$tool_dir/webview_provider.py" "$1" "$evidence" "${@:2}"
}
provider_unsupported() {
  provider_report outcome unsupported "$stage" "$1"
  echo "UNSUPPORTED (not a data-loss result): $1" >&2
  exit 78
}
prepare_provider() {
  stage=provider-compatibility
  # Refuse privileged changes: no root, remount, signature bypass or downgrade.
  adb shell dumpsys webviewupdate > "$evidence/provider-before.txt"
  adb shell getprop ro.build.fingerprint > "$evidence/provider-target-image.txt"
  "$tools/apksigner" verify --print-certs "$provider_apk" > "$evidence/provider-candidate.cert"
  "$tools/aapt" dump badging "$provider_apk" > "$evidence/provider-candidate.badging"
  provider_report preflight \
    "$(adb shell getprop ro.build.version.sdk | tr -d '\r')" \
    "$(adb shell getprop ro.product.cpu.abilist | tr -d '\r')" "$provider_apk"
}
change_provider() {
  stage=provider-install
  if ! adb install -r "$provider_apk" > "$evidence/provider-install.txt" 2>&1; then
    # Only known platform compatibility rejections are unsupported. Timeouts,
    # transport failures, out-of-space etc. remain failing infrastructure checks.
    if grep -Eq 'INSTALL_FAILED_(UPDATE_INCOMPATIBLE|VERSION_DOWNGRADE|OLDER_SDK|NO_MATCHING_ABIS|MISSING_SHARED_LIBRARY)' "$evidence/provider-install.txt"; then
      provider_unsupported "Android rejected the provider APK; see provider-install.txt"
    fi
    cat "$evidence/provider-install.txt" >&2
    return 1
  fi
  stage=provider-activation
  adb shell cmd webviewupdate set-webview-implementation com.android.webview \
    > "$evidence/provider-selection.txt"
  for attempt in $(seq 1 30); do
    adb shell dumpsys webviewupdate > "$evidence/provider-after.txt"
    if grep -q 'WebView package dirty: false' "$evidence/provider-after.txt"; then
      break
    fi
    sleep 1
  done
  provider_report changed
  # From here on, failure to launch/probe is NOT called unsupported.
  stage=after-provider
}
