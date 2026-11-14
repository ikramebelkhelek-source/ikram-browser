#!/usr/bin/env bash
# Trusted GitHub runner only. Retain the ORIGINAL APK, without any signing key.
set -Eeuo pipefail
tool_dir="$(cd "$(dirname "$0")" && pwd)"
manifest="$tool_dir/android-update-baseline.json"
output=generated-artifacts/android-baseline
mkdir -p "$output"
readarray -t pin < <(python3 - "$manifest" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for key in ("repository", "release_tag", "asset", "source_commit", "source_artifact_id"):
    print(data[key])
PY
)
repo="${pin[0]}"
tag="${pin[1]}"
apk="$output/${pin[2]}"
if python3 "$tool_dir/android_baseline.py" fetch "$apk"; then
  python3 "$tool_dir/android_baseline.py" verify "$apk"
  exit 0
else
  status=$?
  if [ "$status" -ne 4 ]; then
    echo "Existing baseline could not be verified; refusing to replace it." >&2
    exit "$status"
  fi
fi
# Bootstrap only from this pinned successful earlier run's retained artifact.
# If it has expired, fail rather than build old source with today's dependencies.
gh api "repos/$repo/actions/artifacts/${pin[4]}/zip" > "$output/original.zip"
python3 "$tool_dir/android_baseline.py" extract "$apk" --archive "$output/original.zip"
python3 "$tool_dir/android_baseline.py" verify "$apk"
if ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release create "$tag" --repo "$repo" --target "${pin[3]}" --draft \
    --prerelease --latest=false --title "Android update CI baseline (versionCode 30)" \
    --notes "Original historical APK for synthetic emulator migration tests only. Not a new production release. Public integrity and certificate metadata: android-update-baseline.json."
fi
# No --clobber: never replace the historical binary, even on a retry.
if [ ! -s "$apk" ]; then
  echo "Historical APK file is unavailable; skipping optional retention." >&2
  exit 4
fi
gh release upload "$tag" "$apk" "$manifest" --repo "$repo"
gh release edit "$tag" --repo "$repo" --draft=false --prerelease --latest=false
python3 "$tool_dir/android_baseline.py" fetch "$output/retained.apk"
python3 "$tool_dir/android_baseline.py" verify "$output/retained.apk"
