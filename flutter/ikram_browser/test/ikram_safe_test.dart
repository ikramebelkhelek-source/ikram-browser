import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ikram_browser/browser_chrome.dart';
import 'package:ikram_browser/browser_identity.dart';
import 'package:ikram_browser/browser_services.dart';
import 'package:ikram_browser/identity_store.dart';
import 'package:ikram_browser/proxy_country.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      'Version/4.0 Chrome/130.0.6723.40 Mobile Safari/537.36';

  setUp(() {
    SharedPreferences.setMockInitialValues({'ikram_profiles': 'preserved'});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ikram_safe/privacy'), null);
  });

  test('new persona changes exposed device but retains actual engine version', () {
    final first = BrowserIdentity.generate(engine);
    final second = BrowserIdentity.generate(engine, previous: first);
    expect(first.id, isNot(second.id));
    expect(first.device, isNot(second.device));
    expect(second.userAgent, contains('Chrome/130.0.6723.40'));
    expect(second.script, contains('hardwareConcurrency'));
    expect(second.script, isNot(contains(second.id)));
    expect(BrowserIdentity.fromJson(second.toJson()).userAgent, second.userAgent);
    expect(() => BrowserIdentity.generate('Firefox/140'), throwsFormatException);
    expect(() => BrowserIdentity.fromJson({}), throwsFormatException);
  });

  test('personas persist independently of saved profiles', () async {
    final identity = BrowserIdentity.generate(engine);
    await IdentityStore().save('one', identity);
    expect((await IdentityStore().load('one'))!.id, identity.id);
    expect(await IdentityStore().load('other'), isNull);
    expect((await SharedPreferences.getInstance()).getString('ikram_profiles'),
        'preserved');
  });

  test('shopping queries are encoded and no affiliate tags are fabricated', () {
    for (final target in ['web', 'shein', 'amazon', 'aliexpress']) {
      final uri = shoppingSearch('حذاء & shoes / #1', target);
      expect(uri.scheme, 'https');
      expect(uri.userInfo, isEmpty);
      expect(uri.queryParameters.containsKey('tag'), isFalse);
      expect(uri.fragment, isEmpty);
    }
    expect(shoppingSearch('red shoes', 'amazon').queryParameters['k'], 'red shoes');
    expect(() => shoppingSearch('', 'shein'), throwsFormatException);
    expect(() => shoppingSearch('shoes', 'unknown'), throwsFormatException);
  });

  test('country result is validated instead of guessed', () {
    final country = ProxyCountry.parse(
        jsonEncode({'country': 'MA', 'ip': '192.0.2.10'}));
    expect(country.code, 'MA');
    expect(() => ProxyCountry.parse('{}'), throwsFormatException);
    expect(() => ProxyCountry.parse('{"country":"unknown","ip":"x"}'),
        throwsFormatException);
  });

  test('cleanup reports full versus partial without deleting profile settings',
      () async {
    var complete = true;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('ikram_safe/privacy'),
      (call) async {
        expect(call.method, 'clearAll');
        calls++;
        return {'complete': complete};
      },
    );
    expect((await clearSharedBrowsingData()).complete, isTrue);
    complete = false;
    expect((await clearSharedBrowsingData()).complete, isFalse);
    expect(calls, 2);
    expect((await SharedPreferences.getInstance()).getString('ikram_profiles'),
        'preserved');
  });

  test('cleanup does not claim success if the native bridge fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('ikram_safe/privacy'),
      (_) async => throw PlatformException(code: 'CLEANUP_FAILED'),
    );
    await expectLater(clearSharedBrowsingData(), throwsA(isA<PlatformException>()));
  });

  testWidgets('native controls stay usable on a small Arabic phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var clears = 0;
    var generates = 0;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(child: Column(children: [
            SafeProxyBar(endpoint: 'proxy.example:8080',
                countryLabel: 'البلد: MA', enabled: true, busy: false,
                detecting: false, onEdit: () {}, onToggle: (_) {}, onDetect: () {}),
            SafeSearchBar(controller: controller, target: 'shein',
                onTargetChanged: (_) {}, onSubmit: () {}, onReload: () {},
                enabled: true),
            SafeFingerprintCard(title: 'Pixel 7', details: 'خصائص تجريبية',
                onGenerate: () => generates++),
          ])),
          bottomNavigationBar: SafeClearDock(
              onClear: () => clears++, busy: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pump();
    expect(clears, 1);
    await tester.ensureVisible(find.byIcon(Icons.autorenew));
    await tester.tap(find.byIcon(Icons.autorenew));
    expect(generates, 1);
    expect(tester.takeException(), isNull);
  });
}
