import 'package:flutter/material.dart';

import '../core/models/work.dart';
import '../l10n/app_localizations.dart';
import 'tag_picker_screen.dart';

/// 弹出筛选面板，返回新的查询条件；用户取消时返回 null。
Future<WorkQuery?> showWorkFilterSheet(
  BuildContext context, {
  required WorkQuery query,
}) {
  return showModalBottomSheet<WorkQuery>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FilterSheet(initial: query),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final WorkQuery initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late WorkOrder _order = widget.initial.order;
  late SortDirection _sort = widget.initial.sort;
  late double _rate = widget.initial.rate ?? 0;
  late int _duration = widget.initial.duration ?? 0;
  late bool _subtitle = widget.initial.subtitle ?? false;
  late bool _translation = widget.initial.includeTranslationWorks ?? false;
  late bool? _nsfw = widget.initial.nsfw;
  late List<int> _tags = [...widget.initial.tags];

  /// 可选的最短时长（秒）。
  static const _durations = [0, 15 * 60, 30 * 60, 60 * 60, 120 * 60];

  String _durationLabel(L10n l, int seconds) {
    if (seconds == 0) return l('common.all');
    final m = seconds ~/ 60;
    if (m < 60) return '$m min';
    final h = m / 60;
    return '${h == h.roundToDouble() ? h.toInt() : h} h';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Text(l('browse.filter'), style: theme.textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: _reset,
                    child: Text(l('browse.clearFilters')),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _Label(l('browse.order')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in WorkOrder.values)
                        if (o != WorkOrder.betterRandom)
                          ChoiceChip(
                            label: Text(_orderLabel(l, o)),
                            selected: _order == o,
                            onSelected: (_) => setState(() => _order = o),
                          ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<SortDirection>(
                    segments: [
                      ButtonSegment(
                        value: SortDirection.desc,
                        label: Text(l('sort.desc')),
                        icon: const Icon(Icons.south_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: SortDirection.asc,
                        label: Text(l('sort.asc')),
                        icon: const Icon(Icons.north_rounded, size: 16),
                      ),
                    ],
                    selected: {_sort},
                    onSelectionChanged: (s) => setState(() => _sort = s.first),
                  ),
                  const SizedBox(height: 24),

                  _Label(l('browse.contentType')),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: -1, label: Text(l('common.all'))),
                      ButtonSegment(value: 0, label: Text(l('work.general'))),
                      ButtonSegment(value: 1, label: Text(l('work.adult'))),
                    ],
                    selected: {_nsfw == null ? -1 : (_nsfw! ? 1 : 0)},
                    onSelectionChanged: (s) => setState(() {
                      final v = s.first;
                      _nsfw = v == -1 ? null : v == 1;
                    }),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      _Label(l('browse.minRating')),
                      const Spacer(),
                      Text(
                        _rate <= 0 ? l('common.all') : _rate.toStringAsFixed(1),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _rate,
                    min: 0,
                    max: 5,
                    divisions: 10,
                    label: _rate <= 0
                        ? l('common.all')
                        : _rate.toStringAsFixed(1),
                    onChanged: (v) => setState(() => _rate = v),
                  ),
                  const SizedBox(height: 12),

                  _Label(l('browse.minDuration')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in _durations)
                        ChoiceChip(
                          label: Text(_durationLabel(l, d)),
                          selected: _duration == d,
                          onSelected: (_) => setState(() => _duration = d),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _SwitchTile(
                    title: l('browse.subtitleOnly'),
                    icon: Icons.subtitles_rounded,
                    value: _subtitle,
                    onChanged: (v) => setState(() => _subtitle = v),
                  ),
                  _SwitchTile(
                    title: l('browse.withTranslation'),
                    icon: Icons.translate_rounded,
                    value: _translation,
                    onChanged: (v) => setState(() => _translation = v),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sell_outlined),
                    title: Text(l('work.tags')),
                    subtitle: Text(
                      _tags.isEmpty
                          ? l('common.all')
                          : l('tag.selectedCount', {'n': _tags.length}),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickTags,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l('common.cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _apply,
                      child: Text(l('common.apply')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _orderLabel(L10n l, WorkOrder o) => switch (o) {
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

  void _reset() {
    setState(() {
      _order = WorkOrder.createDate;
      _sort = SortDirection.desc;
      _rate = 0;
      _duration = 0;
      _subtitle = false;
      _translation = false;
      _nsfw = null;
      _tags = [];
    });
  }

  Future<void> _pickTags() async {
    final result = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => TagPickerScreen(initial: _tags)),
    );
    if (result != null) setState(() => _tags = result);
  }

  void _apply() {
    Navigator.of(context).pop(
      widget.initial.copyWith(
        order: _order,
        sort: _sort,
        page: 1,
        rate: _rate > 0 ? _rate : null,
        clearRate: _rate <= 0,
        duration: _duration > 0 ? _duration : null,
        clearDuration: _duration <= 0,
        subtitle: _subtitle ? true : null,
        includeTranslationWorks: _translation ? true : null,
        nsfw: _nsfw,
        clearNsfw: _nsfw == null,
        tags: _tags,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon),
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 当前生效筛选条件的摘要条（可点击移除单项）。
class ActiveFilterBar extends StatelessWidget {
  const ActiveFilterBar({
    super.key,
    required this.query,
    required this.tagLabels,
    required this.onRemoveTag,
    required this.onClear,
    required this.onAdjustRate,
    required this.onClearDuration,
  });

  final WorkQuery query;

  /// 标签 id -> 展示名，由调用方从标签目录解析，避免这里再依赖全局状态。
  final Map<int, String> tagLabels;
  final void Function(int tagId) onRemoveTag;
  final VoidCallback onClear;
  final VoidCallback onAdjustRate;
  final VoidCallback onClearDuration;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final chips = <Widget>[];

    if (query.nsfw != null) {
      chips.add(
        _Chip(
          label: query.nsfw! ? l('work.adult') : l('work.general'),
          onDeleted: onClear,
        ),
      );
    }
    if (query.rate != null) {
      chips.add(
        _Chip(
          label: '≥ ${query.rate!.toStringAsFixed(1)}',
          onDeleted: onAdjustRate,
        ),
      );
    }
    if (query.duration != null && query.duration! > 0) {
      chips.add(
        _Chip(
          label: '≥ ${query.duration! ~/ 60} min',
          onDeleted: onClearDuration,
        ),
      );
    }
    if (query.subtitle == true) {
      chips.add(_Chip(label: l('work.subtitle')));
    }
    if (query.includeTranslationWorks == true) {
      chips.add(_Chip(label: l('browse.withTranslation')));
    }
    for (final id in query.tags) {
      chips.add(
        _Chip(
          label: '# ${tagLabels[id] ?? id}',
          onDeleted: () => onRemoveTag(id),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: c),
            ),
          Center(
            child: TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: Text(l('browse.clearFilters')),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.onDeleted});

  final String label;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onDeleted: onDeleted,
      deleteIcon: onDeleted == null
          ? null
          : const Icon(Icons.close_rounded, size: 15),
      visualDensity: VisualDensity.compact,
    );
  }
}
