import 'package:fl_clash/common/penrix_private.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Penrix provider download routing', () {
    test('keeps a safe select group used by ChatGPT', () {
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

      expect(
        inferPenrixProviderDownloadTarget(config, 'Residential'),
        'Residential',
      );
    });

    test('does not use a url-test group for provider downloads', () {
      final config = <String, dynamic>{
        'proxy-groups': [
          {
            'name': 'Auto',
            'type': 'url-test',
            'proxies': ['Cox-US'],
          },
          {
            'name': '节点选择',
            'type': 'select',
            'proxies': ['Auto', 'Cox-US'],
          },
        ],
        'proxies': [
          {'name': 'Cox-US', 'type': 'ss'},
        ],
      };

      expect(inferPenrixProviderDownloadTarget(config, 'Auto'), '节点选择');
    });

    test('omits provider proxy when only an unsafe group exists', () {
      final config = buildPenrixPrivateNetworkConfig(<String, dynamic>{
        'proxy-groups': [
          {
            'name': 'Auto',
            'type': 'url-test',
            'proxies': ['Cox-US'],
          },
        ],
        'proxies': const <Map<String, String>>[],
        'rules': ['DOMAIN-SUFFIX,openai.com,Auto', 'MATCH,DIRECT'],
      });

      final provider =
          (config['rule-providers'] as Map)[penrixAdblockProviderName] as Map;
      expect(provider.containsKey('proxy'), false);
    });
  });
}
