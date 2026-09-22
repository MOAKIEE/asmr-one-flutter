import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/data/featured_tags.dart';
import '../core/models/common.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/settings_state.dart';
import '../state/work_feed.dart';
import '../widgets/common.dart';
import '../widgets/work_grid.dart';
import 'tag_browse_screen.dart';

/// 搜索页：历史 / 热门标签 + 结果列表。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.api});

  final ApiClient? api;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _debouncer = Debouncer();

  WorkFeed? _feed;
  String _keyword = '';
  bool _listMode = false;

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    _focus.dispose();
    _feed?.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _debouncer.run(() => _search(value, record: false));
  }

  void _search(String keyword, {bool record = true}) {
    final k = keyword.trim();
    if (record) {
      _debouncer.cancel();
      if (k.isNotEmpty) {
        context.read<SettingsState>().addSearchHistory(k);
        _focus.unfocus();
      }
    }
    if (k == _keyword && _feed != null) return;
    setState(() {
      _keyword = k;
      _feed?.dispose();
      _feed = k.isEmpty
          ? null
          : WorkFeed(
              (page, pageSize) => (widget.api ?? ApiClient.instance).search(
                k,
                page: page,
                pageSize: pageSize,
                nsfw: context.read<SettingsState>().showNsfw ? null : false,
              ),
              pageSize: 24,
              label: 'search:$k',
            );
    });
    if (k.isEmpty) return;
    _feed?.load();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l('search.title')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (v) => _search(v),
              decoration: InputDecoration(
                hintText: l('search.hint'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          _search('');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: _feed == null
          ? _Suggestions(
              onSelect: (k) {
                _controller.text = k;
                _search(k);
              },
            )
          : WorkFeedView(
              feed: _feed!,
              columns: settings.gridColumns,
              listMode: _listMode,
              leadingSlivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 10, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l('browse.resultCount', {'n': _feed!.totalCount}),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: _listMode
                              ? l('browse.gridView')
                              : l('browse.listView'),
                          onPressed: () =>
                              setState(() => _listMode = !_listMode),
                          icon: Icon(
                            _listMode
                                ? Icons.grid_view_rounded
                                : Icons.view_list_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// 无关键词时展示的搜索历史与热门标签。
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onSelect});

  final void Function(String keyword) onSelect;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();
    final history = settings.searchHistory;
    final hotTags = FeaturedTags.resolve();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (history.isNotEmpty) ...[
          SectionHeader(
            title: l('search.history'),
            icon: Icons.history_rounded,
            action: l('search.clearHistory'),
            onAction: settings.clearSearchHistory,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in history)
                InputChip(
                  label: Text(h),
                  onPressed: () => onSelect(h),
                  onDeleted: () => settings.removeSearchHistory(h),
                  deleteIcon: const Icon(Icons.close_rounded, size: 15),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        SectionHeader(
          title: l('search.hotTags'),
          icon: Icons.local_fire_department_rounded,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in hotTags)
              ActionChip(
                label: Text(tag.label(AppLang.zh)),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TagBrowseScreen(initialTag: tag),
                  ),
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            l('search.hint'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
