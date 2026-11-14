import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ikram_browser/domain.dart';
import 'package:ikram_browser/profile_store.dart';
import 'package:ikram_browser/profiles_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:profile_backup_documents/profile_backup_documents.dart';

void main() {
  const existing = Profile(id: 'existing', name: 'محفوظ');
  const incoming = Profile(id: 'incoming', name: 'مستورد');
  final backup = encodeProfileBackup([incoming]);

  Future<String?> raw() async =>
      (await SharedPreferences.getInstance()).getString('ikram_profiles');

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ikram_profiles': encodeProfiles([existing]),
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileBackupDocuments.channel, null);
  });

  void documents(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileBackupDocuments.channel, handler);
  }

  // The screen intentionally keeps an indeterminate progress indicator active
  // while a dialog holds the operation lock. Do not wait for all frames to end.
  Future<void> render(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openImport(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfilesScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('استيراد إعدادات البروفايلات'));
    await render(tester);
  }

  FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'تأكيد الاستيراد'),
      );

  testWidgets('preview does not write; confirmation persists all profiles', (
    tester,
  ) async {
    await openImport(tester);
    final before = await raw();
    expect(confirm(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), backup);
    await tester.tap(find.text('معاينة الاستيراد'));
    await render(tester);
    expect(find.text('• مستورد'), findsOneWidget);
    expect(await raw(), before);
    expect(confirm(tester).onPressed, isNotNull);
    await tester.tap(find.text('تأكيد الاستيراد'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect((await ProfileStore().load()).map((p) => p.id), [
      'existing',
      'incoming',
    ]);
    expect(find.text('مستورد'), findsOneWidget);
  });

  testWidgets('cancel after preview leaves preferences unchanged', (
    tester,
  ) async {
    await openImport(tester);
    final before = await raw();
    await tester.enterText(find.byType(TextField), backup);
    await tester.tap(find.text('معاينة الاستيراد'));
    await render(tester);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(await raw(), before);
  });

  testWidgets(
    'editing validated text disables confirmation until revalidated',
    (tester) async {
      await openImport(tester);
      await tester.enterText(find.byType(TextField), backup);
      await tester.tap(find.text('معاينة الاستيراد'));
      await render(tester);
      expect(confirm(tester).onPressed, isNotNull);
      await tester.enterText(find.byType(TextField), '{');
      await render(tester);
      expect(confirm(tester).onPressed, isNull);
      await tester.tap(find.text('معاينة الاستيراد'));
      await render(tester);
      expect(confirm(tester).onPressed, isNull);
      expect(await raw(), encodeProfiles([existing]));
    },
  );

  testWidgets(
    'conflicting IDs allow backup inspection but never confirmation',
    (tester) async {
      await openImport(tester);
      await tester.enterText(
        find.byType(TextField),
        encodeProfileBackup([existing]),
      );
      await tester.tap(find.text('معاينة الاستيراد'));
      await render(tester);
      expect(find.text('• محفوظ'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);
      expect(await raw(), encodeProfiles([existing]));
    },
  );

  testWidgets('export shows configurations and limitations without writing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProfilesScreen()));
    await tester.pumpAndSettle();
    final before = await raw();
    await tester.tap(find.byTooltip('تصدير إعدادات البروفايلات'));
    await render(tester);
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(decodeProfileBackup(text.data!).single.id, existing.id);
    expect(find.textContaining('لا تشمل كوكيز'), findsOneWidget);
    expect(find.textContaining('حُذف دون نسخة سابقة'), findsOneWidget);
    expect(await raw(), before);
  });

  testWidgets('opening Arabic file previews only; confirmation imports', (
    tester,
  ) async {
    const arabic = Profile(
      id: 'جديد-٢',
      name: 'إكرام — مُتصفِّح 🧭',
      proxy: 'socks://proxy.example:1080',
    );
    final source = encodeProfileBackup([arabic]);
    documents((call) async {
      expect(call.method, 'open');
      return Uint8List.fromList(utf8.encode(source));
    });
    await openImport(tester);
    final before = await raw();
    await tester.tap(find.text('فتح ملف'));
    await render(tester);
    expect(find.text('• ${arabic.name}'), findsOneWidget);
    expect(await raw(), before);
    expect(confirm(tester).onPressed, isNotNull);
    await tester.tap(find.text('تأكيد الاستيراد'));
    await tester.pumpAndSettle();
    final restored = (await ProfileStore().load()).last;
    expect(restored.id, arabic.id);
    expect(restored.name, arabic.name);
    expect(restored.proxy, arabic.proxy);
  });

  testWidgets('cancelling file picker leaves input and saved profiles intact', (
    tester,
  ) async {
    documents((_) async => null);
    await openImport(tester);
    final before = await raw();
    await tester.enterText(find.byType(TextField), backup);
    await tester.tap(find.text('معاينة الاستيراد'));
    await render(tester);
    await tester.ensureVisible(find.text('فتح ملف'));
    await tester.tap(find.text('فتح ملف'));
    await render(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        backup);
    expect(confirm(tester).onPressed, isNull);
    expect(await raw(), before);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(await raw(), before);
  });

  testWidgets('failed file read invalidates old preview and permits retry', (
    tester,
  ) async {
    var fail = true;
    documents((_) async {
      if (fail) throw PlatformException(code: 'storage_error');
      return Uint8List.fromList(utf8.encode(backup));
    });
    await openImport(tester);
    await tester.enterText(find.byType(TextField), backup);
    await tester.tap(find.text('معاينة الاستيراد'));
    await render(tester);
    await tester.ensureVisible(find.text('فتح ملف'));
    await tester.tap(find.text('فتح ملف'));
    await render(tester);
    expect(confirm(tester).onPressed, isNull);
    expect(find.textContaining('تعذّر فتح الملف'), findsOneWidget);
    expect(await raw(), encodeProfiles([existing]));
    fail = false;
    await tester.tap(find.text('فتح ملف'));
    await render(tester);
    expect(confirm(tester).onPressed, isNotNull);
  });

  testWidgets('file containing new and conflicting IDs cannot partly import', (
    tester,
  ) async {
    documents((_) async => Uint8List.fromList(
        utf8.encode(encodeProfileBackup([incoming, existing]))));
    await openImport(tester);
    await tester.tap(find.text('فتح ملف'));
    await render(tester);
    expect(find.text('• مستورد'), findsOneWidget);
    expect(find.text('• محفوظ'), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);
    expect(await raw(), encodeProfiles([existing]));
  });

  testWidgets('invalid file schemas and repeated IDs never enable import', (
    tester,
  ) async {
    var source = '{"format":"unknown","version":1,"profiles":[]}';
    documents((_) async => Uint8List.fromList(utf8.encode(source)));
    await openImport(tester);
    for (final invalid in [
      source,
      backup.replaceFirst('"incoming"', '"existing"'),
      backup.replaceFirst(
          '"profiles": [',
          '"profiles": ['
              '${jsonEncode(incoming.toJson())},'),
      backup.substring(0, backup.length - 3),
    ]) {
      source = invalid;
      await tester.tap(find.text('فتح ملف'));
      await render(tester);
      expect(confirm(tester).onPressed, isNull);
      expect(await raw(), encodeProfiles([existing]));
    }
  });

  testWidgets('dialog cancellation after file preview never persists', (
    tester,
  ) async {
    documents((_) async => Uint8List.fromList(utf8.encode(backup)));
    await openImport(tester);
    await tester.tap(find.text('فتح ملف'));
    await render(tester);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(await raw(), encodeProfiles([existing]));
  });

  testWidgets('pending picker disables confirmation, editing and repeat open', (
    tester,
  ) async {
    final result = Completer<Object?>();
    var calls = 0;
    documents((_) {
      calls++;
      return result.future;
    });
    await openImport(tester);
    await tester.tap(find.text('فتح ملف'));
    await render(tester);
    expect(confirm(tester).onPressed, isNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'إلغاء'))
            .onPressed,
        isNull);
    await tester.tap(find.text('فتح ملف'));
    expect(calls, 1);
    result.complete(Uint8List.fromList(utf8.encode(backup)));
    await render(tester);
    expect(confirm(tester).onPressed, isNotNull);
    expect(await raw(), encodeProfiles([existing]));
  });

  testWidgets('late file result after route disposal cannot save or update UI',
      (
    tester,
  ) async {
    final result = Completer<Object?>();
    documents((_) => result.future);
    await openImport(tester);
    await tester.tap(find.text('فتح ملف'));
    await render(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    result.complete(Uint8List.fromList(utf8.encode(backup)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(await raw(), encodeProfiles([existing]));
  });

  testWidgets('pending save prevents duplicate requests and premature close', (
    tester,
  ) async {
    final result = Completer<Object?>();
    var calls = 0;
    documents((_) {
      calls++;
      return result.future;
    });
    await tester.pumpWidget(const MaterialApp(home: ProfilesScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تصدير إعدادات البروفايلات'));
    await render(tester);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'حفظ ملف'),
    );
    // Simulate two activations before Flutter has rebuilt the disabled button.
    button.onPressed!();
    button.onPressed!();
    await render(tester);
    expect(calls, 1);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'إغلاق'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('تم حفظ ملف'), findsNothing);
    result.complete(null);
    await render(tester);
    expect(find.textContaining('أُلغي حفظ الملف'), findsOneWidget);
    expect(await raw(), encodeProfiles([existing]));
  });

  testWidgets('export distinguishes cancellation, provider failure and save', (
    tester,
  ) async {
    var outcome = 'cancel';
    documents((call) async {
      expect(call.method, 'save');
      expect(
        utf8.decode((call.arguments as Map)['bytes'] as Uint8List),
        encodeProfileBackup([existing]),
      );
      if (outcome == 'fail') throw PlatformException(code: 'storage_error');
      return outcome == 'save' ? true : null;
    });
    await tester.pumpWidget(const MaterialApp(home: ProfilesScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تصدير إعدادات البروفايلات'));
    await render(tester);
    await tester.tap(find.text('حفظ ملف'));
    await render(tester);
    expect(find.textContaining('أُلغي حفظ الملف'), findsOneWidget);
    expect(find.textContaining('تم حفظ ملف'), findsNothing);
    outcome = 'fail';
    await tester.tap(find.text('حفظ ملف'));
    await render(tester);
    expect(find.textContaining('تعذّر حفظ الملف كاملاً'), findsOneWidget);
    expect(find.textContaining('تم حفظ ملف'), findsNothing);
    outcome = 'save';
    await tester.tap(find.text('حفظ ملف'));
    await render(tester);
    expect(find.textContaining('تم حفظ ملف الإعدادات'), findsOneWidget);
    expect(await raw(), encodeProfiles([existing]));
  });
}
