#!/usr/bin/env bash
# Convert ONLY the documented unsupported exit into a non-failing CI result.
# The uploaded JSON/summary still says UNSUPPORTED, never PASS.
set -Eeuo pipefail
tool_dir="$(cd "$(dirname "$0")" && pwd)"
evidence=generated-artifacts/android-webview-update
provider=generated-artifacts/webview-provider/provider.apk
if [ ! -f "$provider" ]; then
  # The donor may have explicitly reported an unsupported split/absent provider.
  python3 - "$evidence/provider-result.json" <<'PY'
import json
import sys
assert json.load(open(sys.argv[1]))["status"] == "unsupported", "Missing provider fixture"
PY
  exit 0
fi
code=0
bash "$tool_dir/verify_android_update.sh" "$@" --webview-provider "$provider" || code=$?
if [ "$code" -eq 78 ]; then
  python3 - "$evidence/provider-result.json" <<'PY'
import json
import sys
assert json.load(open(sys.argv[1]))["status"] == "unsupported", "Unexplained unsupported exit"
PY
  echo "::notice::WebView combination unsupported; migration was NOT verified. See provider evidence."
  exit 0
fi
exit "$code"
