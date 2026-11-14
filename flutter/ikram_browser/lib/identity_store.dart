import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'browser_identity.dart';

class IdentityStore {
  String _key(String profileId) => 'ikram_safe_identity_$profileId';

  Future<BrowserIdentity?> load(String profileId) async {
    final value = (await SharedPreferences.getInstance()).getString(_key(profileId));
    if (value == null) return null;
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('خصائص المتصفح المحفوظة غير صالحة.');
    }
    return BrowserIdentity.fromJson(decoded);
  }

  Future<void> save(String profileId, BrowserIdentity identity) async {
    final ok = await (await SharedPreferences.getInstance())
        .setString(_key(profileId), jsonEncode(identity.toJson()));
    if (!ok) throw StateError('تعذّر حفظ خصائص المتصفح.');
  }
}
