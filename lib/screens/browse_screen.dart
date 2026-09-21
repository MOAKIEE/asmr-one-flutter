import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/common.dart';
import '../core/models/work.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/settings_state.dart';
import '../state/work_feed.dart';
import '../widgets/work_grid.dart';
import 'filter_sheet.dart';
import 'tag_browse_screen.dart';

/// 浏览页：排序 + 多条件筛选 + 网格 / 列表浏览。
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final BrowseController _controller;
  bool _listMode = false;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _controller = BrowseController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    // 首次进入时按「是否包含 18 禁」设置初始化筛选条件。
    final settings = context.read<SettingsState>();
    _controller
        .update(
          const WorkQuery().copyWith(
            nsfw: settings.showNsfw ? null : false,
            clearNsfw: settings.showNsfw,
          ),
        )
        .ignore();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  AppLang get _lang {
    switch (Localizations.localeOf(context).languageCode) {
      case 'ja':
        return AppLang.ja;
      case 'en':
        return AppLang.en;
      default:
        return AppLang.zh;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();
    final auth = context.watch<AuthState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l('browse.title')),
        actions: [
          IconButton(
            tooltip: _listMode ? l('browse.gridView') : l('browse.listView'),
            onPressed: () => setState(() => _listMode = !_listMode),
            icon: Icon(
              _listMode ? Icons.grid_view_rounded : Icons.view_list_rounded,
            ),
          ),
          IconButton(
            tooltip: l('tag.browse'),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TagBrowseScreen())),
            icon: const Icon(Icons.sell_outlined),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final count = _controller.query.filterCount;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    tooltip: l('browse.filter'),
                    onPressed: _openFilter,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6,
                      top: 8,
                      child: _CountDot(count: count),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final q = _controller.query;
          final labels = <int, String>{
            for (final id in q.tags) id: auth.tagLabel(id, _lang),
          };
          return WorkFeedView(
            feed: _controller.works,
            columns: settings.gridColumns,
            listMode: _listMode,
            leadingSlivers: [
              SliverToBoxAdapter(
                child: ActiveFilterBar(
                  query: q,
                  tagLabels: labels,
                  onRemoveTag: (id) => _controller.update(
                    q.copyWith(tags: [...q.tags]..remove(id)),
                  ),
                  onClear: () => _controller.clearFilters(),
                  onAdjustRate: () =>
                      _controller.update(q.copyWith(clearRate: true)),
                  onClearDuration: () =>
                      _controller.update(q.copyWith(clearDuration: true)),
                ),
              ),
              SliverToBoxAdapter(
                child: _SortRow(
                  order: q.order,
                  sort: q.sort,
                  totalCount: _controller.works.totalCount,
                  onOrder: (o) => _controller.setOrder(o, q.sort),
                  onToggleSort: () => _controller.setOrder(
                    q.order,
                    q.sort == SortDirection.desc
                        ? SortDirection.asc
                        : SortDirection.desc,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openFilter() async {
    final result = await showWorkFilterSheet(context, query: _controller.query);
    if (result == null) return;
    await _controller.update(result);
  }
}

class _CountDot extends StatelessWidget {
  const _CountDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.order,
    required this.sort,
    required this.totalCount,
    required this.onOrder,
    required this.onToggleSort,
  });

  final WorkOrder order;
  final SortDirection sort;
  final int totalCount;
  final ValueChanged<WorkOrder> onOrder;
  final VoidCallback onToggleSort;

  static const _options = [
    WorkOrder.createDate,
    WorkOrder.dlCount,
    WorkOrder.rateAverage,
    WorkOrder.reviewCount,
    WorkOrder.release,
    WorkOrder.price,
  ];

  String _label(L10n l, WorkOrder o) => switch (o) {
    WorkOrder.createDate => l('order.createDate'),
    WorkOrder.release => l('order.release'),
    WorkOrder.dlCount => l('order.dlCount'),
    WorkOrder.rateAverage => l('order.rateAverage'),
    WorkOrder.reviewCount => l('order.reviewCount'),
    WorkOrder.price => l('order.price'),
    WorkOrder.id => l('order.id'),
    WorkOrder.random => l('order.random'),
    WorkOrder.betterRandom => l('order.betterRandom'),
  };

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _options.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final o = _options[i];
              return Center(
                child: ChoiceChip(
                  label: Text(_label(l, o)),
                  selected: o == order,
                  onSelected: (_) => onOrder(o),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 10, 0),
          child: Row(
            children: [
              Text(
                totalCount > 0
                    ? l('browse.resultCount', {'n': totalCount})
                    : '',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onToggleSort,
                icon: Icon(
                  sort == SortDirection.desc
                      ? Icons.south_rounded
                      : Icons.north_rounded,
                  size: 15,
                ),
                label: Text(
                  sort == SortDirection.desc ? l('sort.desc') : l('sort.asc'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
