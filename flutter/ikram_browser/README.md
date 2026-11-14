# إكرام سيف — Ikram Safe

## Version 1.1: native shopping browser interface

The official display name is **إكرام سيف (Ikram Safe)**. The Android package
remains `com.ikram.ikram_browser`, and CI continues using the existing protected
signing key. Renaming the app does not migrate or discard installed data.

- The top proxy toolbar shows the applied endpoint, a persistent on/off switch,
  editing, and real exit-country detection. Country detection is opt-in, uses
  `https://api.country.is/` **through a WebView using the active proxy**, and
  displays the returned ISO country code and IP. It is approximate, not proof
  of anonymity. Failed lookups show an error instead of an invented country.
  The service sees the connection's exit IP; browsing URLs and saved profiles
  are not sent. Tap the country control to revoke automatic lookup consent.
- A dedicated search bar supports SHEIN, Amazon, AliExpress, and web search.
  Direct URLs, including existing affiliate parameters, are not rewritten.
  The app does not create affiliate accounts, IDs, or tracking tags.
- **Generate New Fingerprint** creates and persists an experimental browser
  compatibility persona for the selected profile. It changes the WebView
  user agent and supported JavaScript-exposed platform/CPU/memory values,
  keeping the actual Chromium engine version. Regeneration reloads the page.
  It does **not** change physical device identifiers, canvas, WebGL, TLS
  signatures, or Client Hints, does not guarantee anonymity, and is not
  equivalent to Brave or Firefox anti-fingerprinting. Existing cookies are not
  automatically erased. Generated personas are local app preferences, not
  part of the configuration-only profile backup format.
- The central orange **Clear All / مسح الكل** button performs one-tap,
  app-wide local website cleanup. Its visible warning explains that websites
  are signed out across all profiles. Saved profiles, proxy settings and
  backup documents are preserved. Browser views are destroyed before cleanup;
  a blank page is opened afterward, without automatically revisiting a shop
  or IP service and recreating data.
- On Android WebView versions supporting `DELETE_BROWSING_DATA`, cleanup uses
  AndroidX WebStorageCompat to remove all-origin website data, including
  cookies, cache and JavaScript-readable storage (DOM storage, IndexedDB and
  service-worker data). HTTP-auth credentials and WebView history/form data
  are cleared as well. Older providers receive the supported cache/cookie/
  WebStorage cleanup and an explicit **partial cleanup** message. Update
  Android System WebView for the comprehensive API. The app does not claim
  to erase server records, external downloads, exported backups or OS backups.

This fixes the uploaded Flutter app without converting it to React or Expo.
The app remains a native Arabic/RTL Flutter browser. The entry point is `lib/main.dart`.

## Important privacy limits

- **Profiles are saved configurations, not isolated browser sessions.** Cookies,
  logins and website storage are shared by the native WebView. The app explains
  this before opening a browser. It does not claim fingerprint protection,
  anonymity, or guaranteed removal of every tracking mechanism.
- **Deleting a profile removes only its saved configuration.** It does not touch
  cookies, storage, or cache. A separate, confirmed action clears the shared
  cookies, cache and Web Storage for every profile. Android Web Storage cleanup
  is limited to what the platform API exposes; this is not a guarantee of wiping
  every possible artifact, including downloads or data held by websites.
- **Proxy overrides are Android-only and app-wide**, not per WebView. Only one
  browser is open at a time. Settings are awaited before creating it. Unsupported
  devices and setup failures block browsing rather than silently going direct.
  Changing proxy settings recreates the WebView; unsaved webpage state can be lost.
- Empty proxy means **system network settings**, not “your real IP.” A device
  VPN or OS proxy may still apply. “Applied” means the platform accepted the
  configuration, **not** that an external IP check succeeded.
- Supports unauthenticated `host:port`, `http://host:port`,
  `https://host:port`, and `socks://host:port`. **Authenticated proxies are
  explicitly unsupported.** Their credentials must never be entered here.
  Legacy proxy credentials are removed from preferences at load time and that
  profile is blocked until its settings are reviewed. This does not securely erase
  copies retained by operating-system backups or previous versions.
- Android incognito is deliberately NOT used as fake profile isolation:
  the plugin documents that enabling it clears cookies for all WebViews.
- TLS errors are not bypassed. Navigation only permits HTTP(S).

True persistent isolation needs a different native data-store/process design;
it cannot be created by assigning IDs to these `InAppWebView` widgets.

## Fixed behaviors

- Saved proxies now configure Android's actual `ProxyController`.
- Editing a profile from inside the browser is persisted immediately.
- Adds, edits and deletes await successful storage before updating the list.
- Loading or decoding failures do not silently overwrite saved profiles.
- Profile deletion and app-wide browsing-data removal have separate confirmations.
- Bare domains open as URLs; search queries are encoded safely.
- Adds Arabic localization/RTL, lifecycle checks, controller disposal, loading
  and error states, and a site-back button.

## Use in a Flutter project

Requires Flutter **3.24 or newer**, Dart **3.5 or newer**, and native Android/iOS.
`flutter_inappwebview` is pinned to the verified stable API version **6.1.5**.

For an existing app, copy this folder's `lib/` and `packages/`, merge the
dependencies from `pubspec.yaml`, and keep your existing native project
files/signing configuration. The local `profile_backup_documents` package
registers the Android system document picker automatically; do not omit it.

For a new native shell, run from this folder with Flutter installed:

```sh
flutter create --platforms=android,ios --project-name ikram_browser .
flutter pub get
flutter analyze
flutter run
```

Review platform prerequisites in the plugin documentation. The pinned Flutter
3.35.7 Android shell requires **minSdk 24** (Android 7.0), even though the WebView
plugin alone supports older devices. It also requires an Internet permission in the **main** manifest
(not just the debug manifest):

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Keep Android cleartext traffic disabled and iOS ATS enabled unless you explicitly
need plain-HTTP sites; this source does not weaken either platform's defaults.
The WebView itself is not available in the browser-based Replit preview.

## Validation

### Automatic Android APK builds

The repository's `.github/workflows/android-apk.yml` builds an installable
**debuggable test APK with a persistent CI signing key**, using Flutter 3.35.7
and Java 17. Pull requests run source/domain/signing-tool checks **without
signing secrets** and build a disposable-key APK pair only for automated testing,
not the recommended download. Non-default-branch pushes do the same. Default-branch pushes
and manual runs on an environment-approved branch also build two APKs on
separate fresh runners. Both must match the protected signing certificate.
Disposable Android **API 24, 28 and 35** emulators then install the first APK,
seed two saved profiles, and open a controlled HTTPS-origin fixture inside the
actual app WebView. It creates persistent Secure JavaScript and HttpOnly cookies
and actual localStorage through browser APIs. A cold restart verifies they
reached disk before the update. Each emulator rejects a copy signed with a
new disposable certificate, then installs the correct second APK with
`adb install -r`. Checks include unchanged UID, byte-for-byte preferences/WebView
files after both rejected and accepted updates, visible profiles after relaunch,
and read-only verification of the original cookies/localStorage, including
another cold start after updating. A separate **historical-release check on
API 35** installs the original retained versionCode 30 APK, creates profiles
through that earlier app's UI, seeds real HTTPS-origin storage, and updates
directly to the current build without reseeding anything. **All three API checks
must pass** before the protected-key APK is offered with its SHA-256 checksum.
Historical verification must also pass when its retained APK is available.
When retention returns the explicit unavailable status (exit 4), that check is
skipped and clearly reported as unverified; it does not prevent the download.

Once this repository and workflow have been pushed to GitHub:

1. Open the repository's **Actions** tab.
2. Select **Build Android APK**. To start manually, choose **Run workflow**.
   GitHub must have the workflow on the default branch for this manual control.
3. Open a successful run and click its APK download link in the summary, or find
   **ikram-browser-debug-…** under **Artifacts**.
4. Download and unzip the artifact. Install `ikram-browser-debug.apk` on Android;
   you may need to permit installation from your browser or file manager.

You must be signed in to GitHub to download artifacts, which are kept for
30 days. Intermediate `signed-apk-…` artifacts are for verification only and
expire after one day. These are **debuggable test builds**, not hardened releases.
Nothing here publishes to an app store.

### Update without losing profiles or browser data

1. Download the tested `ikram-browser-debug-…` artifact from a newer successful
   run of **this repository**. Check `SHA256SUMS.txt` if transferring the APK.
   That checksum checks file integrity; it is not the signing certificate.
2. Install `ikram-browser-debug.apk` **over the existing installation** using
   Android's Update prompt. With ADB, use `adb install -r path/to/new.apk`.
   **Do not uninstall, clear storage, or run `adb uninstall` / `pm clear`.**
3. Reopen the app and check your saved profiles and website logins. An update
   retains the app's private storage; website session expiry and explicit
   in-app browsing-data deletion remain separate.

Android requires the same application ID (`com.ikram.ikram_browser`), signing
certificate, and a compatible version code. CI assigns increasing version codes
from its run number; download from a **newer run**, not an older artifact.
Rerunning an old run does not give it a newer version number. Do not rename the
workflow or reset its version numbering without preserving monotonic versions.

**Legacy builds:** previous APKs used a random runner debug key. A new stable
key cannot update an app signed by a different old key. If Android reports
`INSTALL_FAILED_UPDATE_INCOMPATIBLE`, **stop and leave the installed app alone**.
Do not uninstall to “fix” it: uninstalling deletes profiles and browsing data.
The only seamless migration is to reuse the exact original private signing key,
if it still exists, before establishing the CI identity. An old APK contains
only the public certificate; it cannot recover that private key. Versions with
the backup controls below can export **configurations only**, not browser
sessions. A legacy APK without these controls cannot gain them via an
incompatible update. If its original key is lost, keep it installed and manually
record its visible profile names and supported proxy settings for re-entry on
another device. This is not a lossless migration, and Android backup is not a
reliable way to recover browser sessions. Never copy proxy passwords into this app.

### Back up profile configurations before changing phones or reinstalling

This feature is available **only in builds containing the export/import controls**.
It does not recover data from an app that has already been uninstalled or had
its storage cleared without a previous backup. It does not bypass Android
signing restrictions or migrate website sessions.

1. On the saved-profiles screen, tap **تصدير إعدادات البروفايلات** (upload-file
   icon). The JSON includes only profile IDs, names, unauthenticated proxy
   settings, and any proxy-review flag. Cookies, website storage, cache,
   passwords, logins and open tabs are **not included**.
2. On Android, tap **حفظ ملف**, choose a trusted location in the system document
   picker, and save `ikram-profiles.json`. The app writes complete UTF-8 bytes,
   including Arabic names, and reports success only after the stream is closed.
   Cancellation is not success. A failed write may leave a partial file at the
   chosen destination: do not rely on it; retry and verify the saved file.
   Transfer a copy to your new phone or another trusted device.
   The JSON is **unencrypted** and can expose profile names and proxy addresses.
   Use trusted storage and avoid public sharing.
   **نسخ JSON** remains available as an alternative (and on platforms without
   the Android picker): save the **entire text**, unchanged, using a trusted
   UTF-8 editor outside the app, then clear the clipboard. Copying alone is not
   proof of a durable saved file.
3. Before removing anything, use **استيراد إعدادات البروفايلات** → **فتح ملف**
   to reopen the saved document. Opening automatically previews it, without
   importing. Check the expected count and names. Alternatively paste the
   complete file contents and tap **معاينة الاستيراد**. On the original
   installation, a valid preview will also warn about already-saved IDs and
   disable import. This is expected; cancel the dialog. Verification of JSON
   does not verify any website session.
4. On the destination installation, open **استيراد إعدادات البروفايلات**, use
   **فتح ملف** (or paste the complete JSON), preview it, then tap
   **تأكيد الاستيراد**. Cancel or dismiss
   before confirmation to make no changes. After success, close and reopen the
   app to check the configurations. You must sign in to websites again yourself.
5. Import adds to existing configurations; it **never overwrites an existing
   profile**. A repeated ID within the backup or a conflict with any saved ID
   rejects the entire import, including otherwise valid records. On a brand-new
   destination installation, its automatically created default profile may
   share ID `1` with a backed-up profile. Delete **only that unused default on
   the new installation** before importing. Do not delete real profiles to
   resolve conflicts without separately backing them up.

The versioned format is `{"format":"ikram-profile-configurations","version":1,
"profiles":[...]}`. Each record must have string `id`, `name`, and `proxy`
fields plus boolean `proxyNeedsReview`; IDs and names cannot be blank. Unknown
formats/versions/fields, wrong types, malformed JSON, credential-bearing or
invalid proxies, duplicates, and input over 1,048,576 characters are rejected
before any write. Empty backups are valid but add nothing. Legacy stored proxy
credentials are excluded from export and the review requirement is retained.
If existing saved data cannot be read, import/export are blocked rather than
replacing it; this feature is not a damaged-storage repair tool.

#### Android file-access safety and checks

The local Android plugin uses `ACTION_CREATE_DOCUMENT` and
`ACTION_OPEN_DOCUMENT` with `CATEGORY_OPENABLE`. It does not request broad
storage permissions, retain URI permissions, or copy selected documents into an
app cache. It accepts providers with generic MIME labels, then relies on the
existing strict backup schema rather than trusting the extension or MIME type.
Native reads stop at 3 MiB (the maximum UTF-8 bytes for the schema's UTF-16
character limit). Dart also enforces the existing 1,048,576-character limit and
rejects malformed UTF-8 instead of replacing characters. A UTF-8 BOM is accepted.
Provider errors and incomplete writes are shown without exposing provider paths
or file contents. A cancelled/failed open preserves the text already entered
but invalidates its old preview; preview again before confirming.

`flutter test` covers full-schema Arabic save/open round trips, cancellation,
storage errors and retry, invalid UTF-8 and size limits, preview without writes,
explicit confirmation, duplicate rejection, and dialog cancellation.
The Android CI check additionally runs:

```sh
cd android
./gradlew :profile_backup_documents:testDebugUnitTest
```

These native Robolectric checks exercise Android API **24 and 35** intents and
`ContentResolver` IO against a synthetic document provider. They cover cancelled
save/open without provider writes, unavailable and unwritable storage, exact
Arabic bytes and truncation when overwriting an explicitly selected file,
bounded reads, missing document URIs, overlapping operations, and activity
recreation/detachment. They are Android-runtime unit checks, not proof of a
particular phone's DocumentsUI or cloud provider behavior.

Before relying on a real device/provider, save and reopen a synthetic Arabic
configuration, verify its full names/count, cancel both system pickers, and
check a disconnected/read-only storage provider. Confirm no saved profiles
change until import confirmation. The existing separate phone-transfer checks
remain necessary; these configuration files do not restore website sessions.

### Administrator: protect the signing identity

The GitHub environment **`android-signing`** holds these five encrypted secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_SIGNING_CERT_SHA256`

The environment must restrict deployment branches to the trusted default branch
(`main` here). A trusted verification branch may be explicitly allowed temporarily,
then removed. Never permit wildcard branches, tags, or pull-request refs.
Require administrator review for changes to the workflow and signing tools.
The environment is a CI access boundary; it does not deploy the app.

For a **new identity only**, an administrator with authenticated GitHub CLI and
Java 17 `keytool` can run:

```sh
python3 tool/provision_ci_signing.py OWNER/REPOSITORY
```

The setup tool configures the main-only environment restriction first, generates
a long-lived key and random password in a private temporary directory, sends the
values directly to GitHub's encrypted environment secrets through `gh secret set`,
and removes local signing files. It refuses to modify an existing signing
environment or overwrite signing secrets.
No signing value should be printed, pasted into chat, committed, or uploaded as
an artifact. Do not use shell tracing (`set -x`), dump environment variables, or
enable verbose Gradle diagnostics with secrets present.

**Do not regenerate, rotate, delete, or overwrite this key after distributing an
APK.** Losing it prevents future compatible updates. GitHub does not let you
download stored secret values. Preserve the protected environment and repository;
moving repositories requires a planned secure key migration, not a new identity.
If setup partially fails, stop and investigate secret names/access without
overwriting the identity. If the original installed app's key is available,
have its owner securely provision that key and matching certificate/passwords
instead of running the new-key generator.

The build fails if any signing setting is absent, if the generated app ID
changes, or if the restored key or resulting APK has the wrong certificate.
There is no fallback to a fresh debug key. Temporary keystores are deleted with
an always-run cleanup step, and only APKs/checksums are uploaded.

### What the update test proves

The automated test verifies a real package-manager update, profile readability
in the relaunched app, and persistence of actual native WebView cookies and
localStorage as well as its files. The protected-key APK pair is built on
separate runners; PRs use one runner's disposable debug key without protected
secrets. The script refuses non-emulators and pre-existing installations.
Never run it on a personal device or use personal accounts.

#### Separate System WebView version-change scenario

The `verify-webview-update` job is separate from the unchanged API 24/28/35
app-update matrix. It builds and downloads **only disposable-key APKs**, on
all workflow events; it never enters the protected signing environment.
Two fresh, Google-account-free AOSP emulators are used:

1. An API 29 x86_64 **donor** supplies its standalone `com.android.webview`
   APK directly from Google's Android SDK image, not a third-party APK mirror.
2. An API 28 x86_64 **test** emulator first checks that APK's signature
   integrity, package, min/target SDK and native ABI. The installed app creates
   synthetic persistent Secure JavaScript and HttpOnly cookies and localStorage
   with the existing HTTPS-origin probe, and reads them after a cold start.
3. With the app stopped, `adb install -r` and Android's normal WebView selection
   command request the donor provider. The test requires Android's active
   provider to match the candidate and have a **different version**.
4. The original token is read without reseeding immediately after the provider
   change, then after the app update, and again after another cold start.
   The existing UID/profile/file and wrong-signature controls still run.

`provider-result.json` records the original, candidate and activated provider
versions, candidate SHA-256, stage and outcome. Evidence also includes both
SDK image fingerprints, provider diagnostics, public certificate metadata,
install/selection output and the probe results/screenshots. The provider APK
itself is not uploaded. No root, remount, signature bypass, downgrade flag,
uninstall, data clearing, personal account or production device is used.

SDK image revisions can change independently. Missing/split providers,
incompatible SDK/ABI, known package/signature rejection, unchanged versions
or Android declining the requested provider are explicitly **UNSUPPORTED**
(exit 78 internally). CI summarizes this as **not tested**, never as a pass or
data-loss failure. Other installation/transport errors fail the job. After
successful provider activation, lost storage fails as **data-loss**; launch or
protocol errors fail as test errors, not unsupported combinations. Failure
before the initial persistent fixture is proven is a fixture failure.
An incomplete run cannot report success. This separate lane's summary does
not broaden the tested-download claim: the original matrix remains mandatory,
and historical migration coverage is claimed only when that check actually passes.

Run the shell tools only through this fresh-emulator workflow. Local tests
exercise compatibility classification, the real probe CLI with simulated CDP
responses, safety guards and read-only failure behavior without an emulator.
Real provider migration requires the GitHub-hosted Android emulator run; local
tooling results alone do not prove device storage retention.

#### Retained earlier-release baseline

`tool/android-update-baseline.json` pins the original main-branch versionCode
**30** APK from source `f334837895f9245cf72e1ef1fdd814759e480220`, built by
[run 43478338382](https://github.com/ikramebelkhelek-source/ikram-browser/actions/runs/43478338382).
It represents the app before configuration-backup support. It is not rebuilt
from old source: today's SDKs/dependencies could change that APK and hide real
migration bugs. Its file SHA-256 and public signing-certificate SHA-256 are
checked before installation, along with its application ID and versionCode.
The current APK must have the same certificate, a strictly greater versionCode,
and a different source revision. Baseline metadata is public, not signing
material.

The `retain-baseline` job, on trusted runs only, stores that original APK as a
permanent **CI-only prerelease asset** under `android-update-baseline-v30` in
this GitHub repository. It has no signing-environment access; only that job has
repository write permission. The first run retrieves the pinned, already-tested
APK artifact and verifies it before retention. This bootstrap **must run before
the original 30-day artifact expires** (created 2026-11-13). Subsequent runs use
the permanent asset, independent of Actions artifact expiry. Retention exit 4
now makes the historical check optional: the workflow warns and skips it rather
than blocking an APK that passes the required update checks. Other retention
errors, including failed integrity verification, still fail the pipeline.
There is no fallback to a rebuilt APK or a new key. Downloads are checksum-verified and
atomically installed locally. The retention job never replaces an existing
release asset. Only the baseline APK and its public manifest are uploaded,
never a build directory, keystore or signing properties.

This historical APK predates explicit native WebView inspection on old Android
images, so the historical lane uses API 35's automatic debugging for debuggable
apps. The unchanged same-revision lanes still cover APIs 24, 28 and 35; they do
not claim historical migration coverage on APIs 24/28. PRs and non-default-branch
pushes retain disposable-key checks, but cannot perform a permanent-key
historical update and do not advertise a tested download.

Both paths create the two profiles through the installed first app's UI, rather
than writing preferences in the current source's schema. They capture visible
profile names before and after the update, verify the original storage tokens
after update and again after a cold start, and never call the seed path after
installing the current app. Historical evidence includes the pinned manifest
and both APKs' public certificate/package reports. The final download job
requires the same-revision matrix to succeed; historical verification must pass
unless explicitly skipped because retention reported the baseline unavailable.

Local tooling checks (no Android SDK or emulator required):

```sh
python3 -m unittest discover -s flutter/ikram_browser/tool/tests -v
node --test flutter/ikram_browser/tool/tests/*.test.mjs
for script in flutter/ikram_browser/tool/*.sh; do bash -n "$script" || exit; done
```

`tool/update_test_page.html` is a controlled, repository-owned page supplied to
the real WebView at `https://update-test.invalid` through its DevTools request
interception interface. The reserved domain is never contacted; no public
hosting, real accounts, custom CA, or TLS error bypass is used. This tests
HTTPS-origin storage (including Secure/HttpOnly cookies), **not TLS transport,
server session expiry, or any particular website's login policy**.
The post-restart and post-update pages only read: they cannot recreate lost
cookies or localStorage. A separate negative control re-signs only a temporary
APK copy; it never changes the protected identity.

Native WebView inspection is enabled explicitly only when Android marks the
APK debuggable, including older System WebViews that do not auto-enable it.
It is not enabled for release builds. These APKs are already debuggable test
builds, not suitable for personal credentials.

Each API uploads separate one-day evidence: provider/API details, profile UI
dumps, fixture screenshots, storage probe results, and accepted/rejected install
output. Failure evidence includes a screenshot and recent emulator logs.
Verified on **2026-11-13**:

- [Expanded Android update suite](https://github.com/ikramebelkhelek-source/ikram-browser/actions/runs/43478875318):
  APIs **24, 28 and 35** all passed cold-start persistence, wrong-certificate
  rejection, in-place installation, unchanged UID and directory contents,
  visible saved profiles, and retained Secure/HttpOnly cookies and localStorage.
  The non-default-branch run used only a disposable debug identity; protected-key
  build and recommended-download jobs were correctly skipped. The final small
  hardening changes (longer flush wait, frame-ready screenshots, transient-context
  retries and certificate fingerprint comparison) were checked locally afterward.

The older single-API verification below is historical.

Verified on **2026-11-12**:

- [Independent APK builds](https://github.com/ikramebelkhelek-source/ikram-browser/actions/runs/43293675940):
  both signed-build jobs passed on fresh runners with the protected identity.
- [Android 35 in-place update test](https://github.com/ikramebelkhelek-source/ikram-browser/actions/runs/43295813025):
  the exact same APK pair passed replacement installation, unchanged UID,
  byte-for-byte preferences/WebView data retention, and visible saved profile
  after relaunch. The test was rerun separately after correcting its Android UID
  query; this did not rebuild or re-sign either APK.

The temporary rerun workflow was removed after verification. The permanent
workflow includes the corrected check and retains an emulator screenshot for one
day. These tests used synthetic data, not a personal device or real website login.

### Local checks

The dependency-free domain checks can run with the Dart SDK:

```sh
dart tool/check_domain.dart
dart analyze lib/domain.dart tool/check_domain.dart
```

For complete Flutter verification, run `flutter pub get` and `flutter analyze`,
then `flutter test` (also required by the APK workflow),
then use a native device/emulator to check:

1. Create/edit/delete profiles and restart: configurations persist.
2. Open two profiles in sequence: both display the shared-storage warning.
3. Sign in to a website, delete a profile: no global cookie deletion occurs.
4. Cancel shared-data cleanup: no data changes. Confirm: website logins clear.
5. Configure an unreachable proxy: navigation fails, with no automatic direct
   fallback. Configure a working proxy and independently verify its exit IP.
6. On iOS or an unsupported Android WebView, a configured proxy blocks browsing.
7. Edit the active proxy, restart, and verify the new setting was retained.
8. Legacy credential-bearing proxy records require review before browsing.

These device checks are a verification checklist, not a claim that they have
already been performed.

## API references

- https://inappwebview.dev/docs/webview/proxy-controller/
- https://pub.dev/documentation/flutter_inappwebview/6.1.5/
- https://pub.dev/documentation/flutter_inappwebview/latest/flutter_inappwebview/InAppWebViewSettings/incognito.html
