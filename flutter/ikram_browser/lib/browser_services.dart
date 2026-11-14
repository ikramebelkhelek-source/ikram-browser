import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

class CleanupReport {
  final bool complete;
  const CleanupReport(this.complete);

  String get message => complete
      ? 'تم مسح بيانات المواقع المحلية. بقيت البروفايلات وإعدادات البروكسي.'
      : 'تم مسح الكوكيز والكاش وتخزين الويب الأساسي. حدّث Android System '
          'WebView لإتاحة المسح الشامل لقواعد بيانات المواقع وبيانات التتبع.';
}

/// Explicitly app-wide, never invoked by profile deletion. Caller must first
/// stop and dispose all WebViews (including country lookups).
Future<CleanupReport> clearSharedBrowsingData() async {
  if (!isSupportedMobile) {
    throw UnsupportedError('مسح بيانات المتصفح متاح على Android وiOS فقط.');
  }
  if (isAndroid) {
    const channel = MethodChannel('ikram_safe/privacy');
    final result = await channel
        .invokeMapMethod<String, dynamic>('clearAll')
        .timeout(const Duration(seconds: 45));
    if (result == null || result['complete'] is! bool) {
      throw StateError('تعذّر تأكيد اكتمال المسح.');
    }
    return CleanupReport(result['complete'] as bool);
  }
  await CookieManager.instance().deleteAllCookies();
  await InAppWebViewController.clearAllCache();
  final storage = WebStorageManager.instance();
  await storage.removeDataModifiedSince(
    dataTypes: WebsiteDataType.ALL,
    date: DateTime.fromMillisecondsSinceEpoch(0),
  );
  return const CleanupReport(true);
}
