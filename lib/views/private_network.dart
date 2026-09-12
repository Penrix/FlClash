import 'package:fl_clash/common/penrix_private.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PrivateNetworkView extends ConsumerStatefulWidget {
  const PrivateNetworkView({super.key});

  @override
  ConsumerState<PrivateNetworkView> createState() => _PrivateNetworkViewState();
}

class _PrivateNetworkViewState extends ConsumerState<PrivateNetworkView> {
  PenrixPrivateSettings? _settings;
  bool _applying = false;
  String? _applyError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await loadPenrixPrivateSettings();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _change(
    PenrixPrivateSettings Function(PenrixPrivateSettings current) update,
  ) async {
    final current = _settings;
    if (current == null || _applying) return;
    final next = update(current);
    setState(() {
      _settings = next;
      _applying = true;
      _applyError = null;
    });

    try {
      await savePenrixPrivateSettings(next);
      final applied = await ref
          .read(setupActionProvider.notifier)
          .applyProfile(force: true);
      if (applied) return;
      await _rollback(current);
    } catch (_) {
      await _rollback(current);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _rollback(PenrixPrivateSettings previous) async {
    var restored = false;
    try {
      await savePenrixPrivateSettings(previous);
      restored = await ref
          .read(setupActionProvider.notifier)
          .applyProfile(force: true);
    } catch (_) {
      restored = false;
    }
    if (!mounted) return;
    setState(() {
      _settings = previous;
      _applyError = restored
          ? '应用失败，已恢复原设置。'
          : '应用失败；原设置已恢复，但核心重新应用失败，请重新应用当前配置。';
    });
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _toggle({
    required String title,
    required String subtitle,
    required bool value,
    required PenrixPrivateSettings Function(
      PenrixPrivateSettings current,
      bool value,
    ) update,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: _applying
          ? null
          : (value) => _change((current) => update(current, value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const BaseScaffold(
        title: '私人网络',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return BaseScaffold(
      title: '私人网络',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_applyError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                _applyError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _section('关键工具'),
          _toggle(
            title: 'ChatGPT · 关键',
            subtitle: '强制 ChatGPT App、OpenAI 域名族和 WebSocket 使用当前代理',
            value: settings.chatGpt,
            update: (current, value) => current.copyWith(chatGpt: value),
          ),
          _section('应用增强'),
          _toggle(
            title: 'Twitter / X',
            subtitle: 'App、主站、图片与短链保持同一代理路径',
            value: settings.twitter,
            update: (current, value) => current.copyWith(twitter: value),
          ),
          _toggle(
            title: 'Telegram',
            subtitle: 'App 与常用 Telegram 域名强制使用当前代理',
            value: settings.telegram,
            update: (current, value) => current.copyWith(telegram: value),
          ),
          _toggle(
            title: 'GitHub',
            subtitle: 'GitHub App、API、静态资源和 usercontent 保持代理',
            value: settings.github,
            update: (current, value) => current.copyWith(github: value),
          ),
          _toggle(
            title: 'Google',
            subtitle: 'Google、API、静态资源与视频域名保持代理',
            value: settings.google,
            update: (current, value) => current.copyWith(google: value),
          ),
          _toggle(
            title: 'Pixiv',
            subtitle: 'Pixiv App、主站与图片 CDN 保持代理',
            value: settings.pixiv,
            update: (current, value) => current.copyWith(pixiv: value),
          ),
          _section('特殊路由'),
          _toggle(
            title: 'UAA · 直连优先',
            subtitle: 'UAA 自有域名强制 DIRECT，避免住宅代理触发登录异常',
            value: settings.uaaDirect,
            update: (current, value) => current.copyWith(uaaDirect: value),
          ),
          _toggle(
            title: '私人站点增强',
            subtitle: '小说站与常用视频站固定使用当前代理，减少规则漏分流',
            value: settings.privateSites,
            update: (current, value) => current.copyWith(privateSites: value),
          ),
          _section('隐私与过滤'),
          _toggle(
            title: '广告与追踪拦截',
            subtitle: '使用 Mihomo MRS 规则在全设备网络层 REJECT 广告与追踪域名',
            value: settings.adblock,
            update: (current, value) => current.copyWith(adblock: value),
          ),
          if (_applying)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
