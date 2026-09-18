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

    test('does not steal a target from another enhanced service', () {
      final config = <String, dynamic>{
        'proxies': [
          {'name': 'Cox-US', 'type': 'ss'},
        ],
        'proxy-groups': [
          {
            'name': 'GoogleOnly',
            'type': 'select',
            'proxies': ['Cox-US'],
          },
          {
            'name': 'Residential',
            'type': 'select',
            'proxies': ['Cox-US'],
          },
        ],
      };
      final target = inferPenrixProxyTarget(config, [
        'DOMAIN-SUFFIX,google.com,GoogleOnly',
        'DOMAIN-SUFFIX,openai.com,Residential',
        'MATCH,DIRECT',
      ]);

      expect(target, 'Residential');
    });

    test('uses MATCH before an arbitrary selector fallback', () {
      final config = <String, dynamic>{
        'proxies': [
          {'name': 'Cox-US', 'type': 'ss'},
        ],
        'proxy-groups': [
          {
            'name': 'Special',
            'type': 'select',
            'proxies': ['Cox-US'],
          },
          {
            'name': 'Final',
            'type': 'select',
            'proxies': ['Cox-US'],
          },
        ],
      };

      expect(inferPenrixProxyTarget(config, ['MATCH,Final']), 'Final');
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
      final windowsChatGptProcess = rules.indexOf(
        'PROCESS-NAME,ChatGPT.exe,Residential',
      );
      final webSocket = rules.indexOf('DOMAIN,ws.chatgpt.com,Residential');
      final adblock = rules.indexOf(
        'RULE-SET,$penrixAdblockProviderName,REJECT',
      );
      final originalMatch = rules.indexOf('MATCH,DIRECT');

      expect(chatGptProcess, 0);
      expect(windowsChatGptProcess, greaterThan(chatGptProcess));
      expect(webSocket, greaterThan(windowsChatGptProcess));
      expect(adblock, greaterThan(webSocket));
      expect(originalMatch, greaterThan(adblock));
    });

    test('keeps ChatGPT on the inferred main proxy target', () {
      final config = buildPenrixPrivateNetworkConfig(<String, dynamic>{
        'proxy-groups': [
          {
            'name': 'Residential',
            'type': 'select',
            'proxies': ['Cox-US', 'Backup-US'],
          },
        ],
        'proxies': [
          {'name': 'Cox-US', 'type': 'ss'},
          {'name': 'Backup-US', 'type': 'vless'},
        ],
        'rules': ['DOMAIN-SUFFIX,openai.com,Residential', 'MATCH,DIRECT'],
      });

      final groups = List<Map<String, dynamic>>.from(
        config['proxy-groups'] as List,
      );
      expect(
        groups.where((group) => group['name'] == penrixChatGptGroupName),
        isEmpty,
      );

      final rules = List<String>.from(config['rules'] as List);
      expect(rules, contains('DOMAIN-SUFFIX,openai.com,Residential'));
      expect(rules, contains('PROCESS-NAME,com.openai.chatgpt,Residential'));
      expect(rules, contains('DOMAIN-SUFFIX,github.com,Residential'));
    });

    test('removes a legacy ChatGPT selector when rebuilding config', () {
      final config = buildPenrixPrivateNetworkConfig(<String, dynamic>{
        'proxy-groups': [
          {
            'name': penrixChatGptGroupName,
            'type': 'select',
            'proxies': ['Backup-US'],
          },
          {
            'name': 'Residential',
            'type': 'select',
            'proxies': ['Cox-US'],
          },
        ],
        'proxies': [
          {'name': 'Cox-US', 'type': 'ss'},
          {'name': 'Backup-US', 'type': 'vless'},
        ],
        'rules': ['DOMAIN-SUFFIX,openai.com,Residential', 'MATCH,DIRECT'],
      });
      final groups = List<Map<String, dynamic>>.from(
        config['proxy-groups'] as List,
      );
      final rules = List<String>.from(config['rules'] as List);

      expect(
        groups.where((group) => group['name'] == penrixChatGptGroupName),
        isEmpty,
      );
      expect(rules, contains('PROCESS-NAME,com.openai.chatgpt,Residential'));
    });

    test('can keep raw rules untouched while preparing standard additions', () {
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
        'rules': ['MATCH,DIRECT'],
      };
      final config = buildPenrixPrivateNetworkConfig(
        rawConfig,
        routingRules: ['DOMAIN-SUFFIX,openai.com,Residential', 'MATCH,DIRECT'],
        prependPrivateRules: false,
      );
      final addedRules = mergePenrixPrivateRules(
        config,
        ['DOMAIN-SUFFIX,example.com,DIRECT'],
        routingRules: ['DOMAIN-SUFFIX,openai.com,Residential', 'MATCH,DIRECT'],
      );

      expect(config['rules'], ['MATCH,DIRECT']);
      expect(addedRules.first, 'PROCESS-NAME,com.openai.chatgpt,Residential');
      expect(
        addedRules.indexOf('DOMAIN-SUFFIX,example.com,DIRECT'),
        greaterThan(addedRules.indexOf('DOMAIN-SUFFIX,openai.com,Residential')),
      );
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
        'rules': ['DOMAIN-SUFFIX,github.com,Residential', 'MATCH,DIRECT'],
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
        merged.where((rule) => rule == 'DOMAIN-SUFFIX,openai.com,Residential'),
        hasLength(1),
      );
    });

    test('service switches remove their owned rules and provider', () {
      const settings = PenrixPrivateSettings(
        chatGpt: false,
        twitter: false,
        telegram: false,
        github: false,
        google: false,
        pixiv: false,
        uaaDirect: false,
        privateSites: false,
        adblock: false,
      );
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
      }, settings: settings);

      expect(config['rules'], ['MATCH,DIRECT']);
      expect(
        (config['proxy-groups'] as List).where(
          (group) => group['name'] == penrixChatGptGroupName,
        ),
        isEmpty,
      );
      expect(
        (config['rule-providers'] as Map).containsKey(
          penrixAdblockProviderName,
        ),
        false,
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
        rules.any(
          (rule) => rule.startsWith('PROCESS-NAME,com.openai.chatgpt,'),
        ),
        false,
      );
    });
  });
}
