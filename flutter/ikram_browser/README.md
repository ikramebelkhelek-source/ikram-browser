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
