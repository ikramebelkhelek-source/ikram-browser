// Run without Flutter: dart flutter/ikram_browser/tool/check_domain.dart
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
  print('Passed $checks domain checks.');
}
