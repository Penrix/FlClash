import 'package:fl_clash/common/penrix_android_dns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes only the direct top-level dns listen entry', () {
    const source = '''
dns:
  enable: true
  listen: 0.0.0.0:7874
  enhanced-mode: fake-ip
  nameserver:
    - 1.1.1.1
  nested:
    listen: keep-me
rules:
  - MATCH,DIRECT
''';

    final result = stripExternalDnsListenFromYaml(source);

    expect(result, isNot(contains('  listen: 0.0.0.0:7874')));
    expect(result, contains('  enhanced-mode: fake-ip'));
    expect(result, contains('    - 1.1.1.1'));
    expect(result, contains('    listen: keep-me'));
    expect(result, contains('rules:'));
  });

  test('leaves profiles without a dns listener untouched', () {
    const source = '''
dns:
  enable: true
  nameserver:
    - 1.1.1.1
''';

    expect(stripExternalDnsListenFromYaml(source), source);
  });
}
