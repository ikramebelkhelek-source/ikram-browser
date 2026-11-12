"""One-time administrator setup. Requires authenticated gh and Java keytool.

Private material is generated in a mode-0700 temporary directory, sent directly
to GitHub's encrypted environment-secret store, and removed even on failure.
Never run with shell tracing or log subprocess input.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile

NAMES = (
    "ANDROID_STORE_PASSWORD", "ANDROID_KEY_PASSWORD", "ANDROID_KEY_ALIAS",
    "ANDROID_SIGNING_CERT_SHA256", "ANDROID_KEYSTORE_BASE64",
)


def gh_json(*args, body=None):
    result = subprocess.run(
        ["gh", "api", *args, *([] if body is None else ["--input", "-"])],
        input=None if body is None else json.dumps(body).encode(),
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True,
    )
    return json.loads(result.stdout) if result.stdout else None


def provision(repo):
    prefix = f"repos/{repo}/environments/android-signing"
    # This is deliberately a first-time setup tool, not an environment editor.
    # Do not weaken existing reviewer/branch rules, even when secrets are absent.
    page = 1
    while True:
        environments = gh_json(f"repos/{repo}/environments?per_page=100&page={page}")["environments"]
        if any(e["name"] == "android-signing" for e in environments):
            raise ValueError("Signing environment already exists; preserve its identity and protections.")
        if len(environments) < 100:
            break
        page += 1
    # Configure the branch restriction BEFORE storing any key.
    gh_json(prefix, "--method", "PUT", body={
        "deployment_branch_policy": {
            "protected_branches": False, "custom_branch_policies": True,
        },
    })
    policies = gh_json(f"{prefix}/deployment-branch-policies")["branch_policies"]
    if not any(p["name"] == "main" and p["type"] == "branch" for p in policies):
        gh_json(f"{prefix}/deployment-branch-policies", "--method", "POST",
                body={"name": "main", "type": "branch"})
    existing = gh_json(f"{prefix}/secrets")["secrets"]
    if any(s["name"] in NAMES for s in existing):
        raise ValueError("Signing secrets already exist; never replace an established signing identity.")
    with tempfile.TemporaryDirectory(prefix="ikram-signing-") as directory:
        key = Path(directory) / "identity.jks"
        password = secrets.token_urlsafe(48)
        alias = "ikram-ci"
        env = dict(os.environ, IKRAM_SETUP_PASSWORD=password)
        subprocess.run(
            ["keytool", "-genkeypair", "-noprompt", "-storetype", "JKS",
             "-keystore", str(key), "-alias", alias, "-keyalg", "RSA",
             "-keysize", "3072", "-validity", "36500",
             "-dname", "CN=Ikram Browser CI",
             "-storepass:env", "IKRAM_SETUP_PASSWORD",
             "-keypass:env", "IKRAM_SETUP_PASSWORD"],
            env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        certificate = subprocess.run(
            ["keytool", "-exportcert", "-keystore", str(key), "-alias", alias,
             "-storepass:env", "IKRAM_SETUP_PASSWORD"],
            env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        ).stdout
        values = (password, password, alias, hashlib.sha256(certificate).hexdigest(),
                  base64.b64encode(key.read_bytes()).decode())
        for name, value in zip(NAMES, values):
            subprocess.run(
                ["gh", "secret", "set", name, "--repo", repo, "--env", "android-signing"],
                input=value.encode(), check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
    print("Protected signing identity created. No key or passwords were printed or retained locally.")


if __name__ == "__main__":
    try:
        provision(sys.argv[1])
    except (IndexError, ValueError, OSError, subprocess.CalledProcessError):
        sys.exit("Signing setup refused or failed. Preserve existing environment/secrets; inspect names and access only.")
