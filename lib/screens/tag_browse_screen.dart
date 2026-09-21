import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/common.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/settings_state.dart';
import '../state/work_feed.dart';
import '../widgets/work_grid.dart';
import 'tag_picker_screen.dart';

/// 按标签浏览：顶部标签条 + 结果列表。
class TagBrowseScreen extends StatefulWidget {
  const TagBrowseScreen({super.key, this.initialTag});

  final Tag? initialTag;

  @override
  State<TagBrowseScreen> createState() => _TagBrowseScreenState();
}

class _TagBrowseScreenState extends State<TagBrowseScreen> {
  late final BrowseController _controller;
  late List<int> _selected;
  bool _listMode = false;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialTag == null ? [] : [widget.initialTag!.id];
    _controller = BrowseController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final settings = context.read<SettingsState>();
    _reload(settings.showNsfw);
  }

  void _reload(bool showNsfw) {
    _controller.update(
      _controller.query.copyWith(
        tags: _selected,
        nsfw: showNsfw ? null : false,
        clearNsfw: showNsfw,
      ),
    );
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
    final lang = _lang;

    // 顶部标签条：已选标签优先，其后是热门标签，按 id 去重保序。
    final byId = {for (final t in auth.tags) t.id: t};
    final ordered = <Tag>[
      for (final id in _selected)
        if (byId[id] != null) byId[id]!,
      for (final t in auth.tags.take(40))
        if (!_selected.contains(t.id)) t,
    ];
    final seen = <int>{};
    final tags = [
      for (final t in ordered)
        if (seen.add(t.id)) t,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selected.isEmpty
              ? l('tag.browse')
              : l('tag.selectedCount', {'n': _selected.length}),
        ),
        actions: [
          IconButton(
            tooltip: _listMode ? l('browse.gridView') : l('browse.listView'),
            onPressed: () => setState(() => _listMode = !_listMode),
            icon: Icon(
              _listMode ? Icons.grid_view_rounded : Icons.view_list_rounded,
            ),
          ),
          IconButton(
            tooltip: l('tag.searchHint'),
            onPressed: _openPicker,
            icon: const Icon(Icons.manage_search_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: tags.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    itemCount: tags.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final tag = tags[i];
                      final selected = _selected.contains(tag.id);
                      return Center(
                        child: FilterChip(
                          label: Text(tag.label(lang)),
                          selected: selected,
                          onSelected: (_) => _toggle(tag.id),
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: WorkFeedView(
              feed: _controller.works,
              columns: settings.gridColumns,
              listMode: _listMode,
              leadingSlivers: [
                if (_selected.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.touch_app_outlined,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l('browse.filter'),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggle(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected = [..._selected]..remove(id);
      } else {
        _selected = [id, ..._selected];
      }
    });
    final settings = context.read<SettingsState>();
    _reload(settings.showNsfw);
  }

  Future<void> _openPicker() async {
    final result = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => TagPickerScreen(initial: _selected)),
    );
    if (result == null) return;
    setState(() => _selected = result);
    if (!mounted) return;
    _reload(context.read<SettingsState>().showNsfw);
  }
}
