import 'package:defer_pointer/defer_pointer.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widget_registry.dart';
import 'widgets/core_status_button.dart';
import 'widgets/start_button.dart';

typedef _IsEditWidgetBuilder = Widget Function(bool isEdit);

const _compactCrossAxisCount = 8;
const _mediumCrossAxisCount = 12;
const _maxCrossAxisCount = 16;
const _mediumGridBreakpoint = 480.0;
const _maxGridBreakpoint = 840.0;
const _maxGridWidth = 280.0 * _maxCrossAxisCount / 4;

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  final key = GlobalKey<SuperGridState>();
  final _isEditNotifier = ValueNotifier<bool>(false);
  final _addedWidgetsNotifier = ValueNotifier<List<GridItem>>([]);

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      dashboardStateProvider.select((state) => state.dashboardWidgets),
      (_, dashboardWidgets) => _syncAddedWidgets(dashboardWidgets),
      fireImmediately: true,
    );
  }

  void _syncAddedWidgets(List<DashboardWidget> dashboardWidgets) {
    bool onThisPlatform(DashboardWidget item) =>
        item.platforms.contains(SupportPlatform.currentPlatform);
    final shown = dashboardWidgets
        .where(onThisPlatform)
        .map((item) => item.widget)
        .toSet();
    _addedWidgetsNotifier.value = DashboardWidget.values
        .where((item) => onThisPlatform(item) && !shown.contains(item.widget))
        .map((item) => item.widget)
        .toList();
  }

  @override
  void dispose() {
    _isEditNotifier.dispose();
    _addedWidgetsNotifier.dispose();
    super.dispose();
  }

  Widget _buildIsEdit(_IsEditWidgetBuilder builder) {
    return ValueListenableBuilder(
      valueListenable: _isEditNotifier,
      builder: (_, isEdit, _) {
        return builder(isEdit);
      },
    );
  }

  List<Widget> _buildActions(bool isEdit) {
    return [
      if (!isEdit && coreLib == null) const CoreStatusButton(),
      if (isEdit)
        ValueListenableBuilder(
          valueListenable: _addedWidgetsNotifier,
          builder: (_, addedChildren, child) {
            if (addedChildren.isEmpty) {
              return Container();
            }
            return child!;
          },
          child: IconButton(
            tooltip: context.appLocalizations.addWidget,
            onPressed: () {
              _showAddWidgetsModal();
            },
            icon: const Icon(Icons.add_circle),
          ),
        ),
      FadeRotationScaleBox(
        child: isEdit
            ? IconButton(
                tooltip: context.appLocalizations.save,
                key: const ValueKey(true),
                icon: const Icon(Icons.save, key: ValueKey('save-icon')),
                onPressed: _handleSaveAndExit,
              )
            : IconButton(
                tooltip: context.appLocalizations.edit,
                key: const ValueKey(false),
                icon: const Icon(Icons.edit, key: ValueKey('edit-icon')),
                onPressed: _handleEnterEdit,
              ),
      ),
    ];
  }

  void _showAddWidgetsModal() {
    showSheet(
      builder: (_) {
        return ValueListenableBuilder(
          valueListenable: _addedWidgetsNotifier,
          builder: (_, value, _) {
            return AdaptiveSheetScaffold(
              body: _AddDashboardWidgetModal(
                items: value,
                onAdd: (gridItem) {
                  key.currentState?.handleAdd(gridItem);
                },
              ),
              title: context.appLocalizations.add,
            );
          },
        );
      },
      context: context,
    );
  }

  void _handleEnterEdit() {
    if (_isEditNotifier.value) {
      return;
    }
    _isEditNotifier.value = true;
  }

  void _handleExitEdit() {
    if (!_isEditNotifier.value) {
      return;
    }
    final dashboardWidgets = _getDashboardWidgets(key.currentState);
    if (dashboardWidgets != null) {
      _saveDashboardWidgets(dashboardWidgets);
    }
    _isEditNotifier.value = false;
  }

  Future<void> _handleSaveAndExit() async {
    if (!_isEditNotifier.value) {
      return;
    }
    await _handleSave();
    if (mounted) {
      _isEditNotifier.value = false;
    }
  }

  Future<void> _handleSave() async {
    final currentState = key.currentState;
    if (currentState == null) {
      return;
    }
    if (!mounted || currentState.snapshotChildren.isEmpty) {
      return;
    }
    final transformCompleted = await currentState.isTransformCompleter;
    if (!transformCompleted ||
        !mounted ||
        !currentState.mounted ||
        !identical(key.currentState, currentState)) {
      return;
    }
    final dashboardWidgets = _getDashboardWidgets(currentState);
    if (dashboardWidgets == null) {
      return;
    }
    _saveDashboardWidgets(dashboardWidgets);
  }

  List<DashboardWidget>? _getDashboardWidgets(SuperGridState? currentState) {
    if (currentState == null) {
      return null;
    }
    final children = currentState.snapshotChildren;
    if (children.isEmpty) {
      return null;
    }
    return children.map(dashboardWidgetOf).toList();
  }

  void _saveDashboardWidgets(List<DashboardWidget> dashboardWidgets) {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(dashboardWidgets: dashboardWidgets));
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardStateProvider);
    final spacing = 14.mAp;
    final children = [
      ...dashboardState.dashboardWidgets
          .where(
            (item) => item.platforms.contains(SupportPlatform.currentPlatform),
          )
          .map((item) => item.widget),
    ];
    return _buildIsEdit(
      (isEdit) => CommonScaffold(
        title: '网络服务大厅',
        actions: _buildActions(isEdit),
        floatingActionButton: isEdit ? const StartButton() : null,
        body: Align(
          alignment: Alignment.topCenter,
          child: Builder(
            builder: (context) => SingleChildScrollView(
              padding: const EdgeInsets.all(
                16,
              ).copyWith(bottom: 16 + BottomInsetScope.of(context)),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxGridWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isEdit) ...[
                        const _PrivateServiceHero(),
                        SizedBox(height: spacing),
                      ],
                      LayoutBuilder(
                        builder: (_, constraints) {
                          final columns = switch (constraints.maxWidth) {
                            < _mediumGridBreakpoint => _compactCrossAxisCount,
                            <= _maxGridBreakpoint => _mediumCrossAxisCount,
                            _ => _maxCrossAxisCount,
                          };
                          return isEdit
                              ? BackLayerScope(
                                  onBack: _handleExitEdit,
                                  child: SuperGrid(
                                    key: key,
                                    crossAxisCount: columns,
                                    crossAxisSpacing: spacing,
                                    mainAxisSpacing: spacing,
                                    children: children,
                                    onUpdate: () {
                                      _handleSave();
                                    },
                                  ),
                                )
                              : Grid(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: spacing,
                                  mainAxisSpacing: spacing,
                                  children: children,
                                );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddDashboardWidgetModal extends StatelessWidget {
  final List<GridItem> items;
  final Function(GridItem item) onAdd;

  const _AddDashboardWidgetModal({required this.items, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return DeferredPointerHandler(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Grid(
          crossAxisCount: 8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: items
              .map(
                (item) => item.wrap(
                  builder: (child) {
                    return _AddedContainer(
                      onAdd: () {
                        onAdd(item);
                      },
                      child: child,
                    );
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _AddedContainer extends StatefulWidget {
  final Widget child;
  final VoidCallback onAdd;

  const _AddedContainer({required this.child, required this.onAdd});

  @override
  State<_AddedContainer> createState() => _AddedContainerState();
}

class _AddedContainerState extends State<_AddedContainer> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(_AddedContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {}
  }

  Future<void> _handleAdd() async {
    widget.onAdd();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ActivateBox(child: widget.child),
        Positioned(
          top: -8,
          right: -8,
          child: DeferPointer(
            child: SizedBox(
              width: 24,
              height: 24,
              child: IconButton.filled(
                tooltip: context.appLocalizations.add,
                iconSize: 20,
                padding: const EdgeInsets.all(2),
                onPressed: _handleAdd,
                icon: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


class _PrivateServiceHero extends ConsumerWidget {
  const _PrivateServiceHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStart = ref.watch(isStartProvider);
    final runTime = ref.watch(runTimeProvider);
    final suspend = ref.watch(suspendProvider);
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    final colors = context.colorScheme;
    final statusText = suspend
        ? '专线休眠'
        : isStart
        ? '安全专线已连接'
        : '专线待命';
    final detailText = !hasProfile
        ? '请先导入配置文件'
        : isStart
        ? '网络服务正在运行 · 稳定优先'
        : '点击右侧开关启动网络服务';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final banner = Container(
          padding: EdgeInsets.all(isWide ? 28 : 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFD9282F),
                Color(0xFFB5121B),
                Color(0xFF8F0710),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF9C1118).withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD35A),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.7),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Color(0xFFB5121B),
                      size: 31,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '政务网络服务',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '私人实验网络 · 稳定连接未来',
                          style: TextStyle(
                            color: Color(0xFFFFE6B5),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Text(
                      '民间测试版',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isStart
                            ? const Color(0xFFFFE3DF)
                            : const Color(0xFFF3F0ED),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isStart
                            ? Icons.verified_user_rounded
                            : Icons.power_settings_new_rounded,
                        color: isStart
                            ? const Color(0xFFC2171D)
                            : const Color(0xFF7A716B),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusText,
                            style: const TextStyle(
                              color: Color(0xFF281B18),
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detailText,
                            style: const TextStyle(
                              color: Color(0xFF7B6C66),
                              fontSize: 12,
                            ),
                          ),
                          if (isStart && runTime != null) ...[
                            const SizedBox(height: 5),
                            DefaultTextStyle(
                              style: const TextStyle(
                                color: Color(0xFFC2171D),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              child: RunTimeText(timeStamp: runTime),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Switch(
                      value: isStart,
                      onChanged: hasProfile
                          ? (_) {
                              ref
                                  .read(commonActionProvider.notifier)
                                  .toggleRunning();
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const _PrivateSloganStrip(),
            ],
          ),
        );

        if (!isWide) {
          return banner;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: banner),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.14),
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.public_rounded,
                      size: 52,
                      color: Color(0xFFC2171D),
                    ),
                    SizedBox(height: 14),
                    Text(
                      '数字网络服务中心',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '连接可靠 · 状态透明 · 配置自主',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF806F68),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PrivateSloganStrip extends StatelessWidget {
  const _PrivateSloganStrip();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PrivateSloganDot(label: '私人实验'),
        _PrivateSloganDivider(),
        _PrivateSloganDot(label: '稳定优先'),
        _PrivateSloganDivider(),
        _PrivateSloganDot(label: '网络常青'),
      ],
    );
  }
}

class _PrivateSloganDot extends StatelessWidget {
  final String label;

  const _PrivateSloganDot({required this.label});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PrivateSloganDivider extends StatelessWidget {
  const _PrivateSloganDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Container(
        width: 4,
        height: 4,
        decoration: const BoxDecoration(
          color: Color(0xFFFFD35A),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
