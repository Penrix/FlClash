import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String penrixAdblockProviderName = 'penrix-adblock';
const String penrixChatGptGroupName = '💬 Penrix ChatGPT 稳定通道';
const String penrixAdblockProviderUrl =
    'https://raw.githubusercontent.com/217heidai/adblockfilters/main/rules/adblockmihomo.mrs';
const int penrixAdblockUpdateInterval = 28800;
const String penrixPrivateSettingsKey = 'penrix.private.network.settings.v1';

const Set<String> _reservedTargets = {
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
};

const List<String> _chatGptTargetMarkers = [
  'openai',
  'chatgpt',
  'oaistatic',
  'oaiusercontent',
  'oaistatsig',
];

const List<String> _preferredProxyTargetNames = [
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

class PenrixPrivateSettings {
  final bool chatGpt;
  final bool twitter;
  final bool telegram;
  final bool github;
  final bool google;
  final bool pixiv;
  final bool uaaDirect;
  final bool privateSites;
  final bool adblock;

  const PenrixPrivateSettings({
    this.chatGpt = true,
    this.twitter = true,
    this.telegram = true,
    this.github = true,
    this.google = true,
    this.pixiv = true,
    this.uaaDirect = true,
    this.privateSites = true,
    this.adblock = true,
  });

  factory PenrixPrivateSettings.fromJson(Map<String, dynamic> json) {
    bool read(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    return PenrixPrivateSettings(
      chatGpt: read('chatGpt', true),
      twitter: read('twitter', true),
      telegram: read('telegram', true),
      github: read('github', true),
      google: read('google', true),
      pixiv: read('pixiv', true),
      uaaDirect: read('uaaDirect', true),
      privateSites: read('privateSites', true),
      adblock: read('adblock', true),
    );
  }

  Map<String, bool> toJson() => {
    'chatGpt': chatGpt,
    'twitter': twitter,
    'telegram': telegram,
    'github': github,
    'google': google,
    'pixiv': pixiv,
    'uaaDirect': uaaDirect,
    'privateSites': privateSites,
    'adblock': adblock,
  };

  PenrixPrivateSettings copyWith({
    bool? chatGpt,
    bool? twitter,
    bool? telegram,
    bool? github,
    bool? google,
    bool? pixiv,
    bool? uaaDirect,
    bool? privateSites,
    bool? adblock,
  }) {
    return PenrixPrivateSettings(
      chatGpt: chatGpt ?? this.chatGpt,
      twitter: twitter ?? this.twitter,
      telegram: telegram ?? this.telegram,
      github: github ?? this.github,
      google: google ?? this.google,
      pixiv: pixiv ?? this.pixiv,
      uaaDirect: uaaDirect ?? this.uaaDirect,
      privateSites: privateSites ?? this.privateSites,
      adblock: adblock ?? this.adblock,
    );
  }
}

Future<PenrixPrivateSettings> loadPenrixPrivateSettings() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(penrixPrivateSettingsKey);
    if (raw == null || raw.isEmpty) return const PenrixPrivateSettings();
    final decoded = json.decode(raw);
    if (decoded is! Map) return const PenrixPrivateSettings();
    return PenrixPrivateSettings.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  } catch (_) {
    return const PenrixPrivateSettings();
  }
}

Future<void> savePenrixPrivateSettings(PenrixPrivateSettings settings) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    penrixPrivateSettingsKey,
    json.encode(settings.toJson()),
  );
}

Map<String, dynamic> buildPenrixPrivateNetworkConfig(
  Map<String, dynamic> source, {
  List<String>? routingRules,
  PenrixPrivateSettings settings = const PenrixPrivateSettings(),
  bool prependPrivateRules = true,
}) {
  final config = Map<String, dynamic>.from(source);
  final existingRules = _asStringList(config['rules']);
  final targetRules = routingRules?.isNotEmpty == true
      ? routingRules!
      : existingRules;
  final proxyTarget = inferPenrixProxyTarget(config, targetRules);
  _updateChatGptGroup(config, proxyTarget, enabled: settings.chatGpt);
  final providerProxyTarget = inferPenrixProviderDownloadTarget(
    config,
    proxyTarget,
  );

  final ruleProviders = <String, dynamic>{};
  final existingProviders = config['rule-providers'];
  if (existingProviders is Map) {
    for (final entry in existingProviders.entries) {
      ruleProviders[entry.key.toString()] = entry.value;
    }
  }
  if (settings.adblock) {
    ruleProviders[penrixAdblockProviderName] = <String, dynamic>{
      'type': 'http',
      'behavior': 'domain',
      'format': 'mrs',
      'url': penrixAdblockProviderUrl,
      'interval': penrixAdblockUpdateInterval,
      if (providerProxyTarget != null) 'proxy': providerProxyTarget,
    };
  } else {
    ruleProviders.remove(penrixAdblockProviderName);
  }
  config['rule-providers'] = ruleProviders;
  config['rules'] = prependPrivateRules
      ? mergePenrixPrivateRules(
          config,
          existingRules,
          routingRules: targetRules,
          settings: settings,
        )
      : existingRules;
  return config;
}

List<String> mergePenrixPrivateRules(
  Map<String, dynamic> config,
  List<String> existingRules, {
  List<String>? routingRules,
  PenrixPrivateSettings settings = const PenrixPrivateSettings(),
}) {
  final targetRules = routingRules?.isNotEmpty == true
      ? routingRules!
      : existingRules;
  return _prependUnique(
    buildPenrixPrivateRulePrefix(config, targetRules, settings: settings),
    existingRules,
  );
}

List<String> buildPenrixPrivateRulePrefix(
  Map<String, dynamic> config,
  List<String> routingRules, {
  PenrixPrivateSettings settings = const PenrixPrivateSettings(),
}) {
  final proxyTarget = inferPenrixProxyTarget(config, routingRules);
  final hasChatGptGroup =
      config['proxy-groups'] is List &&
      (config['proxy-groups'] as List).whereType<Map>().any(
        (group) => group['name'] == penrixChatGptGroupName,
      );
  return _privateRulePrefix(
    proxyTarget,
    settings,
    chatGptTarget: hasChatGptGroup ? penrixChatGptGroupName : proxyTarget,
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
    return value != penrixChatGptGroupName && availableTargets.contains(value);
  }

  for (final rawRule in rules) {
    final lower = rawRule.toLowerCase();
    if (!_chatGptTargetMarkers.any(lower.contains)) continue;
    final target = _simpleRuleTarget(rawRule);
    if (usable(target)) return target!.trim();
  }

  for (final preferred in _preferredProxyTargetNames) {
    if (availableTargets.contains(preferred)) return preferred;
  }

  for (final rawRule in rules.reversed) {
    final parts = rawRule.split(',').map((item) => item.trim()).toList();
    if (parts.isEmpty || parts.first.toUpperCase() != 'MATCH') continue;
    final target = _simpleRuleTarget(rawRule);
    if (usable(target)) return target!.trim();
  }

  for (final name in selectorGroupNames) {
    if (name != penrixChatGptGroupName) return name;
  }
  for (final name in groupNames) {
    if (name != penrixChatGptGroupName) return name;
  }
  if (proxyNames.isNotEmpty) return proxyNames.first;
  return null;
}

String? inferPenrixProviderDownloadTarget(
  Map<String, dynamic> config,
  String? routeTarget,
) {
  final proxyNames = <String>{};
  final rawProxies = config['proxies'];
  if (rawProxies is List) {
    for (final item in rawProxies) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim();
      if (name != null && name.isNotEmpty) proxyNames.add(name);
    }
  }

  final selectorNames = <String>[];
  final groupTypes = <String, String>{};
  final rawGroups = config['proxy-groups'];
  if (rawGroups is List) {
    for (final item in rawGroups) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim();
      if (name == null || name.isEmpty) continue;
      final type = item['type']?.toString().toLowerCase() ?? '';
      groupTypes[name] = type;
      if (type == 'select' || type == 'selector') {
        selectorNames.add(name);
      }
    }
  }

  final target = routeTarget?.trim();
  if (target != null && target.isNotEmpty) {
    if (proxyNames.contains(target)) return target;
    final type = groupTypes[target];
    if (type == 'select' || type == 'selector') return target;
  }

  for (final preferred in _preferredProxyTargetNames) {
    if (selectorNames.contains(preferred)) return preferred;
  }
  if (selectorNames.isNotEmpty) return selectorNames.first;
  return null;
}

List<String> _privateRulePrefix(
  String? proxyTarget,
  PenrixPrivateSettings settings, {
  required String? chatGptTarget,
}) => [
  if (settings.chatGpt && chatGptTarget != null)
    ..._chatGptCriticalRules(chatGptTarget),
  if (settings.uaaDirect) ...[
    'DOMAIN-SUFFIX,uaa.com,DIRECT',
    'DOMAIN-SUFFIX,uaa002.com,DIRECT',
  ],
  if (settings.twitter && proxyTarget != null) ..._twitterRules(proxyTarget),
  if (settings.telegram && proxyTarget != null) ..._telegramRules(proxyTarget),
  if (settings.github && proxyTarget != null) ..._githubRules(proxyTarget),
  if (settings.google && proxyTarget != null) ..._googleRules(proxyTarget),
  if (settings.pixiv && proxyTarget != null) ..._pixivRules(proxyTarget),
  if (settings.adblock) 'RULE-SET,$penrixAdblockProviderName,REJECT',
  if (settings.privateSites && proxyTarget != null)
    ..._privateSiteRules(proxyTarget),
];

List<String> _chatGptCriticalRules(String target) => [
  'PROCESS-NAME,com.openai.chatgpt,$target',
  'PROCESS-NAME,ChatGPT.exe,$target',
  'PROCESS-NAME,ChatGPT,$target',
  'PROCESS-NAME,codex.exe,$target',
  'DOMAIN,ws.chatgpt.com,$target',
  'DOMAIN-SUFFIX,chatgpt.com,$target',
  'DOMAIN-SUFFIX,chatgpt.site,$target',
  'DOMAIN-SUFFIX,chatgpt-team.site,$target',
  'DOMAIN-SUFFIX,openai.com,$target',
  'DOMAIN-SUFFIX,oaistatic.com,$target',
  'DOMAIN-SUFFIX,oaiusercontent.com,$target',
  'DOMAIN-SUFFIX,oaistatsig.com,$target',
  'DOMAIN-SUFFIX,ct.sendgrid.net,$target',
  'DOMAIN-SUFFIX,intercom.io,$target',
  'DOMAIN-SUFFIX,intercomcdn.com,$target',
  'DOMAIN,cdn.openaimerge.com,$target',
  'DOMAIN,cdn.workos.com,$target',
  'DOMAIN,challenges.cloudflare.com,$target',
  'DOMAIN,forwarder.workos.com,$target',
  'DOMAIN,humb.apple.com,$target',
  'DOMAIN,images.workoscdn.com,$target',
  'DOMAIN,js.stripe.com,$target',
  'DOMAIN,o207216.ingest.sentry.io,$target',
  'DOMAIN,o33249.ingest.sentry.io,$target',
  'DOMAIN,rum.browser-intake-datadoghq.com,$target',
  'DOMAIN,setup.workos.com,$target',
  'DOMAIN,workos.imgix.net,$target',
];

List<String> _twitterRules(String target) => [
  'PROCESS-NAME,com.twitter.android,$target',
  'DOMAIN-SUFFIX,x.com,$target',
  'DOMAIN-SUFFIX,twitter.com,$target',
  'DOMAIN-SUFFIX,twimg.com,$target',
  'DOMAIN-SUFFIX,t.co,$target',
];

List<String> _telegramRules(String target) => [
  'PROCESS-NAME,org.telegram.messenger,$target',
  'PROCESS-NAME,org.telegram.messenger.web,$target',
  'DOMAIN-SUFFIX,telegram.org,$target',
  'DOMAIN-SUFFIX,t.me,$target',
  'DOMAIN-SUFFIX,telegra.ph,$target',
];

List<String> _githubRules(String target) => [
  'PROCESS-NAME,com.github.android,$target',
  'DOMAIN-SUFFIX,github.com,$target',
  'DOMAIN-SUFFIX,githubusercontent.com,$target',
  'DOMAIN-SUFFIX,githubassets.com,$target',
  'DOMAIN-SUFFIX,github.io,$target',
];

List<String> _googleRules(String target) => [
  'DOMAIN-SUFFIX,google.com,$target',
  'DOMAIN-SUFFIX,googleapis.com,$target',
  'DOMAIN-SUFFIX,gstatic.com,$target',
  'DOMAIN-SUFFIX,googleusercontent.com,$target',
  'DOMAIN-SUFFIX,googlevideo.com,$target',
  'DOMAIN-SUFFIX,ytimg.com,$target',
];

List<String> _pixivRules(String target) => [
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
  'DOMAIN-SUFFIX,viralporn.com,$target',
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

void _updateChatGptGroup(
  Map<String, dynamic> config,
  String? proxyTarget, {
  required bool enabled,
}) {
  final sourceGroups = config['proxy-groups'];
  final groups = sourceGroups is List
      ? sourceGroups
            .whereType<Map>()
            .map((group) => Map<String, dynamic>.from(group))
            .where((group) => group['name'] != penrixChatGptGroupName)
            .toList()
      : <Map<String, dynamic>>[];
  if (!enabled || proxyTarget == null) {
    config['proxy-groups'] = groups;
    return;
  }

  final members = <String>[];
  final seen = <String>{};
  void addMember(dynamic value) {
    final name = value?.toString().trim();
    if (name == null ||
        name.isEmpty ||
        name == penrixChatGptGroupName ||
        _reservedTargets.contains(name.toUpperCase()) ||
        !seen.add(name)) {
      return;
    }
    members.add(name);
  }

  addMember(proxyTarget);
  for (final group in groups) {
    if (group['name'] != proxyTarget || group['proxies'] is! List) continue;
    for (final member in group['proxies'] as List) {
      addMember(member);
    }
  }
  final sourceProxies = config['proxies'];
  if (sourceProxies is List) {
    for (final proxy in sourceProxies.whereType<Map>()) {
      addMember(proxy['name']);
    }
  }

  config['proxy-groups'] = [
    <String, dynamic>{
      'name': penrixChatGptGroupName,
      'type': 'select',
      'proxies': members,
      'default-selected': proxyTarget,
    },
    ...groups,
  ];
}

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
