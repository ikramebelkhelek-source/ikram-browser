#!/usr/bin/env python3
"""Write an honest CI summary; absent/incomplete evidence must never pass."""
import json
import os
from pathlib import Path


def summary(report):
    status = report["status"]
    descriptions = {
        "passed": "PASS — original data survived provider and app updates",
        "unsupported": "UNSUPPORTED — provider combination not tested; NOT a pass or data-loss failure",
        "data-loss": "FAIL — original synthetic cookies/localStorage were lost",
        "fixture-failure": "FAIL — initial synthetic data could not be persisted",
        "failed": "FAIL — test or infrastructure error; see evidence",
    }
    lines = ["## Separate System WebView migration check",
             descriptions.get(status, "FAIL — scenario did not finish")]
    for key in ("before", "candidate", "after"):
        provider = report.get(key)
        if provider:
            lines.append(f"- {key}: `{provider['package']}` version `{provider['version']}`")
    lines.append(f"- Stage: `{report.get('stage', 'unknown')}`")
    lines.append(f"- {report.get('reason', 'See uploaded evidence for details')}")
    lines.append("Disposable AOSP emulators, synthetic accounts-free storage, disposable app keys only.")
    return "\n".join(lines) + "\n"


def main():
    path = Path("generated-artifacts/android-webview-update/provider-result.json")
    report = json.loads(path.read_text()) if path.exists() else {
        "status": "failed", "stage": "setup", "reason": "No provider-result evidence was produced"}
    text = summary(report)
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(text)
    return 0 if report["status"] in ("passed", "unsupported") else 1


if __name__ == "__main__":
    raise SystemExit(main())
