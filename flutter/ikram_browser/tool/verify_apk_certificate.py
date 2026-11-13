"""Verify apksigner output without printing certificate or secret values."""
import os
from pathlib import Path
import re
import sys


def fingerprint(text):
    # Build Tools 37 labels this "V2 Signer:" instead of "Signer #1".
    # It may report the same certificate once per signing scheme. Check EVERY
    # certificate digest, rather than silently ignoring an unfamiliar label.
    lines = [line.strip() for line in text.splitlines()
             if "certificate SHA-256 digest:" in line]
    digests = set()
    for line in lines:
        match = re.fullmatch(r".+ certificate SHA-256 digest: ([0-9a-fA-F]{64})", line)
        if not match:
            raise ValueError("Malformed APK certificate digest.")
        digests.add(match[1].lower())
    if len(digests) != 1:
        raise ValueError("Expected exactly one distinct APK signing certificate.")
    return digests.pop()


if __name__ == "__main__":
    try:
        actual = fingerprint(Path(sys.argv[1]).read_text())
        expected = os.environ["ANDROID_SIGNING_CERT_SHA256"].lower()
        if actual != expected:
            raise ValueError("Certificate mismatch.")
    except ValueError as error:
        # These are fixed diagnostic strings, never values from the file/secrets.
        sys.exit(str(error))
    except (OSError, KeyError, IndexError):
        sys.exit("APK signing certificate verification failed.")
    print("APK matches the protected signing identity.")
