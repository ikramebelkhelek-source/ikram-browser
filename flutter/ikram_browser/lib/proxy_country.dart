import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ProxyCountry {
  final String code;
  final String ip;
  const ProxyCountry(this.code, this.ip);

  factory ProxyCountry.parse(String source) {
    final data = jsonDecode(source);
    if (data is! Map ||
        data['country'] is! String ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(data['country'] as String) ||
        data['ip'] is! String ||
        (data['ip'] as String).length > 64) {
      throw const FormatException('لم يتم إرجاع بلد صالح.');
    }
    return ProxyCountry(data['country'] as String, data['ip'] as String);
  }
}

/// This deliberately uses WebView, NOT Dart HttpClient, so the Android WebView
/// proxy override also applies to the IP lookup. Called only after user consent.
Future<ProxyCountry> detectProxyCountry() async {
  final result = Completer<ProxyCountry>();
  final view = HeadlessInAppWebView(
    initialUrlRequest: URLRequest(url: WebUri('https://api.country.is/')),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      thirdPartyCookiesEnabled: false,
      javaScriptCanOpenWindowsAutomatically: false,
    ),
    onLoadStop: (controller, _) async {
      if (result.isCompleted) return;
      try {
        final text = await controller.evaluateJavascript(
          source: 'document.body.innerText',
        );
        final country = ProxyCountry.parse(text as String);
        if (!result.isCompleted) result.complete(country);
      } catch (error) {
        if (!result.isCompleted) result.completeError(error);
      }
    },
    onReceivedError: (_, request, error) {
      if (request.isForMainFrame == true && !result.isCompleted) {
        result.completeError(StateError('تعذّر فحص بلد الاتصال.'));
      }
    },
  );
  try {
    await view.run();
    return await result.future.timeout(const Duration(seconds: 15));
  } finally {
    await view.dispose();
  }
}
