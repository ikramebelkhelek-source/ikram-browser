"""Download and verify the original historical APK; never rebuild or re-sign it.

The checked-in manifest is the trust anchor. Only public integrity/provenance
metadata belongs here. No signing credentials are needed by this tool.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.error import HTTPError
from urllib.request import urlopen
import zipfile

from verify_apk_certificate import fingerprint


DEFAULT_MANIFEST = Path(__file__).with_name("android-update-baseline.json")
FIELDS = {
    "schema", "repository", "release_tag", "asset", "sha256", "certificate_sha256",
    "application_id", "version_code", "source_commit", "source_run_id",
    "source_artifact_id", "test_api",
}


def manifest(path):
    data = json.loads(Path(path).read_text())
    if set(data) != FIELDS or data["schema"] != 1:
        raise ValueError("Unexpected baseline manifest schema")
    patterns = {
        "repository": r"[\w.-]+/[\w.-]+",
        "release_tag": r"[\w.-]+",
        "asset": r"[\w.-]+\.apk",
        "sha256": r"[a-f0-9]{64}",
        "certificate_sha256": r"[a-f0-9]{64}",
        "application_id": r"[a-z][a-z0-9_.]+",
        "source_commit": r"[a-f0-9]{40}",
    }
    for field, pattern in patterns.items():
        if not isinstance(data[field], str) or not re.fullmatch(pattern, data[field]):
            raise ValueError(f"Invalid public baseline field: {field}")
    for field in ("version_code", "source_run_id", "source_artifact_id", "test_api"):
        if type(data[field]) is not int or data[field] <= 0:
            raise ValueError(f"Invalid public baseline field: {field}")
    return data


def check_hash(apk, data):
    with Path(apk).open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    if digest != data["sha256"]:
        raise ValueError("Historical APK checksum mismatch; do not rebuild or re-sign it")


def check_reports(apk, data, certificate, badging, current_source=None):
    check_hash(apk, data)
    if fingerprint(certificate) != data["certificate_sha256"]:
        raise ValueError("Historical APK certificate differs from the pinned permanent identity")
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)'", badging, re.M)
    if not package or (package[1], int(package[2])) != (
            data["application_id"], data["version_code"]):
        raise ValueError("Historical APK application ID or versionCode mismatch")
    if not re.search(r"^application-debuggable\s*$", badging, re.M):
        raise ValueError("The historical storage probe requires the original debuggable APK")
    if current_source is not None:
        if not re.fullmatch(r"[a-f0-9]{40}", current_source):
            raise ValueError("Expected the full current source commit")
        if current_source == data["source_commit"]:
            raise ValueError("Historical update must cross source revisions")


def verify(apk, data, build_tools, current_source=None):
    # Check bytes before invoking native tools on a downloaded binary.
    check_hash(apk, data)
    certificate = subprocess.check_output(
        [str(build_tools / "apksigner"), "verify", "--print-certs", str(apk)], text=True)
    badging = subprocess.check_output(
        [str(build_tools / "aapt"), "dump", "badging", str(apk)], text=True)
    check_reports(apk, data, certificate, badging, current_source)


def fetch(data, destination):
    """Fetch a permanent release asset, atomically, with a pinned content hash."""
    url = (f"https://github.com/{data['repository']}/releases/download/"
           f"{data['release_tag']}/{data['asset']}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as tmp:
        candidate = Path(tmp) / data["asset"]
        with urlopen(url, timeout=120) as response, candidate.open("wb") as output:
            shutil.copyfileobj(response, output)
        check_hash(candidate, data)
        candidate.replace(destination)


def extract(archive, destination, data):
    # Read only the expected APK, never unpack arbitrary ZIP paths or key files.
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as tmp:
        candidate = Path(tmp) / data["asset"]
        with zipfile.ZipFile(archive) as zipped:
            if zipped.namelist().count(data["asset"]) != 1:
                raise ValueError("Source artifact must contain exactly one baseline APK")
            with zipped.open(data["asset"]) as source, candidate.open("wb") as output:
                shutil.copyfileobj(source, output)
        check_hash(candidate, data)
        candidate.replace(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("fetch", "extract", "verify"))
    parser.add_argument("apk", type=Path)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--build-tools", type=Path)
    parser.add_argument("--current-source")
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    data = manifest(args.manifest)
    if args.operation == "fetch":
        fetch(data, args.apk)
    elif args.operation == "extract":
        if args.archive is None:
            parser.error("extract requires --archive")
        extract(args.archive, args.apk, data)
    else:
        tools = args.build_tools
        if tools is None:
            tools = max((Path(os.environ["ANDROID_HOME"]) / "build-tools").iterdir(),
                        key=lambda path: tuple(int(n) for n in re.findall(r"\d+", path.name)))
        verify(args.apk, data, tools, args.current_source)
    if args.evidence:
        args.evidence.write_text(json.dumps(data, indent=2) + "\n")
    print(f"PASS: historical APK {args.operation}; pinned public metadata matched")


if __name__ == "__main__":
    try:
        main()
    except HTTPError as error:
        # Only a missing public release may trigger the one-time retention job.
        # Integrity failures and server/network errors must fail closed.
        sys.exit(4 if error.code == 404 else 1)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError,
            zipfile.BadZipFile) as error:
        sys.exit(f"Historical APK check failed: {error}")
