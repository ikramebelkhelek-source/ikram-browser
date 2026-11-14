import 'package:flutter_test/flutter_test.dart';
import 'package:ikram_browser/domain.dart';
import 'package:ikram_browser/profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'ikram_profiles';
  const existing = Profile(id: 'existing', name: 'محفوظ');
  const incoming = Profile(id: 'incoming', name: 'جديد', proxy: 'host:80');
  final store = ProfileStore();

  Future<String?> raw() async =>
      (await SharedPreferences.getInstance()).getString(key);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      key: encodeProfiles([existing]),
    });
  });

  test('export is read-only, import merges and survives reload', () async {
    final before = await raw();
    final exported = await store.exportBackup();
    expect(decodeProfileBackup(exported).single.id, existing.id);
    expect(await raw(), before);
    final result = await store.importBackup(encodeProfileBackup([incoming]));
    expect(result.map((p) => p.id), [existing.id, incoming.id]);
    await (await SharedPreferences.getInstance()).reload();
    expect((await store.load()).map((p) => p.id), [existing.id, incoming.id]);
  });

  test('any invalid record or duplicate rejects the entire import', () async {
    final before = await raw();
    final valid = encodeProfileBackup([incoming]);
    for (final source in [
      '{',
      valid.replaceFirst('"version": 1', '"version": 99'),
      valid.replaceFirst('"host:80"', '"host:0"'),
      valid.replaceFirst('"host:80"', '"user:secret@host:80"'),
      valid.replaceFirst('"incoming"', '"existing"'),
      valid.replaceFirst('"profiles": [', '"profiles": [null,'),
    ]) {
      await expectLater(store.importBackup(source), throwsFormatException);
      expect(await raw(), before);
    }
    await store.importBackup(valid);
    final imported = await raw();
    await expectLater(store.importBackup(valid), throwsFormatException);
    expect(await raw(), imported);
  });

  test('damaged existing data cannot be replaced by an import', () async {
    SharedPreferences.setMockInitialValues({key: '{damaged'});
    await expectLater(
      store.importBackup(encodeProfileBackup([incoming])),
      throwsFormatException,
    );
    expect(await raw(), '{damaged');
    await expectLater(store.exportBackup(), throwsFormatException);
    expect(await raw(), '{damaged');
  });

  test(
    'absent storage is not initialized by a rejected import or export',
    () async {
      SharedPreferences.setMockInitialValues({});
      await expectLater(store.importBackup('{'), throwsFormatException);
      await expectLater(store.exportBackup(), throwsStateError);
      expect(await raw(), isNull);
      await store.importBackup(encodeProfileBackup([incoming]));
      expect((await store.load()).single.id, incoming.id);
    },
  );

  test(
    'export sanitizes legacy credentials without rewriting preferences',
    () async {
      const legacy =
          '[{"id":"old","name":"قديم","proxy":"user:secret@host:80"}]';
      SharedPreferences.setMockInitialValues({key: legacy});
      final backup = await store.exportBackup();
      expect(backup, isNot(contains('secret')));
      expect(decodeProfileBackup(backup).single.proxyNeedsReview, isTrue);
      expect(await raw(), legacy);
    },
  );

  test(
    'a failed platform write reports failure and preserves stored data',
    () async {
      for (final throwOnWrite in [false, true]) {
        SharedPreferences.setMockInitialValues({});
        final backend = _FailingPreferences({
          'flutter.$key': encodeProfiles([existing]),
        }, throwOnWrite: throwOnWrite);
        SharedPreferencesStorePlatform.instance = backend;
        await expectLater(
          store.importBackup(encodeProfileBackup([incoming])),
          throwsStateError,
        );
        expect(
          (await backend.getAll())['flutter.$key'],
          encodeProfiles([existing]),
        );
        expect(await raw(), encodeProfiles([existing]));
        expect(
          decodeProfileBackup(await store.exportBackup()).single.id,
          existing.id,
        );
      }
    },
  );
}

class _FailingPreferences extends InMemorySharedPreferencesStore {
  final bool throwOnWrite;
  _FailingPreferences(Map<String, Object> data, {required this.throwOnWrite})
      : super.withData(data);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throwOnWrite) throw StateError('Simulated device write failure');
    return false;
  }
}
