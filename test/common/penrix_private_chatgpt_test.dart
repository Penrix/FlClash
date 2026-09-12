import 'package:fl_clash/common/penrix_private.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatGPT P0 covers current official network dependencies', () {
    final config = <String, dynamic>{
      'proxy-groups': [
        {
          'name': 'Residential',
          'type': 'select',
          'proxies': ['Cox-US'],
        },
      ],
      'proxies': [
        {'name': 'Cox-US', 'type': 'ss'},
      ],
    };
    final rules = buildPenrixPrivateRulePrefix(config, [
      'DOMAIN-SUFFIX,openai.com,Residential',
      'MATCH,DIRECT',
    ]);

    expect(rules, contains('PROCESS-NAME,com.openai.chatgpt,Residential'));
    expect(rules, contains('PROCESS-NAME,ChatGPT.exe,Residential'));
    expect(rules, contains('DOMAIN,ws.chatgpt.com,Residential'));
    expect(rules, contains('DOMAIN,cdn.openaimerge.com,Residential'));
    expect(rules, contains('DOMAIN,cdn.workos.com,Residential'));
    expect(rules, contains('DOMAIN,challenges.cloudflare.com,Residential'));
    expect(rules, contains('DOMAIN,setup.workos.com,Residential'));
    expect(
      rules,
      contains('DOMAIN,rum.browser-intake-datadoghq.com,Residential'),
    );
  });
}
