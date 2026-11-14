import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ikram_browser/domain.dart';
import 'package:ikram_browser/profile_backup_files.dart';
import 'package:profile_backup_documents/profile_backup_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const files = ProfileBackupFiles();
  const profile = Profile(
    id: 'معرّف-١',
    name: 'إكرام — مُتصفِّح العربية 🧭\nالسطر الثاني',
    proxy: 'https://proxy.example:443',
    proxyNeedsReview: true,
  );
  final source = encodeProfileBackup([profile]);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(ProfileBackupDocuments.channel, null);
  });

  test('saves exact UTF-8 bytes, reopens them without Arabic loss', () async {
    Uint8List? stored;
    messenger.setMockMethodCallHandler(ProfileBackupDocuments.channel,
        (call) async {
      final args = call.arguments as Map;
      if (call.method == 'save') {
        stored = args['bytes'] as Uint8List;
        return true;
      }
      expect(call.method, 'open');
      expect(args['maxBytes'], maxProfileBackupLength * 3);
      return stored;
    });
    expect(await files.save(source), isTrue);
    expect(stored, utf8.encode(source));
    final reopened = await files.open();
    expect(reopened, source);
    final restored = decodeProfileBackup(reopened!).single;
    expect(restored.id, profile.id);
    expect(restored.name, profile.name);
    expect(restored.proxy, profile.proxy);
    expect(restored.proxyNeedsReview, isTrue);
  });

  test('system picker cancellation is not success or an empty import',
      () async {
    messenger.setMockMethodCallHandler(
        ProfileBackupDocuments.channel, (_) async => null);
    expect(await files.save(source), isFalse);
    expect(await files.open(), isNull);
  });

  test('provider failures propagate without returning false success', () async {
    messenger.setMockMethodCallHandler(ProfileBackupDocuments.channel,
        (_) async => throw PlatformException(code: 'storage_error'));
    await expectLater(files.save(source), throwsA(isA<PlatformException>()));
    await expectLater(files.open(), throwsA(isA<PlatformException>()));
  });

  test('malformed UTF-8 is rejected rather than silently replaced', () async {
    messenger.setMockMethodCallHandler(ProfileBackupDocuments.channel,
        (_) async => Uint8List.fromList([0xD8]));
    await expectLater(files.open(), throwsFormatException);
  });

  test('UTF-8 BOM is accepted', () async {
    messenger.setMockMethodCallHandler(
        ProfileBackupDocuments.channel,
        (_) async =>
            Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(source)]));
    expect(await files.open(), source);
  });

  test('character limit is checked independently of UTF-8 byte limit',
      () async {
    messenger.setMockMethodCallHandler(ProfileBackupDocuments.channel,
        (_) async => Uint8List(maxProfileBackupLength + 1));
    await expectLater(files.open(), throwsFormatException);
  });

  test('oversized provider bytes are rejected defensively', () async {
    messenger.setMockMethodCallHandler(ProfileBackupDocuments.channel,
        (_) async => Uint8List(maxProfileBackupLength * 3 + 1));
    await expectLater(files.open(), throwsFormatException);
  });

  test('invalid export schema never invokes document picker', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(ProfileBackupDocuments.channel,
        (_) async {
      calls++;
      return true;
    });
    await expectLater(files.save('{"cookies":[]}'), throwsFormatException);
    expect(calls, 0);
  });
}
