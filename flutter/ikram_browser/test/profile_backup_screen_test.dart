import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ikram_browser/domain.dart';
import 'package:ikram_browser/profile_store.dart';
import 'package:ikram_browser/profiles_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
