---
name: Historical Android migration baseline
description: Preserve original APK bytes and distinguish historical migration coverage from same-source update coverage.
---

Retained migration baselines must be original signed APKs, not rebuilds of old
source with today's SDKs and dependencies. Never patch or re-sign a baseline to
make it easier to inspect.

**Why:** Rebuilding changes the historical artifact and can hide migration
regressions. The representative earlier APK also predates explicit native
WebView inspection on older Android images, which limits where its storage can
be probed without changing its bytes.

**How to apply:** Keep public checksums and certificate/provenance metadata
pinned separately from the binary. Use Android 35's automatic inspection for
this baseline; do not describe same-source API 24/28 tests as historical-release
migration coverage. Create fixtures through the earlier app's UI so its own
schema is exercised.
