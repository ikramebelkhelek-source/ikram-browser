---
name: Backup document access
description: Why configuration-backup file access deliberately avoids private cached copies and persistent grants.
---

Prefer direct, bounded document-provider streams for backup files; do not add
convenience pickers that retain private copies without reviewing their behavior.

**Why:** Configuration backups are unencrypted. Automatically caching arbitrary
selected documents would retain potentially sensitive input unnecessarily.
Some convenience-picker implementations also treat a null output stream as a
successful save, which conflicts with the requirement not to claim a durable
backup after a provider failure.

**How to apply:** When changing document access, verify cancellation separately
from errors, successful stream closure before success, strict UTF-8, bounded
reads before decoding, and no implicit retained copies or URI permissions.
Keep real-device/provider checks distinct from simulated Android-runtime tests.

Native Flutter clipboard checks must verify the pasted content, not just a
successful Android input command.

**Why:** On Android 35, `KEYCODE_PASTE` returned success but did not invoke
Flutter's paste action; the profile field remained unchanged. Flutter's
Ctrl+V shortcut invokes the real clipboard editing action instead.

**How to apply:** Use an actual supported editing shortcut or the touch selection
toolbar, and compare the resulting configuration/document. Treat UI-driver
preflight failures separately from failed backup or session-preservation checks.
