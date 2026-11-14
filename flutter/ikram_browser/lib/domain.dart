import 'dart:convert';

/// Profiles are named configurations, NOT independent website data stores.
class Profile {
  final String id;
  final String name;
  final String proxy;
  final bool proxyNeedsReview;

  const Profile({
    required this.id,
    required this.name,
    this.proxy = '',
    this.proxyNeedsReview = false,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final proxy = json['proxy'] ?? '';
    final review = json['proxyNeedsReview'] ?? false;
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        proxy is! String ||
        review is! bool) {
      throw const FormatException('بيانات البروفايلات غير صالحة.');
    }
    // Legacy versions stored proxy credentials in SharedPreferences. Never
    // return those credentials to the UI or silently switch that profile online.
    final hasCredentials = proxy.contains('@');
    return Profile(
      id: id,
      name: name.trim(),
      proxy: hasCredentials ? '' : proxy.trim(),
      proxyNeedsReview: review || hasCredentials,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'proxy': proxy,
        'proxyNeedsReview': proxyNeedsReview,
      };
}

List<Profile> decodeProfiles(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List) {
    throw const FormatException('قائمة البروفايلات غير صالحة.');
  }
  final ids = <String>{};
  return decoded.map((entry) {
    if (entry is! Map<String, dynamic>) {
      throw const FormatException('بروفايل غير صالح.');
    }
    final profile = Profile.fromJson(entry);
    if (!ids.add(profile.id)) {
      throw const FormatException('معرّف بروفايل مكرر.');
    }
    return profile;
  }).toList();
}

String encodeProfiles(List<Profile> profiles) =>
    jsonEncode(profiles.map((p) => p.toJson()).toList());

/// A configuration-only interchange format, distinct from legacy preferences.
/// Keep import strict: legacy credential cleanup must not hide invalid input.
const maxProfileBackupLength = 1024 * 1024;

List<Profile> decodeProfileBackup(String source) {
  if (source.length > maxProfileBackupLength) {
    throw const FormatException('النسخة أكبر من الحد المسموح (مليون حرف).');
  }
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic> ||
      decoded.length != 3 ||
      decoded['format'] != 'ikram-profile-configurations' ||
      decoded['version'] is! int ||
      decoded['version'] != 1 ||
      decoded['profiles'] is! List) {
    throw const FormatException('صيغة النسخة الاحتياطية أو إصدارها غير مدعوم.');
  }
  final entries = decoded['profiles'] as List;
  for (final entry in entries) {
    if (entry is! Map<String, dynamic> ||
        entry.length != 4 ||
        entry['id'] is! String ||
        (entry['id'] as String).trim().isEmpty ||
        entry['id'] != (entry['id'] as String).trim() ||
        entry['name'] is! String ||
        (entry['name'] as String).trim().isEmpty ||
        entry['proxy'] is! String ||
        entry['proxyNeedsReview'] is! bool) {
      throw const FormatException('سجل بروفايل غير مكتمل أو غير صالح.');
    }
    ProxyEndpoint.parse(entry['proxy'] as String);
  }
  // Also rejects repeated IDs, even if the rest of the records differ.
  return decodeProfiles(jsonEncode(entries));
}

String encodeProfileBackup(List<Profile> profiles) {
  final source = const JsonEncoder.withIndent('  ').convert({
    'format': 'ikram-profile-configurations',
    'version': 1,
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
  });
  decodeProfileBackup(source);
  return source;
}

/// All-or-nothing merge. Re-imports and conflicting IDs never replace records.
List<Profile> mergeProfileBackup(List<Profile> saved, String source) {
  final imported = decodeProfileBackup(source);
  final ids = saved.map((profile) => profile.id).toSet();
  for (final profile in imported) {
    if (!ids.add(profile.id)) {
      throw const FormatException(
        'توجد معرّفات بروفايلات محفوظة مسبقاً. لم يتم استيراد أي بروفايل.',
      );
    }
  }
  return [...saved, ...imported];
}

class ProxyEndpoint {
  final String url;
  const ProxyEndpoint._(this.url);

  /// Returns null for the explicit "use system network settings" configuration.
  static ProxyEndpoint? parse(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    if (value.contains('@')) {
      throw const FormatException(
        'البروكسي بكلمة مرور غير مدعوم. لا تُدخل بيانات الدخول هنا.',
      );
    }
    if (RegExp(r'\s').hasMatch(value)) {
      throw const FormatException('عنوان البروكسي لا يقبل مسافات.');
    }
    final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
    if (uri == null ||
        !{'http', 'https', 'socks'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'أدخل host:port أو http://host:port أو socks://host:port.',
      );
    }
    final host = uri.host.replaceAll(RegExp(r'^\[|\]$'), '');
    if (!host.contains(':') &&
        !RegExp(
          r'^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$',
        ).hasMatch(host)) {
      throw const FormatException('اسم مضيف البروكسي غير صالح.');
    }
    final port = uri.hasPort
        ? uri.port
        : switch (uri.scheme) {
            'https' => 443,
            'socks' => 1080,
            _ => 80,
          };
    if (port < 1 || port > 65535) {
      throw const FormatException('منفذ البروكسي يجب أن يكون بين 1 و65535.');
    }
    final authority = host.contains(':') ? '[$host]' : host;
    return ProxyEndpoint._('${uri.scheme}://$authority:$port');
  }
}

/// No javascript:, file:, data:, credentials, or ambiguous custom schemes.
Uri resolveAddress(String input) {
  final value = input.trim();
  if (value.isEmpty) {
    throw const FormatException('أدخل رابطاً أو عبارة بحث.');
  }
  final explicitScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
  if (explicitScheme.hasMatch(value)) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'\s').hasMatch(value)) {
      throw const FormatException(
        'يسمح فقط بروابط HTTP وHTTPS دون بيانات دخول.',
      );
    }
    return uri;
  }
  // Recognize ordinary domains/IPs, including a port, without confusing
  // example.com:8080 with an explicit URI scheme.
  if (!RegExp(r'\s').hasMatch(value)) {
    final uri = Uri.tryParse('https://$value');
    if (uri != null &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        (uri.host.contains('.') ||
            uri.host.contains(':') ||
            uri.host == 'localhost')) {
      return uri;
    }
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value)) {
      throw const FormatException('يسمح فقط بروابط HTTP وHTTPS.');
    }
  }
  return Uri.https('www.google.com', '/search', {'q': value});
}
