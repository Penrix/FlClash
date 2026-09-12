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

Map<String, dynamic> buildPenrixPrivateNetworkConfig(
  Map<String, dynamic> source, {
  List<String>? routingRules,
}) {
  final config = Map<String, dynamic>.from(source);
  final existingRules = _asStringList(config['rules']);
  final targetRules = routingRules?.isNotEmpty == true
      ? routingRules!
      : existingRules;
  final proxyTarget = inferPenrixProxyTarget(config, targetRules);

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
  config['rules'] = mergePenrixPrivateRules(
    config,
    existingRules,
    routingRules: targetRules,
  );
  return config;
}

List<String> mergePenrixPrivateRules(
  Map<String, dynamic> config,
  List<String> existingRules, {
  List<String>? routingRules,
}) {
  final targetRules = routingRules?.isNotEmpty == true
      ? routingRules!
      : existingRules;
  final proxyTarget = inferPenrixProxyTarget(config, targetRules);
  return _prependUnique(
    _privateRulePrefix(proxyTarget),
    existingRules,
  );
}

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

List<String> _privateRulePrefix(String? proxyTarget) => [
  if (proxyTarget != null) ..._chatGptCriticalRules(proxyTarget),
  'DOMAIN-SUFFIX,uaa.com,DIRECT',
  'DOMAIN-SUFFIX,uaa002.com,DIRECT',
  'RULE-SET,$penrixAdblockProviderName,REJECT',
  if (proxyTarget != null) ..._commonAppRules(proxyTarget),
  if (proxyTarget != null) ..._privateSiteRules(proxyTarget),
];

List<String> _chatGptCriticalRules(String target) => [
  'PROCESS-NAME,com.openai.chatgpt,$target',
  'DOMAIN,ws.chatgpt.com,$target',
  'DOMAIN-SUFFIX,chatgpt.com,$target',
  'DOMAIN-SUFFIX,openai.com,$target',
  'DOMAIN-SUFFIX,oaistatic.com,$target',
  'DOMAIN-SUFFIX,oaiusercontent.com,$target',
  'DOMAIN-SUFFIX,oaistatsig.com,$target',
];

List<String> _commonAppRules(String target) => [
  'PROCESS-NAME,com.twitter.android,$target',
  'DOMAIN-SUFFIX,x.com,$target',
  'DOMAIN-SUFFIX,twitter.com,$target',
  'DOMAIN-SUFFIX,twimg.com,$target',
  'DOMAIN-SUFFIX,t.co,$target',
  'PROCESS-NAME,org.telegram.messenger,$target',
  'PROCESS-NAME,org.telegram.messenger.web,$target',
  'DOMAIN-SUFFIX,telegram.org,$target',
  'DOMAIN-SUFFIX,t.me,$target',
  'DOMAIN-SUFFIX,telegra.ph,$target',
  'PROCESS-NAME,com.github.android,$target',
  'DOMAIN-SUFFIX,github.com,$target',
  'DOMAIN-SUFFIX,githubusercontent.com,$target',
  'DOMAIN-SUFFIX,githubassets.com,$target',
  'DOMAIN-SUFFIX,github.io,$target',
  'DOMAIN-SUFFIX,google.com,$target',
  'DOMAIN-SUFFIX,googleapis.com,$target',
  'DOMAIN-SUFFIX,gstatic.com,$target',
  'DOMAIN-SUFFIX,googleusercontent.com,$target',
  'DOMAIN-SUFFIX,googlevideo.com,$target',
  'DOMAIN-SUFFIX,ytimg.com,$target',
  'PROCESS-NAME,jp.pxv.android,$target',
  'DOMAIN-SUFFIX,pixiv.net,$target',
  'DOMAIN-SUFFIX,pximg.net,$target',
];

List<String> _privateSiteRules(String target) => [
  'DOMAIN-SUFFIX,pornhub.com,$target',
  'DOMAIN-SUFFIX,phncdn.com,$target',
  'DOMAIN-SUFFIX,xvideos.com,$target',
  'DOMAIN-SUFFIX,xvideos-cdn.com,$target',
  'DOMAIN-SUFFIX,xv-cdn.com,$target',
  'DOMAIN-KEYWORD,missav,$target',
  'DOMAIN-SUFFIX,hanime1.me,$target',
  'DOMAIN-SUFFIX,cool18.com,$target',
  'DOMAIN-SUFFIX,theporndude.com,$target',
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
