# إكرام — corrected Flutter source

This fixes the uploaded Flutter app without converting it to React or Expo.
The Arabic UI and pink theme are retained. The entry point is `lib/main.dart`.

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

For an existing app, copy this folder's `lib/`, merge the dependencies from
`pubspec.yaml`, and keep your existing native project files/signing configuration.

For a new native shell, run from this folder with Flutter installed:

```sh
flutter create --platforms=android,ios --project-name ikram_browser .
flutter pub get
flutter analyze
flutter run
```

Review platform prerequisites in the plugin documentation. Android requires
minSdk 19+, compileSdk 34+ and an Internet permission in the **main** manifest
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
signing secrets** and do not produce downloadable APKs. Default-branch pushes
and manual runs on an environment-approved branch also build two APKs on
separate fresh runners. Both must match the protected signing certificate.
An Android 35 emulator then installs the first APK, seeds a saved profile and
native WebView test data, and installs the second with `adb install -r`.
It checks the unchanged app UID, byte-for-byte preferences/WebView files, and
the saved profile visible after relaunch. Only after this succeeds is the newer
APK uploaded as the recommended download, with a SHA-256 file checksum.

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
only the public certificate; it cannot recover that private key. This app has
no complete profile/browser-session export. Do not promise a lossless migration
from a lost key or rely on Android backup to recover browser sessions.

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

The automated test verifies a real package-manager update between separately
built APKs, profile readability in the relaunched app, and retention of native
WebView files. It uses synthetic data on a disposable emulator, not personal
accounts. It does not prove any particular website will keep a session alive.
For device acceptance, create a named profile, sign in to a disposable test
website account, install a later successful run over it, then confirm the profile
and login still exist. Never run the emulator fixture script on a personal device.

### Local checks

The dependency-free domain checks can run with the Dart SDK:

```sh
dart tool/check_domain.dart
dart analyze lib/domain.dart tool/check_domain.dart
```

For complete Flutter verification, run `flutter pub get` and `flutter analyze`,
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
