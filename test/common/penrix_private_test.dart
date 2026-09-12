import 'package:fl_clash/common/penrix_private.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Penrix private network policy', () {
    test('reuses the subscription target already used for ChatGPT', () {
      final config = <String, dynamic>{
        'proxies': [
          {'name': 'Cox-US', 'type': 'ss'},
        ],
        'proxy-groups': [
          {
            'name': '节点选择',
            'type': 'select',
            'proxies': ['Cox-US'],
          },
        ],
      };
      final target = inferPenrixProxyTarget(config, [
        'DOMAIN-SUFFIX,openai.com,节点选择',
        'MATCH,DIRECT',
      ]);

      expect(target, '节点选择');
    });

    test('falls back to a selector and then a concrete proxy', () {
      expect(
        inferPenrixProxyTarget(<String, dynamic>{
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
        }, const []),
        'Residential',
      );

      expect(
        inferPenrixProxyTarget(<String, dynamic>{
          'proxies': [
            {'name': 'Cox-US', 'type': 'ss'},
          ],
        }, const []),
        'Cox-US',
      );
    });

    test('puts ChatGPT reliability ahead of generic filtering', () {
      final config = buildPenrixPrivateNetworkConfig(<String, dynamic>{
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
        'rules': ['MATCH,DIRECT'],
      });

      final rules = List<String>.from(config['rules'] as List);
      final chatGptProcess = rules.indexOf(
        'PROCESS-NAME,com.openai.chatgpt,Residential',
      );
      final webSocket = rules.indexOf(
        'DOMAIN,ws.chatgpt.com,Residential',
      );
      final adblock = rules.indexOf(
        'RULE-SET,$penrixAdblockProviderName,REJECT',
      );
      final originalMatch = rules.indexOf('MATCH,DIRECT');

      expect(chatGptProcess, 0);
      expect(webSocket, greaterThan(chatGptProcess));
      expect(adblock, greaterThan(webSocket));
      expect(originalMatch, greaterThan(adblock));
    });

    test('forces UAA direct while other private sites use the proxy', () {
      final config = buildPenrixPrivateNetworkConfig(<String, dynamic>{
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
        'rules': ['MATCH,DIRECT'],
      });

      final rules = List<String>.from(config['rules'] as List);
      expect(rules, contains('DOMAIN-SUFFIX,uaa.com,DIRECT'));
      expect(rules, contains('DOMAIN-SUFFIX,uaa002.com,DIRECT'));
      expect(rules, contains('DOMAIN-SUFFIX,twkan.com,Residential'));
      expect(rules, contains('DOMAIN-SUFFIX,pornhub.com,Residential'));
      expect(rules, contains('DOMAIN-KEYWORD,missav,Residential'));
    });

    test('installs the adblock MRS provider through the proxy target', () {
      final config = buildPenrixPrivateNetworkConfig(<String, dynamic>{
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
      });

      final providers = config['rule-providers'] as Map;
      final provider = providers[penrixAdblockProviderName] as Map;
      expect(provider['type'], 'http');
      expect(provider['behavior'], 'domain');
      expect(provider['format'], 'mrs');
      expect(provider['url'], penrixAdblockProviderUrl);
      expect(provider['interval'], penrixAdblockUpdateInterval);
      expect(provider['proxy'], 'Residential');
    });

    test('does not duplicate rules already present in a profile', () {
      final config = buildPenrixPrivateNetworkConfig(<String, dynamic>{
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
        'rules': [
          'DOMAIN-SUFFIX,github.com,Residential',
          'MATCH,DIRECT',
        ],
      });

      final rules = List<String>.from(config['rules'] as List);
      expect(
        rules.where((rule) => rule == 'DOMAIN-SUFFIX,github.com,Residential'),
        hasLength(1),
      );
    });

    test('keeps the private layer above custom overwrite rules', () {
      final rawConfig = <String, dynamic>{
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
      final customRules = [
        'DOMAIN-SUFFIX,openai.com,Residential',
        'MATCH,DIRECT',
      ];
      final config = buildPenrixPrivateNetworkConfig(
        rawConfig,
        routingRules: customRules,
      );
      final merged = mergePenrixPrivateRules(
        config,
        customRules,
        routingRules: customRules,
      );

      expect(merged.first, 'PROCESS-NAME,com.openai.chatgpt,Residential');
      expect(
        merged.indexOf('RULE-SET,$penrixAdblockProviderName,REJECT'),
        lessThan(merged.indexOf('MATCH,DIRECT')),
      );
      expect(
        merged.where(
          (rule) => rule == 'DOMAIN-SUFFIX,openai.com,Residential',
        ),
        hasLength(1),
      );
    });

    test('still enables direct UAA and adblocking without a proxy', () {
      final config = buildPenrixPrivateNetworkConfig(<String, dynamic>{
        'rules': ['MATCH,DIRECT'],
      });

      final rules = List<String>.from(config['rules'] as List);
      expect(rules, contains('DOMAIN-SUFFIX,uaa.com,DIRECT'));
      expect(rules, contains('RULE-SET,$penrixAdblockProviderName,REJECT'));
      expect(
        rules.any((rule) => rule.startsWith('PROCESS-NAME,com.openai.chatgpt,')),
        false,
      );
    });
  });
}
