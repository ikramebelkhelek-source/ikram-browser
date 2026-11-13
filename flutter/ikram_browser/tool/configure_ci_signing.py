"""Restore a CI-only key; fail closed rather than use a runner's debug key."""
import base64
import binascii
import hashlib
import os
from pathlib import Path
import subprocess
import sys

REQUIRED = (
    "ANDROID_KEYSTORE_BASE64", "ANDROID_STORE_PASSWORD", "ANDROID_KEY_PASSWORD",
    "ANDROID_KEY_ALIAS", "ANDROID_SIGNING_CERT_SHA256", "RUNNER_TEMP",
)
MARKER = "// Protected CI signing (no credentials in generated source)."
GRADLE = """
// Protected CI signing (no credentials in generated source).
android {
    signingConfigs {
        getByName("debug") {
            storeFile = file(System.getenv("RUNNER_TEMP") + "/ikram-ci-signing.jks")
            storePassword = System.getenv("ANDROID_STORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
}
"""


def configure():
    if any(not os.environ.get(key) for key in REQUIRED):
        raise ValueError("Missing protected CI signing settings; refusing random debug signing.")
    gradle = Path("android/app/build.gradle.kts")
    source = gradle.read_text()
    # This ID is the update identity of the existing generated Android app.
    if 'applicationId = "com.ikram.ikram_browser"' not in source:
        raise ValueError("Unexpected Android application ID; refusing an incompatible update.")
    if MARKER in source:
        raise ValueError("CI signing has already been configured.")
    key = Path(os.environ["RUNNER_TEMP"]) / "ikram-ci-signing.jks"
    try:
        data = base64.b64decode(os.environ["ANDROID_KEYSTORE_BASE64"], validate=True)
        with os.fdopen(os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
            stream.write(data)
        certificate = subprocess.run(
            ["keytool", "-exportcert", "-keystore", str(key),
             "-storepass:env", "ANDROID_STORE_PASSWORD",
             "-alias", os.environ["ANDROID_KEY_ALIAS"]],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        ).stdout
        if hashlib.sha256(certificate).hexdigest() != os.environ["ANDROID_SIGNING_CERT_SHA256"].lower():
            raise ValueError("Protected certificate does not match the signing identity.")
        gradle.write_text(source + GRADLE)
    except Exception:
        key.unlink(missing_ok=True)
        raise


if __name__ == "__main__":
    try:
        configure()
    except (ValueError, OSError, binascii.Error, subprocess.CalledProcessError):
        # Never echo command output, environment contents, or keystore data.
        sys.exit("CI signing configuration failed. Check protected secrets and Android application ID.")
