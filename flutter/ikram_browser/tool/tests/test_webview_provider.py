import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_android_update import TOOL, load

provider = load("webview_provider")


def dump(version="74.0.3729.185", package="com.android.webview"):
    return (f"Current WebView package (name, version): ({package}, {version})\n"
            "WebView package dirty: false\n")


BADGING = """package: name='com.android.webview' versionCode='372918550' versionName='74.0.3729.185'
sdkVersion:'21'
targetSdkVersion:'29'
native-code: 'x86_64'
"""


class ProviderTests(unittest.TestCase):
    def test_supported_provider_and_real_version_change(self):
        candidate = provider.candidate_provider(BADGING, 28, "x86_64,x86")
        before = provider.current_provider(dump("66.0.3359.158"))
        after = provider.current_provider(dump())
        provider.changed(before, after, candidate)
        with self.assertRaises(provider.UnsupportedProvider):
            provider.changed(after, after, candidate)

    def test_incompatible_sdk_abi_package_and_missing_metadata_are_unsupported(self):
        for text, api, abis in (
            (BADGING, 19, "x86_64"), (BADGING, 35, "x86_64"),
            (BADGING, 28, "arm64-v8a"),
            (BADGING.replace("com.android.webview", "com.example.browser"), 28, "x86_64"),
            ("broken", 28, "x86_64"),
        ):
            with self.subTest(text=text, api=api, abis=abis):
                with self.assertRaises(provider.UnsupportedProvider):
                    provider.candidate_provider(text, api, abis)

    def test_missing_or_wrong_active_provider_is_not_success(self):
        candidate = provider.candidate_provider(BADGING, 28, "x86_64")
        with self.assertRaises(provider.UnsupportedProvider):
            provider.current_provider("Current WebView package is null")
        for after in (dump("66.0.3359.158"), dump(package="com.other.webview")):
            with self.assertRaises(provider.UnsupportedProvider):
                provider.changed(provider.current_provider(dump("66")), provider.current_provider(after), candidate)

    def run_switch(self, install_exit=0, install_text="Success", version="74.0.3729.185"):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            evidence = root / "evidence"
            evidence.mkdir()
            report = {"before": provider.current_provider(dump("66")),
                      "candidate": provider.candidate_provider(BADGING, 28, "x86_64"),
                      "status": "prepared"}
            (evidence / "provider-result.json").write_text(json.dumps(report))
            adb = root / "adb"
            adb.write_text(
                '#!/bin/bash\n'
                'case "$*" in\n'
                f'  "install -r candidate.apk") echo "{install_text}"; exit {install_exit};;\n'
                '  "shell cmd webviewupdate set-webview-implementation com.android.webview") echo Success;;\n'
                f'  "shell dumpsys webviewupdate") printf "%s" "{dump(version)}";;\n'
                '  *) exit 99;;\nesac\n')
            adb.chmod(0o755)
            result = subprocess.run(
                ["bash", "-c", 'set -Eeuo pipefail; source "$tool_dir/webview_provider.sh"; '
                 'change_provider; echo "stage=$stage"'],
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                     "tool_dir": str(TOOL), "evidence": str(evidence), "provider_apk": "candidate.apk"},
                text=True, capture_output=True)
            return result, json.loads((evidence / "provider-result.json").read_text())

    def test_switch_requires_active_new_version(self):
        result, report = self.run_switch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["status"], "changed")
        self.assertIn("stage=after-provider", result.stdout)
        result, report = self.run_switch(version="66")
        self.assertEqual(result.returncode, 78)
        self.assertEqual(report["status"], "unsupported")

    def test_only_known_compatibility_rejections_are_unsupported(self):
        for rejection in ("UPDATE_INCOMPATIBLE", "VERSION_DOWNGRADE", "OLDER_SDK",
                          "NO_MATCHING_ABIS", "MISSING_SHARED_LIBRARY"):
            result, report = self.run_switch(1, f"Failure [INSTALL_FAILED_{rejection}]")
            self.assertEqual(result.returncode, 78)
            self.assertEqual(report["status"], "unsupported")
        result, report = self.run_switch(1, "error: device offline")
        self.assertEqual(result.returncode, 1)
        self.assertNotEqual(report["status"], "unsupported")

    def test_summary_does_not_confuse_unsupported_with_pass_or_loss(self):
        summary = load("report_webview_update").summary
        self.assertIn("UNSUPPORTED", summary({"status": "unsupported"}))
        self.assertIn("NOT a pass", summary({"status": "unsupported"}))
        self.assertIn("FAIL", summary({"status": "data-loss"}))
        self.assertIn("FAIL", summary({"status": "changed"}))
        self.assertIn("PASS", summary({"status": "passed"}))

    def test_cli_preserves_provider_versions_in_failed_storage_result(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            apk = root / "provider.apk"
            apk.write_bytes(b"synthetic provider")
            (root / "provider-before.txt").write_text(dump("66"))
            (root / "provider-candidate.badging").write_text(BADGING)
            (root / "provider-after.txt").write_text(dump())
            for action, values in (
                ("preflight", ["28", "x86_64", str(apk)]), ("changed", []),
                ("outcome", ["data-loss", "after-provider", "Original cookie missing"]),
            ):
                result = subprocess.run(
                    ["python3", str(TOOL / "webview_provider.py"), action, str(root), *values],
                    text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((root / "provider-result.json").read_text())
            self.assertEqual(report["before"]["version"], "66")
            self.assertEqual(report["after"]["version"], "74.0.3729.185")
            self.assertEqual(len(report["candidate"]["sha256"]), 64)
            self.assertEqual(report["status"], "data-loss")

    def test_donor_collection_copies_only_the_standalone_provider(self):
        for paths, expected in (
            ("package:/system/app/webview/webview.apk", True),
            ("", False),
            ("package:/base.apk\\npackage:/split.apk", False),
        ):
            with self.subTest(paths=paths), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                log = root / "commands"
                adb = root / "adb"
                adb.write_text(
                    f'#!/bin/bash\necho "$*" >> "{log}"\ncase "$*" in\n'
                    '  "shell getprop ro.kernel.qemu") echo 1;;\n'
                    f'  "shell pm path com.android.webview") printf "{paths}\\n";;\n'
                    '  "pull "*) printf "synthetic provider" > "$3";;\n'
                    '  "shell getprop ro.build.fingerprint") echo synthetic-donor;;\n'
                    f'  "shell dumpsys webviewupdate") printf "{dump()}";;\n'
                    '  *) exit 99;;\nesac\n')
                adb.chmod(0o755)
                result = subprocess.run(
                    ["bash", str(TOOL / "collect_webview_provider.sh")], cwd=root,
                    env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}"},
                    capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((root / "generated-artifacts/webview-provider/provider.apk").exists(), expected)
                if not expected:
                    report = json.loads((root / "generated-artifacts/android-webview-update/provider-result.json").read_text())
                    self.assertEqual(report["status"], "unsupported")
                self.assertNotIn("install", log.read_text())

    def test_ci_wrapper_never_swallows_data_loss_or_unexplained_exit(self):
        for code, status, expected in (
            (0, "passed", 0), (3, "data-loss", 3),
            (1, "failed", 1), (78, "unsupported", 0), (78, "failed", 1),
        ):
            with self.subTest(code=code, status=status), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                evidence = root / "generated-artifacts/android-webview-update"
                evidence.mkdir(parents=True)
                fixture = root / "generated-artifacts/webview-provider/provider.apk"
                fixture.parent.mkdir()
                fixture.touch()
                (evidence / "provider-result.json").write_text(json.dumps({"status": status}))
                wrapper = root / "verify_webview_update.sh"
                wrapper.write_text((TOOL / wrapper.name).read_text())
                (root / "verify_android_update.sh").write_text(f"#!/bin/bash\nexit {code}\n")
                result = subprocess.run(["bash", str(wrapper), "first.apk", "second.apk"],
                                        cwd=root, capture_output=True)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_lane_only_uses_disposable_artifacts_and_distinct_emulators(self):
        workflow = (TOOL.parents[2] / ".github/workflows/android-apk.yml").read_text()
        lane = workflow.split("\n  verify-webview-update:")[1].split("\n  publish-tested-apk:")[0]
        self.assertIn("needs: build-test", lane)
        self.assertNotIn("secrets.", lane)
        self.assertNotIn("environment:", lane)
        self.assertNotIn("signed-apk", lane)
        self.assertIn("avd-name: webview-donor", lane)
        self.assertIn("avd-name: webview-migration", lane)
        script = (TOOL / "verify_android_update.sh").read_text()
        self.assertLess(script.index('getprop ro.kernel.qemu'), script.index('prepare_provider\n'))
        self.assertLess(script.index("node \"$tool_dir/probe_webview.mjs\" seed"), script.index("  change_provider\n"))
        self.assertLess(script.index("  change_provider\n"), script.index('adb install -r "$second"'))
        self.assertEqual(script.count('probe_webview.mjs" seed'), 1)
        self.assertIn('verify "$token" "$evidence/after-provider.json"', script)

    def test_new_entrypoints_refuse_physical_devices(self):
        for entry in ("collect_webview_provider.sh", "verify_android_update.sh"):
            with self.subTest(entry=entry), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                adb = root / "adb"
                log = root / "commands"
                adb.write_text(f'#!/bin/sh\necho "$*" >> "{log}"\necho 0\n')
                adb.chmod(0o755)
                apk = root / "candidate.apk"
                apk.touch()
                args = [] if entry.startswith("collect") else [str(apk), str(apk), "--webview-provider", str(apk)]
                result = subprocess.run(["bash", str(TOOL / entry), *args], cwd=root,
                                        env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}"},
                                        capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(log.read_text().strip(), "shell getprop ro.kernel.qemu")


if __name__ == "__main__":
    unittest.main()
