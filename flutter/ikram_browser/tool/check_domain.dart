// Run without Flutter: dart flutter/ikram_browser/tool/check_domain.dart
import 'dart:convert';

import '../lib/domain.dart';

int checks = 0;

void expect(bool condition, String label) {
  if (!condition) throw StateError('FAILED: $label');
  checks++;
}

void rejects(void Function() action, String label) {
  try {
    action();
  } on FormatException {
    checks++;
    return;
  }
  throw StateError('FAILED: $label was accepted');
}

void main() {
  expect(ProxyEndpoint.parse('') == null, 'empty means system network');
  expect(
    ProxyEndpoint.parse('proxy.example:8080')!.url ==
        'http://proxy.example:8080',
    'normalize proxy',
  );
  expect(
    ProxyEndpoint.parse('https://proxy.example')!.url ==
        'https://proxy.example:443',
    'HTTPS default port',
  );
  expect(
    ProxyEndpoint.parse('socks://proxy.example')!.url ==
        'socks://proxy.example:1080',
    'SOCKS default port',
  );
  expect(
    ProxyEndpoint.parse('[::1]:8080')!.url == 'http://[::1]:8080',
    'IPv6 endpoint',
  );
  for (final value in [
    'user:password@proxy.example:8080',
    'http://user:password@proxy.example:8080',
    'proxy.example:0',
    'proxy.example:65536',
    'proxy.example:wrong',
    'proxy.example/path',
    'proxy.example?query=1',
    'proxy.example#fragment',
    'proxy example:8080',
    'ftp://proxy.example:21',
    'http://',
  ]) {
    rejects(() => ProxyEndpoint.parse(value), 'invalid proxy');
  }
  expect(
    resolveAddress('shein.com').toString() == 'https://shein.com',
    'bare website',
  );
  expect(
    resolveAddress('example.com:8080/path').toString() ==
        'https://example.com:8080/path',
    'bare website with port',
  );
  expect(
    resolveAddress('https://example.com/path?a=1&b=2').query == 'a=1&b=2',
    'existing URL query',
  );
  expect(
    resolveAddress('ملابس & shoes #1').queryParameters['q'] ==
        'ملابس & shoes #1',
    'encoded search',
  );
  for (final value in [
    '',
    'javascript:alert(1)',
    'data:text/html,test',
    'file:///etc/passwd',
    'ftp://example.com',
    'https://user:password@example.com',
    'https://',
  ]) {
    rejects(() => resolveAddress(value), 'unsafe address');
  }
  const profile = Profile(id: 'one', name: 'متجر', proxy: 'host.example:80');
  final copy = decodeProfiles(encodeProfiles([profile])).single;
  expect(copy.id == profile.id, 'ID preserved');
  expect(copy.name == profile.name, 'Arabic preserved');
  expect(copy.proxy == profile.proxy, 'proxy preserved');
  expect(decodeProfiles('[]').isEmpty, 'empty stays empty');
  final legacy = decodeProfiles(
    '[{"id":"one","name":"قديم","proxy":"user:secret@host.example:8080"}]',
  ).single;
  expect(legacy.proxy.isEmpty, 'legacy credentials removed');
  expect(legacy.proxyNeedsReview, 'legacy profile blocked until reviewed');
  expect(
    !encodeProfiles([legacy]).contains('secret'),
    'legacy secret not persisted',
  );
  expect(
    decodeProfiles(encodeProfiles([legacy])).single.proxyNeedsReview,
    'review requirement survives restart',
  );
  for (final value in [
    '{',
    '{}',
    '[null]',
    '[{"id":1,"name":"name"}]',
    '[{"id":"1","name":""}]',
    '[{"id":"1","name":"name","proxy":42}]',
    '[{"id":"1","name":"a"},{"id":"1","name":"b"}]',
  ]) {
    rejects(() => decodeProfiles(value), 'invalid stored data');
  }
  final backup = encodeProfileBackup([
    profile,
    const Profile(id: 'review', name: 'مراجعة', proxyNeedsReview: true),
    const Profile(id: 'system', name: 'شبكة النظام'),
  ]);
  final restored = decodeProfileBackup(backup);
  expect(restored.length == 3, 'backup count');
  expect(restored.first.id == profile.id, 'backup ID preserved');
  expect(restored.first.name == profile.name, 'backup Arabic preserved');
  expect(restored.first.proxy == profile.proxy, 'backup proxy preserved');
  expect(restored[1].proxyNeedsReview, 'backup retains required review');
  expect(restored[2].proxy.isEmpty, 'backup retains system network');
  expect(
    encodeProfileBackup(restored) == backup,
    'backup round trip is lossless',
  );
  expect(
    decodeProfileBackup(encodeProfileBackup([])).isEmpty,
    'empty backup is valid',
  );
  final saved = [const Profile(id: 'saved', name: 'موجود')];
  final merged = mergeProfileBackup(saved, backup);
  expect(identical(merged.first, saved.first), 'merge keeps saved record');
  expect(saved.length == 1, 'merge does not mutate input list');
  expect(merged.length == 4, 'merge adds all backup records');
  rejects(() => mergeProfileBackup(merged, backup), 're-import rejected');
  rejects(
    () => mergeProfileBackup([profile], backup),
    'existing ID conflict rejects entire import',
  );
  expect(saved.single.name == 'موجود', 'rejected merge leaves input intact');
  String wrap(Object? entries, {Object? version = 1}) => jsonEncode({
        'format': 'ikram-profile-configurations',
        'version': version,
        'profiles': entries,
      });
  for (final value in [
    '',
    '{',
    '[]',
    '{}',
    encodeProfiles([profile]), // Internal legacy storage is not a backup.
    backup.substring(0, backup.length - 1),
    backup.replaceFirst('ikram-profile-configurations', 'unknown'),
    wrap([], version: 2),
    wrap([], version: '1'),
    wrap([], version: 1.0),
    wrap({}),
    wrap([null]),
    wrap([profile.toJson(), profile.toJson()]),
    jsonEncode({...jsonDecode(backup) as Map, 'cookies': []}),
  ]) {
    rejects(() => decodeProfileBackup(value), 'invalid backup');
  }
  for (final field in ['id', 'name', 'proxy', 'proxyNeedsReview']) {
    final entry = {...profile.toJson()}..remove(field);
    rejects(() => decodeProfileBackup(wrap([entry])), 'missing $field');
    entry[field] = null;
    rejects(() => decodeProfileBackup(wrap([entry])), 'null $field');
  }
  for (final change in [
    {'id': ' '},
    {'id': ' one '},
    {'id': 1},
    {'name': ''},
    {'name': 123},
    {'proxy': 123},
    {'proxy': 'user:secret@host:8080'},
    {'proxy': 'host:0'},
    {'proxy': 'ftp://host:21'},
    {'proxyNeedsReview': 'false'},
    {'cookies': 'must not be imported'},
  ]) {
    rejects(
      () => decodeProfileBackup(
        wrap([
          {...profile.toJson(), ...change},
        ]),
      ),
      'invalid backup record',
    );
  }
  rejects(
    () => decodeProfileBackup(' ' * (maxProfileBackupLength + 1)),
    'oversized backup',
  );
  rejects(
    () => encodeProfileBackup([profile, profile]),
    'invalid export rejected',
  );
  expect(
    !encodeProfileBackup([legacy]).contains('secret'),
    'export cannot leak sanitized legacy credentials',
  );
  print('Passed $checks domain checks.');
}
