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
    // Validate IDs/names and duplicates as well as proxy settings before writing.
    decodeProfiles(encodeProfiles(profiles));
    for (final profile in profiles) {
      ProxyEndpoint.parse(profile.proxy);
    }
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = await prefs.setString(_key, encodeProfiles(profiles));
      if (!saved) throw StateError('لم يتم حفظ التغييرات على الجهاز.');
    } catch (_) {
      // SharedPreferences updates its memory cache even if the write fails.
      // Re-read storage so a later export cannot back up an uncommitted import.
      await prefs.reload();
      rethrow;
    }
  }

  Future<String> exportBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_key);
    // Do not initialize or rewrite storage as a side effect of exporting.
    if (source == null) {
      throw StateError('لا توجد بروفايلات محفوظة للتصدير.');
    }
    return encodeProfileBackup(decodeProfiles(source));
  }

  Future<List<Profile>> importBackup(String source) async {
    // Validate the entire backup before touching preferences.
    decodeProfileBackup(source);
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_key);
    // Do not call load(): it can initialize defaults or rewrite legacy data.
    // Damaged existing data must block import, never be replaced by it.
    final saved = current == null ? <Profile>[] : decodeProfiles(current);
    final merged = mergeProfileBackup(saved, source);
    await save(merged);
    return merged;
  }
}
