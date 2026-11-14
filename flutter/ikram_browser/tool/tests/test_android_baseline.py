"""Fail-closed tests for retained-release integrity, provenance and CI wiring."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
import zipfile


TOOL = Path(__file__).resolve().parents[1]
ROOT = TOOL.parents[2]
spec = importlib.util.spec_from_file_location("android_baseline", TOOL / "android_baseline.py")
baseline = importlib.util.module_from_spec(spec)
# unittest discovery also imports the signing tests; make the tool importable
# when this file is run by itself.
import sys
sys.path.insert(0, str(TOOL))
spec.loader.exec_module(baseline)


class BaselineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.apk = self.root / "baseline.apk"
        self.apk.write_bytes(b"an original earlier signed APK")
        self.data = baseline.manifest(baseline.DEFAULT_MANIFEST)
        self.data["sha256"] = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.cert = f"V2 Signer: certificate SHA-256 digest: {self.data['certificate_sha256']}\n"
        self.badging = ("package: name='com.ikram.ikram_browser' versionCode='30' "
                        "versionName='1.0.0'\napplication-debuggable\n")

    def check(self, **overrides):
        baseline.check_reports(
            overrides.get("apk", self.apk), overrides.get("data", self.data),
            overrides.get("certificate", self.cert),
            overrides.get("badging", self.badging),
            overrides.get("current_source", "a" * 40))

    def test_original_fixture_is_accepted_without_signing_credentials(self):
        with patch.dict("os.environ", {}, clear=True):
            self.check()

    def test_corrupt_or_rebuilt_apk_is_rejected(self):
        self.apk.write_bytes(b"same app rebuilt today")
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.check()

    def test_different_or_multiple_signers_are_rejected(self):
        for cert in (
            f"Signer #1 certificate SHA-256 digest: {'b' * 64}",
            self.cert + f"Signer #2 certificate SHA-256 digest: {'b' * 64}",
            "unknown signing report",
        ):
            with self.subTest(cert=cert), self.assertRaises(ValueError):
                self.check(certificate=cert)

    def test_wrong_package_version_or_non_debuggable_is_rejected(self):
        for text in (
            self.badging.replace("com.ikram.ikram_browser", "other.app"),
            self.badging.replace("'30'", "'31'"),
            self.badging.replace("application-debuggable", ""),
        ):
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.check(badging=text)

    def test_same_source_is_not_a_historical_migration(self):
        with self.assertRaisesRegex(ValueError, "cross source revisions"):
            self.check(current_source=self.data["source_commit"])

    def test_manifest_accepts_only_public_fields_and_safe_identifiers(self):
        for field, value in (
            ("private_key", "not allowed"),
            ("asset", "../wrong.apk"),
            ("repository", "other/owner/repo"),
            ("version_code", True),
            ("certificate_sha256", "not-a-fingerprint"),
        ):
            data = {**self.data, field: value}
            path = self.root / "manifest.json"
            path.write_text(json.dumps(data))
            with self.subTest(field=field), self.assertRaises(ValueError):
                baseline.manifest(path)

    def test_fetch_checks_hash_before_replacing_destination(self):
        original = self.apk.read_bytes()
        response = contextlib.closing(io.BytesIO(b"corrupt asset"))
        with patch.object(baseline, "urlopen", return_value=response):
            with self.assertRaisesRegex(ValueError, "checksum"):
                baseline.fetch(self.data, self.apk)
        self.assertEqual(self.apk.read_bytes(), original)
        response = contextlib.closing(io.BytesIO(original))
        with patch.object(baseline, "urlopen", return_value=response) as fetch:
            baseline.fetch(self.data, self.apk)
        self.assertEqual(self.apk.read_bytes(), original)
        self.assertEqual(fetch.call_args.args[0],
                         "https://github.com/ikramebelkhelek-source/ikram-browser/"
                         "releases/download/android-update-baseline-v30/ikram-browser-debug.apk")

    def test_missing_asset_has_no_rebuild_fallback(self):
        with patch.object(baseline, "urlopen", side_effect=HTTPError(
                "https://github.com/test", 404, "missing", {}, None)):
            with self.assertRaises(HTTPError):
                baseline.fetch(self.data, self.apk)

    def test_artifact_extracts_only_the_expected_apk(self):
        archive = self.root / "original.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.writestr(self.data["asset"], self.apk.read_bytes())
            zipped.writestr("../unexpected.jks", b"must never be extracted")
        destination = self.root / "extracted.apk"
        baseline.extract(archive, destination, self.data)
        self.assertEqual(destination.read_bytes(), self.apk.read_bytes())
        self.assertFalse((self.root.parent / "unexpected.jks").exists())

    def test_expired_corrupt_or_wrong_artifact_cannot_replace_baseline(self):
        for contents in ({"other.apk": b"wrong asset"},
                         {self.data["asset"]: b"wrong APK"}):
            archive = self.root / "wrong.zip"
            with zipfile.ZipFile(archive, "w") as zipped:
                for name, data in contents.items():
                    zipped.writestr(name, data)
            with self.subTest(contents=contents), self.assertRaises(ValueError):
                baseline.extract(archive, self.apk, self.data)
            self.assertEqual(self.apk.read_bytes(), b"an original earlier signed APK")

    def test_script_seeds_only_before_update_using_the_first_apps_ui(self):
        script = (TOOL / "verify_android_update.sh").read_text()
        before, after = script.split('adb install -r "$second"')
        self.assertIn("\nseed_profiles\n", before)
        self.assertNotIn("\nseed_profiles\n", after)
        self.assertNotIn('probe_webview.mjs" seed', after)
        self.assertEqual(script.count('probe_webview.mjs" seed'), 1)
        self.assertNotIn("FlutterSharedPreferences.xml", script)
        self.assertIn("tap_label 'إضافة بروفايل'", before)
        self.assertIn("tap_label 'حفظ'", before)
        self.assertIn("open_profile after-update-cold-start", after)
        self.assertIn('probe_webview.mjs" verify', after)
        self.assertNotIn("pm clear", script)
        self.assertNotIn("adb uninstall", script)

    def test_historical_lane_is_optional_only_when_baseline_is_unavailable(self):
        workflow = (ROOT / ".github/workflows/android-apk.yml").read_text()
        publish = workflow.split("  publish-tested-apk:")[1].split("  verify-historical-update:")[0]
        self.assertIn("needs: [build, verify-update, retain-baseline, verify-historical-update]", publish)
        self.assertIn("needs.verify-historical-update.result == 'success'", publish)
        self.assertIn("needs.retain-baseline.outputs.available == 'false'", publish)
        self.assertIn("needs.verify-historical-update.result == 'skipped'", publish)
        self.assertIn("needs.retain-baseline.result == 'success'", publish)
        self.assertIn("This is not a historical-migration pass", publish)
        historic = workflow.split("  verify-historical-update:")[1]
        self.assertIn("android_baseline.py fetch", historic)
        self.assertIn("signed-apk-2-", historic)
        self.assertIn("android-update-baseline.json", historic)
        self.assertIn("needs.retain-baseline.outputs.available == 'true'", historic)
        self.assertNotIn("secrets.", historic)
        retain = workflow.split("  retain-baseline:")[1].split("  build-test:")[0]
        self.assertNotIn("secrets.", retain)
        self.assertNotIn("environment: android-signing", retain)
        self.assertIn("github.ref == format('refs/heads/{0}'", retain)
        retention_script = (TOOL / "retain_android_baseline.sh").read_text()
        self.assertNotIn("flutter build", retention_script)
        self.assertNotIn("apksigner sign", retention_script)
        self.assertNotIn(" --clobber", retention_script.replace("# No --clobber:", "#"))
        self.assertIn('if [ "$status" -ne 4 ]', retention_script)

    def test_optional_workflow_handles_only_unavailable_exit_as_skip(self):
        workflow = (ROOT / ".github/workflows/android-apk.yml").read_text()
        retention = workflow.split("  retain-baseline:")[1].split("  build-test:")[0]
        script = textwrap.dedent(retention.split("        run: |\n", 1)[1])
        command = "bash flutter/ikram_browser/tool/retain_android_baseline.sh"
        self.assertIn(command, script)
        for status in (0, 4, 1, 2):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fake = root / "retention.sh"
                fake.write_text(f"exit {status}\n")
                output, summary = root / "output", root / "summary"
                result = subprocess.run(
                    ["bash", "-e", "-c", script.replace(command, 'bash "$FAKE_RETENTION"')],
                    env={**os.environ, "FAKE_RETENTION": str(fake),
                         "GITHUB_OUTPUT": str(output), "GITHUB_STEP_SUMMARY": str(summary)},
                    capture_output=True, text=True,
                )
                if status == 0:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output.read_text(), "available=true\n")
                elif status == 4:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output.read_text(), "available=false\n")
                    self.assertIn("skipped, not passed", summary.read_text())
                else:
                    self.assertEqual(result.returncode, status)
                    self.assertFalse(output.exists())

    def run_retention(self, fetch_status, artifact_status=0, extract_apk=True):
        """Exercise the orchestration without network, SDK or credentials."""
        commands = self.root / "commands"
        commands.mkdir()
        extraction = ('mkdir -p "$(dirname "$3")"; printf baseline > "$3";'
                      if extract_apk else ":;")
        python = commands / "python3"
        python.write_text(
            "#!/usr/bin/env bash\nset -eu\n"
            'if [[ "$1" != *android_baseline.py ]]; then\n'
            f'  exec "{sys.executable}" "$@"\nfi\n'
            f'echo "python $2" >> "{self.root}/calls"\n'
            'case "$2" in\n'
            f'fetch) if [ ! -e "{self.root}/fetched" ]; then\n'
            f'  touch "{self.root}/fetched"; exit {fetch_status}; fi;;\n'
            f'extract) {extraction};\n'
            'verify) ;;\n'
            '*) exit 99;;\nesac\n')
        gh = commands / "gh"
        gh.write_text(
            "#!/usr/bin/env bash\nset -eu\n"
            f'echo "gh $*" >> "{self.root}/calls"\n'
            f'if [ "$1" = api ]; then printf original; exit {artifact_status}; fi\n'
        )
        python.chmod(0o755)
        gh.chmod(0o755)
        result = subprocess.run(
            ["bash", str(TOOL / "retain_android_baseline.sh")], cwd=self.root,
            env={**os.environ, "PATH": f"{commands}:{os.environ['PATH']}"},
            capture_output=True, text=True)
        return result, (self.root / "calls").read_text()

    def test_retention_reuses_verified_permanent_asset_without_any_write(self):
        result, calls = self.run_retention(fetch_status=0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.splitlines(), ["python fetch", "python verify"])

    def test_retention_never_replaces_corrupt_or_temporarily_unavailable_asset(self):
        result, calls = self.run_retention(fetch_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to replace", result.stderr)
        self.assertNotIn("gh ", calls)

    def test_retention_bootstraps_only_pinned_artifact_then_verifies_public_copy(self):
        result, calls = self.run_retention(fetch_status=4)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"actions/artifacts/{self.data['source_artifact_id']}/zip", calls)
        self.assertIn("python extract\npython verify\ngh release view", calls)
        self.assertIn("gh release upload android-update-baseline-v30", calls)
        self.assertIn("android-update-baseline.json --repo", calls)
        self.assertTrue(calls.endswith("python fetch\npython verify\n"))
        self.assertNotIn("--clobber", calls)

    def test_expired_bootstrap_artifact_blocks_retention(self):
        result, calls = self.run_retention(fetch_status=4, artifact_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("release upload", calls)
        self.assertNotIn("python extract", calls)

    def test_missing_local_apk_is_optional_unavailable_not_an_upload(self):
        result, calls = self.run_retention(fetch_status=4, extract_apk=False)
        self.assertEqual(result.returncode, 4, result.stderr)
        self.assertIn("Historical APK file is unavailable", result.stderr)
        self.assertNotIn("release upload", calls)


if __name__ == "__main__":
    unittest.main()
