import 'dart:convert';
import 'dart:math';

/// A compatibility persona, not a new hardware identity or anti-detection tool.
class BrowserIdentity {
  final String id;
  final String device;
  final String userAgent;
  final int cores;
  final int memoryGiB;

  const BrowserIdentity({
    required this.id,
    required this.device,
    required this.userAgent,
    required this.cores,
    required this.memoryGiB,
  });

  static const _devices = ['Pixel 7', 'SM-S911B', 'moto g84 5G', 'Pixel 8'];

  factory BrowserIdentity.generate(String engineUserAgent,
      {BrowserIdentity? previous}) {
    if (!engineUserAgent.contains('Android') ||
        !engineUserAgent.contains('Chrome/')) {
      throw const FormatException(
        'توليد الخصائص متاح لمحرك Chromium على Android فقط.',
      );
    }
    final random = Random.secure();
    final choices = _devices.where((d) => d != previous?.device).toList();
    final device = choices[random.nextInt(choices.length)];
    // Keep the actual Chromium engine version. Never masquerade as Firefox
    // or Brave: those are different engines/privacy implementations.
    final ua = engineUserAgent.replaceFirst(
      RegExp(r'\(Linux; Android [^)]*\)'),
      '(Linux; Android 13; $device)',
    );
    if (ua == engineUserAgent) {
      throw const FormatException('صيغة وكيل المستخدم غير مدعومة.');
    }
    return BrowserIdentity(
      id: List.generate(12, (_) => random.nextInt(256))
          .map((n) => n.toRadixString(16).padLeft(2, '0'))
          .join(),
      device: device,
      userAgent: ua,
      cores: [4, 6, 8][random.nextInt(3)],
      memoryGiB: [4, 8][random.nextInt(2)],
    );
  }

  Map<String, Object> toJson() => {
        'id': id,
        'device': device,
        'userAgent': userAgent,
        'cores': cores,
        'memoryGiB': memoryGiB,
      };

  factory BrowserIdentity.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        !RegExp(r'^[a-f0-9]{24}$').hasMatch(json['id'] as String) ||
        !_devices.contains(json['device']) ||
        json['userAgent'] is! String ||
        !(json['userAgent'] as String).contains('Chrome/') ||
        ![4, 6, 8].contains(json['cores']) ||
        ![4, 8].contains(json['memoryGiB'])) {
      throw const FormatException('خصائص المتصفح المحفوظة غير صالحة.');
    }
    return BrowserIdentity(
      id: json['id'] as String,
      device: json['device'] as String,
      userAgent: json['userAgent'] as String,
      cores: json['cores'] as int,
      memoryGiB: json['memoryGiB'] as int,
    );
  }

  /// The random profile ID is intentionally never sent to websites.
  String get script => '''
(() => {
  const values = ${jsonEncode({
            'platform': 'Linux armv8l',
            'hardwareConcurrency': cores,
            'deviceMemory': memoryGiB,
          })};
  for (const [name, value] of Object.entries(values)) {
    try {
      Object.defineProperty(Navigator.prototype, name, {
        configurable: true, get: () => value
      });
    } catch (_) {}
  }
})();
''';
}

Uri shoppingSearch(String query, String target) {
  final value = query.trim();
  if (value.isEmpty) throw const FormatException('أدخل اسم المنتج أو رابطاً.');
  if (target == 'web') {
    return Uri.https('www.google.com', '/search', {'q': value});
  }
  // Search only, never rewrite existing affiliate URLs or add tracking tags.
  return switch (target) {
    'shein' => Uri.https('www.shein.com', '/pdsearch/$value/'),
    'amazon' => Uri.https('www.amazon.com', '/s', {'k': value}),
    'aliexpress' => Uri.https(
        'www.aliexpress.com', '/w/wholesale-${value.replaceAll(' ', '-')}.html'),
    _ => throw const FormatException('محرك البحث غير معروف.'),
  };
}
