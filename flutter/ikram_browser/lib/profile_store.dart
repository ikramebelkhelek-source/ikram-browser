import 'package:shared_preferences/shared_preferences.dart';

import 'domain.dart';

class ProfileStore {
  static const _key = 'ikram_profiles';

  Future<List<Profile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_key);
    if (source == null) {
      const initial = [Profile(id: '1', name: 'بروفايل 1 - شي إن')];
      await save(initial);
      return initial;
    }
    final profiles = decodeProfiles(source);
    // Rewrite legacy credentials out of preferences before exposing profiles.
    // Decode errors deliberately propagate: never overwrite a damaged file.
    if (profiles.any((p) => p.proxyNeedsReview)) {
      await save(profiles);
    }
    return profiles;
  }

  Future<void> save(List<Profile> profiles) async {
    for (final profile in profiles) {
      ProxyEndpoint.parse(profile.proxy);
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_key, encodeProfiles(profiles));
    if (!saved) throw StateError('لم يتم حفظ التغييرات على الجهاز.');
  }
}
