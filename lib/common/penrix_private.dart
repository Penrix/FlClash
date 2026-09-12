const String penrixAdblockProviderName = 'penrix-adblock';
const String penrixAdblockProviderUrl =
    'https://raw.githubusercontent.com/217heidai/adblockfilters/main/rules/adblockmihomo.mrs';
const int penrixAdblockUpdateInterval = 28800;

const Set<String> _reservedTargets = {
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
};

const List<String> _priorityServiceMarkers = [
  'openai',
  'chatgpt',
  'telegram',
  'twitter',
  'github',
  'google',
  'pixiv',
];

/// Applies the always-on private networking layer used by Penrix's FlClash
/// build. The subscription remains the source of proxies and groups; this
/// layer only makes critical application routing and filtering deterministic.
Map<String, dynamic> buildPenrixPrivateNetworkConfig(
  Map<String, dynamic> source,
) {
  final config = Map<String, dynamic>.from(source);
  final existingRules = _asStringList(config['rules']);
  final proxyTarget = inferPenrixProxyTarget(config, existingRules);

  final ruleProviders = <String, dynamic>{};
  final existingProviders = config['rule-providers'];
  if (existingProviders is Map) {
    for (final entry in existingProviders.entries) {
      ruleProviders[entry.key.toString()] = entry.value;
    }
  }
  ruleProviders[penrixAdblockProviderName] = <String, dynamic>{
    'type': 'http',
    'behavior': 'domain',
    'format': 'mrs',
    'url': penrixAdblockProviderUrl,
    'interval': penrixAdblockUpdateInterval,
    if (proxyTarget != null) 'proxy': proxyTarget,
  };
  config['rule-providers'] = ruleProviders;

  final privateRules = <String>[
    if (proxyTarget != null) ..._chatGptCriticalRules(proxyTarget),

    // UAA has been observed to authenticate successfully when direct while
    // failing through the residential-US proxy. Keep its own endpoints direct
    // before generic filtering or foreign-site forcing rules.
    'DOMAIN-SUFFIX,uaa.com,DIRECT',
    'DOMAIN-SUFFIX,uaa002.com,DIRECT',

    // Network-layer ad/tracker blocking for the whole device. Site-specific
    // cosmetic cleanup still belongs to the consuming app/WebView.
    'RULE-SET,$penrixAdblockProviderName,REJECT',

    if (proxyTarget != null) ..._commonAppRules(proxyTarget),
    if (proxyTarget != null) ..._privateSiteRules(proxyTarget),
  ];

  config['rules'] = _prependUnique(privateRules, existingRules);
  return config;
}

/// Finds a stable proxy target from the user's subscription rather than
/// assuming a group is literally named `PROXY`. The user's existing rules get
/// first say, then common selector names, then the first selectable group or
/// concrete proxy.
String? inferPenrixProxyTarget(
  Map<String, dynamic> config,
  List<String> rules,
) {
  final groupNames = <String>[];
  final selectorGroupNames = <String>[];
  final rawGroups = config['proxy-groups'];
  if (rawGroups is List) {
    for (final item in rawGroups) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim();
      if (name == null || name.isEmpty) continue;
      groupNames.add(name);
      final type = item['type']?.toString().toLowerCase();
      if (type == 'select' || type == 'selector') {
        selectorGroupNames.add(name);
      }
    }
  }

  final proxyNames = <String>[];
  final rawProxies = config['proxies'];
  if (rawProxies is List) {
    for (final item in rawProxies) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim();
      if (name != null && name.isNotEmpty) proxyNames.add(name);
    }
  }

  final availableTargets = {...groupNames, ...proxyNames};

  bool usable(String? target) {
    if (target == null) return false;
    final value = target.trim();
    if (value.isEmpty || _reservedTargets.contains(value.toUpperCase())) {
      return false;
    }
    return availableTargets.contains(value);
  }

  // Prefer the target that the existing subscription already uses for one of
  // the user's overseas services. This preserves the user's chosen selector.
  for (final rawRule in rules) {
    final lower = rawRule.toLowerCase();
    if (!_priorityServiceMarkers.any(lower.contains)) continue;
    final target = _simpleRuleTarget(rawRule);
    if (usable(target)) return target!.trim();
  }

  const preferredNames = [
    'PROXY',
    'Proxy',
    '节点选择',
    '節點選擇',
    '🚀 节点选择',
    '🚀 節點選擇',
    '代理',
    '美国',
    '美國',
    '美国家宽',
    '美國家寬',
  ];
  for (final preferred in preferredNames) {
    if (availableTargets.contains(preferred)) return preferred;
  }

  if (selectorGroupNames.isNotEmpty) return selectorGroupNames.first;
  if (groupNames.isNotEmpty) return groupNames.first;
  if (proxyNames.isNotEmpty) return proxyNames.first;
  return null;
}

List<String> _chatGptCriticalRules(String target) => [
  // Mihomo PROCESS-NAME matches Android package names. This is deliberately
  // first so a future ChatGPT endpoint cannot silently fall through to DIRECT.
  'PROCESS-NAME,com.openai.chatgpt,$target',
  'DOMAIN,ws.chatgpt.com,$target',
  'DOMAIN-SUFFIX,chatgpt.com,$target',
  'DOMAIN-SUFFIX,openai.com,$target',
  'DOMAIN-SUFFIX,oaistatic.com,$target',
  'DOMAIN-SUFFIX,oaiusercontent.com,$target',
  'DOMAIN-SUFFIX,oaistatsig.com,$target',
];

List<String> _commonAppRules(String target) => [
  // Twitter / X
  'PROCESS-NAME,com.twitter.android,$target',
  'DOMAIN-SUFFIX,x.com,$target',
  'DOMAIN-SUFFIX,twitter.com,$target',
  'DOMAIN-SUFFIX,twimg.com,$target',
  'DOMAIN-SUFFIX,t.co,$target',

  // Telegram
  'PROCESS-NAME,org.telegram.messenger,$target',
  'PROCESS-NAME,org.telegram.messenger.web,$target',
  'DOMAIN-SUFFIX,telegram.org,$target',
  'DOMAIN-SUFFIX,t.me,$target',
  'DOMAIN-SUFFIX,telegra.ph,$target',

  // GitHub
  'PROCESS-NAME,com.github.android,$target',
  'DOMAIN-SUFFIX,github.com,$target',
  'DOMAIN-SUFFIX,githubusercontent.com,$target',
  'DOMAIN-SUFFIX,githubassets.com,$target',
  'DOMAIN-SUFFIX,github.io,$target',

  // Google family. Keep this domain-based rather than forcing every
  // com.google.* Android process through the proxy.
  'DOMAIN-SUFFIX,google.com,$target',
  'DOMAIN-SUFFIX,googleapis.com,$target',
  'DOMAIN-SUFFIX,gstatic.com,$target',
  'DOMAIN-SUFFIX,googleusercontent.com,$target',
  'DOMAIN-SUFFIX,googlevideo.com,$target',
  'DOMAIN-SUFFIX,ytimg.com,$target',

  // Pixiv
  'PROCESS-NAME,jp.pxv.android,$target',
  'DOMAIN-SUFFIX,pixiv.net,$target',
  'DOMAIN-SUFFIX,pximg.net,$target',
];

List<String> _privateSiteRules(String target) => [
  // Video / adult sites currently used by the private Sigma build.
  'DOMAIN-SUFFIX,pornhub.com,$target',
  'DOMAIN-SUFFIX,phncdn.com,$target',
  'DOMAIN-SUFFIX,xvideos.com,$target',
  'DOMAIN-SUFFIX,xvideos-cdn.com,$target',
  'DOMAIN-SUFFIX,xv-cdn.com,$target',
  'DOMAIN-KEYWORD,missav,$target',
  'DOMAIN-SUFFIX,hanime1.me,$target',
  'DOMAIN-SUFFIX,cool18.com,$target',
  'DOMAIN-SUFFIX,theporndude.com,$target',

  // Novel / forum sites currently used by the private Sigma build.
  'DOMAIN-SUFFIX,twkan.com,$target',
  'DOMAIN-SUFFIX,69shuba.com,$target',
  'DOMAIN-SUFFIX,uukanshu.cc,$target',
  'DOMAIN-SUFFIX,uukan.org,$target',
  'DOMAIN-SUFFIX,quanben.io,$target',
  'DOMAIN-SUFFIX,diyibanzhu.me,$target',
  'DOMAIN-SUFFIX,diyibanzhu.quest,$target',
  'DOMAIN-SUFFIX,111bz.cc,$target',
  'DOMAIN-SUFFIX,8xsk.com,$target',
  'DOMAIN-SUFFIX,8xsk.org,$target',
  'DOMAIN-SUFFIX,bachashuku.org,$target',
  'DOMAIN-SUFFIX,hotupub.net,$target',
];

List<String> _asStringList(dynamic value) {
  if (value is! List) return <String>[];
  return value.map((item) => item.toString()).toList();
}

String? _simpleRuleTarget(String rule) {
  final parts = rule.split(',').map((item) => item.trim()).toList();
  if (parts.length < 2) return null;
  if (parts.first.toUpperCase() == 'MATCH') {
    return parts.length >= 2 ? parts[1] : null;
  }
  return parts.length >= 3 ? parts[2] : null;
}

List<String> _prependUnique(List<String> privateRules, List<String> existing) {
  final result = <String>[];
  final seen = <String>{};
  for (final rule in [...privateRules, ...existing]) {
    final normalized = rule.trim();
    if (normalized.isEmpty || !seen.add(normalized)) continue;
    result.add(normalized);
  }
  return result;
}
