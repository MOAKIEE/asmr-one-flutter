import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/models/work.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/settings_state.dart';
import '../state/work_feed.dart';
import '../widgets/player_scaffold.dart';
import '../widgets/work_grid.dart';
import 'login_screen.dart';

/// 相似作品列表页：保留服务端推荐顺序，支持按字幕筛选与分级过滤续页。
class SimilarWorksScreen extends StatefulWidget {
  const SimilarWorksScreen({super.key, required this.work, this.api});

  final Work work;
  final ApiClient? api;

  @override
  State<SimilarWorksScreen> createState() => _SimilarWorksScreenState();
}

class _SimilarWorksScreenState extends State<SimilarWorksScreen> {
  ApiClient get _api => widget.api ?? ApiClient.instance;
  WorkFeed? _feed;
  bool _subtitleOnly = false;
  bool _listMode = false;
  bool? _showNsfw;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final showNsfw = context.watch<SettingsState>().showNsfw;
    if (_feed == null || _showNsfw != showNsfw) {
      _showNsfw = showNsfw;
      _rebuildFeed(showNsfw: showNsfw);
    }
  }

  @override
  void didUpdateWidget(covariant SimilarWorksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.work.id != widget.work.id || oldWidget.api != widget.api) {
      _rebuildFeed(showNsfw: _showNsfw ?? true);
    }
  }

  void _rebuildFeed({required bool showNsfw}) {
    _feed?.dispose();
    final subtitleOnly = _subtitleOnly;
    final feed = WorkFeed(
      (page, _) => _api.fetchSimilarWorks(
        widget.work.id,
        page: page,
        subtitle: subtitleOnly,
      ),
      label: 'similar:${widget.work.id}:$subtitleOnly',
      filter: showNsfw ? null : (work) => !work.nsfw,
    );
    _feed = feed;
    feed.load();
  }

  void _toggleSubtitleOnly(bool value) {
    if (_subtitleOnly == value) return;
    setState(() {
      _subtitleOnly = value;
      _rebuildFeed(showNsfw: _showNsfw ?? true);
    });
  }

  Future<void> _openLogin() async {
    AuthState? auth;
    try {
      auth = context.read<AuthState>();
    } on ProviderNotFoundException {
      return;
    }
    final hadToken = auth.hasToken;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (!mounted) return;
    if (!hadToken && auth.hasToken) {
      _feed?.load();
    }
  }

  @override
  void dispose() {
    _feed?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();
    final feed = _feed!;

    return PlayerScaffold(
      appBar: AppBar(
        title: Text(l('similar.title'), overflow: TextOverflow.ellipsis),
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
      body: RefreshIndicator(
        onRefresh: () => feed.refresh(),
        child: WorkFeedView(
          feed: feed,
          columns: settings.gridColumns,
          listMode: _listMode,
          emptyMessage: l('similar.empty'),
          errorActionBuilder: (context, currentFeed) {
            if (!currentFeed.errorIsAuth) return null;
            return FilledButton.icon(
              onPressed: _openLogin,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(l('auth.login')),
            );
          },
          leadingSlivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.work.title.isNotEmpty) ...[
                      Text(
                        widget.work.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                          label: Text(l('browse.subtitleOnly')),
                          selected: _subtitleOnly,
                          visualDensity: VisualDensity.compact,
                          onSelected: _toggleSubtitleOnly,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
