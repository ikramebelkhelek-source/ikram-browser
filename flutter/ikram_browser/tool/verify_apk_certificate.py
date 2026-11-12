"""Verify apksigner output without printing certificate or secret values."""
import os
from pathlib import Path
import re
import sys


def fingerprint(text):
    matches = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$", text, re.M)
    if len(matches) != 1:
        raise ValueError("Expected exactly one APK signer.")
    return matches[0].lower()


if __name__ == "__main__":
    try:
        actual = fingerprint(Path(sys.argv[1]).read_text())
        expected = os.environ["ANDROID_SIGNING_CERT_SHA256"].lower()
        if actual != expected:
            raise ValueError("Certificate mismatch.")
    except (ValueError, OSError, KeyError, IndexError):
        sys.exit("APK signing certificate verification failed.")
    print("APK matches the protected signing identity.")
