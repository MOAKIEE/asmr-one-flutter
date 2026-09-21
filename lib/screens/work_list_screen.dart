import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/models/work.dart';
import '../l10n/app_localizations.dart';
import '../state/settings_state.dart';
import '../state/work_feed.dart';
import '../widgets/work_grid.dart';

/// 固定查询条件的作品列表页（「查看全部」、标签 / 社团 / 声优筛选结果）。
class WorkListScreen extends StatefulWidget {
  const WorkListScreen({
    super.key,
    required this.title,
    this.query = const WorkQuery(),
    this.showOrderBar = true,
  });

  final String title;
  final WorkQuery query;
  final bool showOrderBar;

  @override
  State<WorkListScreen> createState() => _WorkListScreenState();
}

class _WorkListScreenState extends State<WorkListScreen> {
  late WorkQuery _query;
  late WorkFeed _feed;
  bool _listMode = false;

  @override
  void initState() {
    super.initState();
    _query = widget.query;
    _buildFeed();
  }

  void _buildFeed() {
    _feed = WorkFeed(
      (page, pageSize) => ApiClient.instance.fetchWorks(
        _query.copyWith(page: page, pageSize: pageSize),
      ),
      pageSize: 24,
      label: 'list:${widget.title}',
    );
    _feed.load();
  }

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  Future<void> _changeOrder(WorkOrder order, SortDirection sort) async {
    _query = _query.copyWith(order: order, sort: sort);
    setState(_buildFeed);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _listMode ? l('browse.gridView') : l('browse.listView'),
            icon: Icon(
              _listMode ? Icons.grid_view_rounded : Icons.view_list_rounded,
            ),
            onPressed: () => setState(() => _listMode = !_listMode),
          ),
        ],
      ),
      body: WorkFeedView(
        feed: _feed,
        columns: settings.gridColumns,
        listMode: _listMode,
        leadingSlivers: [
          if (widget.showOrderBar)
            SliverToBoxAdapter(
              child: _OrderBar(
                order: _query.order,
                sort: _query.sort,
                totalCount: _feed.totalCount,
                onChanged: _changeOrder,
              ),
            ),
        ],
      ),
    );
  }
}

/// 排序切换条：一行可横向滚动的排序按钮。
class _OrderBar extends StatelessWidget {
  const _OrderBar({
    required this.order,
    required this.sort,
    required this.totalCount,
    required this.onChanged,
  });

  final WorkOrder order;
  final SortDirection sort;
  final int totalCount;
  final Future<void> Function(WorkOrder order, SortDirection sort) onChanged;

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
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: _options.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final o = _options[i];
              final selected = o == order;
              return Center(
                child: ChoiceChip(
                  label: Text(_label(l, o)),
                  selected: selected,
                  onSelected: (_) => onChanged(
                    o,
                    selected && sort == SortDirection.desc
                        ? SortDirection.asc
                        : SortDirection.desc,
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
          child: Row(
            children: [
              Text(
                l('browse.resultCount', {'n': totalCount}),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => onChanged(
                  order,
                  sort == SortDirection.desc
                      ? SortDirection.asc
                      : SortDirection.desc,
                ),
                icon: Icon(
                  sort == SortDirection.desc
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 16,
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
