import base64
import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

TOOL = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOL / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


signing = load("configure_ci_signing")
certificate = load("verify_apk_certificate")
provisioning = load("provision_ci_signing")


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        previous = Path.cwd()
        os.chdir(self.temp.name)
        self.addCleanup(os.chdir, previous)
        self.gradle = Path("android/app/build.gradle.kts")
        self.gradle.parent.mkdir(parents=True)
        self.source = 'android { defaultConfig { applicationId = "com.ikram.ikram_browser" } }\n'
        self.gradle.write_text(self.source)
        self.environment = {
            "RUNNER_TEMP": self.temp.name,
            "ANDROID_KEYSTORE_BASE64": base64.b64encode(b"test-keystore").decode(),
            "ANDROID_STORE_PASSWORD": "test-only",
            "ANDROID_KEY_PASSWORD": "test-only",
            "ANDROID_KEY_ALIAS": "test-only",
            "ANDROID_SIGNING_CERT_SHA256": hashlib.sha256(b"test-cert").hexdigest(),
        }
        self.env = patch.dict(os.environ, self.environment, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_missing_each_setting_fails_closed(self):
        for name in signing.REQUIRED:
            with self.subTest(name=name), patch.dict(os.environ, {name: ""}):
                with self.assertRaises(ValueError):
                    signing.configure()
        self.assertEqual(self.gradle.read_text(), self.source)

    def test_bad_base64_never_writes_gradle(self):
        os.environ["ANDROID_KEYSTORE_BASE64"] = "not base64!"
        with self.assertRaises(ValueError):
            signing.configure()
        self.assertEqual(self.gradle.read_text(), self.source)

    def test_wrong_app_id_fails_closed(self):
        self.gradle.write_text('applicationId = "wrong.app"')
        with self.assertRaises(ValueError):
            signing.configure()

    @patch.object(signing.subprocess, "run")
    def test_correct_identity_configures_no_password_literals(self, run):
        run.return_value.stdout = b"test-cert"
        signing.configure()
        source = self.gradle.read_text()
        self.assertIn('getByName("debug")', source)
        self.assertNotIn("test-only", source)
        self.assertEqual(Path("ikram-ci-signing.jks").stat().st_mode & 0o777, 0o600)
        with self.assertRaises(ValueError):
            signing.configure()

    @patch.object(signing.subprocess, "run")
    def test_wrong_certificate_removes_private_key(self, run):
        run.return_value.stdout = b"other-cert"
        with self.assertRaises(ValueError):
            signing.configure()
        self.assertFalse(Path("ikram-ci-signing.jks").exists())
        self.assertEqual(self.gradle.read_text(), self.source)

    @patch.object(signing.subprocess, "run", side_effect=OSError("keytool failed"))
    def test_keytool_failure_removes_private_key(self, run):
        with self.assertRaises(OSError):
            signing.configure()
        self.assertFalse(Path("ikram-ci-signing.jks").exists())

    def test_parse_single_certificate(self):
        digest = "a" * 64
        text = f"Signer #1 certificate SHA-256 digest: {digest}\n"
        self.assertEqual(certificate.fingerprint(text), digest)
        for invalid in ("", text + text.replace(digest, "b" * 64),
                        "Signer #1 certificate SHA-256 digest: invalid"):
            with self.assertRaises(ValueError):
                certificate.fingerprint(invalid)

    def test_build_tools_37_scheme_labels(self):
        digest = "a" * 64
        text = f"V2 Signer: certificate SHA-256 digest: {digest}\r\n"
        text += f"V3 Signer: certificate SHA-256 digest: {digest.upper()}\r\n"
        self.assertEqual(certificate.fingerprint(text), digest)
        with self.assertRaises(ValueError):
            certificate.fingerprint(text + f"V3.1 Signer: certificate SHA-256 digest: {'b' * 64}\n")

    @patch.object(provisioning, "gh_json")
    def test_provisioning_never_modifies_an_existing_environment(self, gh):
        gh.return_value = {"environments": [{"name": "android-signing"}]}
        with self.assertRaises(ValueError):
            provisioning.provision("test/repo")
        gh.assert_called_once_with("repos/test/repo/environments?per_page=100&page=1")


if __name__ == "__main__":
    unittest.main()
