#!/usr/bin/env python3
"""Public provider metadata and explicit outcomes for disposable-emulator tests."""
import argparse
import hashlib
import json
from pathlib import Path
import re


class UnsupportedProvider(ValueError):
    pass


def current_provider(text):
    match = re.search(r"Current WebView package \(name, version\): \(([^,]+), ([^)]+)\)", text)
    if not match:
        raise UnsupportedProvider("Android reports no active WebView provider")
    return {"package": match[1], "version": match[2]}


def candidate_provider(text, api, abis):
    def field(pattern):
        match = re.search(pattern, text)
        if not match:
            raise UnsupportedProvider(f"Provider metadata missing: {pattern}")
        return match[1]

    package = field(r"package: name='([^']+)'")
    if package != "com.android.webview":
        raise UnsupportedProvider("Expected the standalone AOSP System WebView")
    minimum = int(field(r"sdkVersion:'(\d+)'"))
    target = int(field(r"targetSdkVersion:'(\d+)'"))
    native = field(r"native-code: ([^\n]+)")
    if minimum > api or target < api:
        raise UnsupportedProvider("Provider SDK range is incompatible with the test image")
    if not set(re.findall(r"'([^']+)'", native)).intersection(abis.split(",")):
        raise UnsupportedProvider("Provider has no compatible native ABI")
    return {
        "package": package,
        "version": field(r"versionName='([^']+)'"),
        "versionCode": int(field(r"versionCode='(\d+)'")),
        "minSdk": minimum, "targetSdk": target,
    }


def changed(before, after, candidate):
    if after["package"] != candidate["package"] or after["version"] != candidate["version"]:
        raise UnsupportedProvider("Android did not activate the requested provider version")
    if before["version"] == after["version"]:
        raise UnsupportedProvider("Provider version did not change; no migration was exercised")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["preflight", "changed", "outcome"])
    parser.add_argument("evidence", type=Path)
    parser.add_argument("values", nargs="*")
    args = parser.parse_args()
    root = args.evidence
    report_path = root / "provider-result.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    try:
        if args.action == "preflight":
            report["stage"] = "compatibility"
            api, abis, apk = args.values
            report["before"] = current_provider((root / "provider-before.txt").read_text())
            report["candidate"] = candidate_provider(
                (root / "provider-candidate.badging").read_text(), int(api), abis)
            report["candidate"]["sha256"] = hashlib.sha256(Path(apk).read_bytes()).hexdigest()
            if report["before"]["version"] == report["candidate"]["version"]:
                raise UnsupportedProvider("Source and destination images contain the same WebView version")
            report.update(status="prepared", stage="compatibility")
        elif args.action == "changed":
            report["stage"] = "provider-activation"
            report["after"] = current_provider((root / "provider-after.txt").read_text())
            changed(report["before"], report["after"], report["candidate"])
            report.update(status="changed", stage="provider-activation")
        else:
            status, stage, reason = args.values
            report.update(status=status, stage=stage, reason=reason)
    except UnsupportedProvider as error:
        report.update(status="unsupported", reason=str(error))
        report_path.write_text(json.dumps(report, indent=2) + "\n")
        print(f"UNSUPPORTED (not a data-loss result): {error}")
        return 78
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
