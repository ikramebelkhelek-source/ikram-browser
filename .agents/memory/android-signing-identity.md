---
name: Android signing identity
description: Diagnose certificate checks without accidentally replacing the permanent update key.
---

Treat a certificate-check failure as a possible tool-output compatibility issue
before assuming the private key is wrong. Never regenerate the CI identity as a
way to repair a verification failure.

**Why:** A correctly signed APK was initially rejected because Android Build Tools
37 changed its human-readable signer labels. Testing that same APK with old and
new verification tools established that the identity had not changed. Replacing
the key would have broken updates for existing installations.

**How to apply:** Distinguish cryptographic verification failure, report parsing
failure, and an actual certificate mismatch. Compare tools on the same APK using
public certificate data without printing signing values or accessing CI secrets.
