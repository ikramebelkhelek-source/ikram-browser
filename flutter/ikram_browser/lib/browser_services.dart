import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'domain.dart';

bool get isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isSupportedMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Only one browser route exists at a time: Android proxy overrides are GLOBAL.
class BrowserNetwork {
  static Future<void> _pending = Future<void>.value();

  Future<void> apply(String value) {
    // A closing route may still have a platform request in flight. The next
    // route must wait for it, or its network settings could be overwritten.
    final next = _pending.then((_) => _apply(value));
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _apply(String value) async {
    final endpoint = ProxyEndpoint.parse(value);
    if (!isSupportedMobile) {
      throw UnsupportedError('المتصفح يدعم Android وiOS فقط.');
    }
    if (!isAndroid) {
      if (endpoint != null) {
        throw UnsupportedError('تغيير البروكسي من التطبيق متاح على Android فقط.');
      }
      return;
    }
    final supported = await WebViewFeature.isFeatureSupported(
      WebViewFeature.PROXY_OVERRIDE,
    );
    if (!supported) {
      if (endpoint != null) {
        throw UnsupportedError(
          'إصدار Android System WebView لا يدعم البروكسي. حدّثه أولاً.',
        );
      }
      return;
    }
    if (endpoint == null) {
      await ProxyController.instance().clearProxyOverride();
    } else {
      await ProxyController.instance().setProxyOverride(
        settings: ProxySettings(
          proxyRules: [ProxyRule(url: endpoint.url)],
          removeImplicitRules: true,
        ),
      );
    }
  }
}

/// Explicitly app-wide, never invoked by profile deletion.
Future<void> clearSharedBrowsingData() async {
  if (!isSupportedMobile) {
    throw UnsupportedError('مسح بيانات المتصفح متاح على Android وiOS فقط.');
  }
  await CookieManager.instance().deleteAllCookies();
  await InAppWebViewController.clearAllCache();
  final storage = WebStorageManager.instance();
  if (isAndroid) {
    await storage.deleteAllData();
  } else {
    await storage.removeDataModifiedSince(
      dataTypes: WebsiteDataType.ALL,
      date: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
