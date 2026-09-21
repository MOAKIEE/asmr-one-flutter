import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api/api_client.dart';
import '../core/models/common.dart';
import '../core/models/review.dart';
import '../core/models/track.dart';
import '../core/models/work.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/download_state.dart';
import '../state/library_state.dart';
import '../state/player_state.dart';
import '../state/settings_state.dart';
import '../widgets/common.dart';
import '../widgets/work_rail.dart';
import 'player_screen.dart';
import 'playlist_screen.dart';
import 'tag_browse_screen.dart';

/// 作品详情页。
class WorkDetailScreen extends StatefulWidget {
  const WorkDetailScreen({super.key, required this.work});

  /// 列表页传入的作品（可能是列表接口的精简数据，进入后会补全）。
  final Work work;

  @override
  State<WorkDetailScreen> createState() => _WorkDetailScreenState();
}

class _WorkDetailScreenState extends State<WorkDetailScreen> {
  late Work _work = widget.work;
  List<TrackNode> _tracks = const [];
  List<AudioTrack> _flatTracks = const [];
  ReviewPage _reviews = ReviewPage.empty;

  bool _loadingDetail = true;
  bool _loadingTracks = true;
  bool _loadingReviews = false;

  String? _detailError;
  String? _trackError;

  final ApiClient _api = ApiClient.instance;

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _loadTracks();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loadingDetail = true;
      _detailError = null;
    });
    try {
      final full = await _api.fetchWork(_work.id);
      if (!mounted) return;
      setState(() {
        _work = full;
        _loadingDetail = false;
      });
      // 有完整信息后再尝试拉评论。
      _loadReviews();
    } catch (e) {
      // 列表页已经带了基础信息，详情失败时降级展示而不是白屏。
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _detailError = e is ApiException ? e.message : '$e';
      });
    }
  }

  Future<void> _loadTracks() async {
    setState(() {
      _loadingTracks = true;
      _trackError = null;
    });
    try {
      final nodes = await _api.fetchTracks(_work.id);
      if (!mounted) return;
      setState(() {
        _tracks = nodes;
        _flatTracks = nodes.expand((n) => n.flatten()).toList();
        _loadingTracks = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTracks = false;
        _trackError = e is ApiException ? e.message : '$e';
      });
    }
  }

  Future<void> _loadReviews() async {
    if (!context.read<AuthState>().hasToken) return;
    setState(() => _loadingReviews = true);
    try {
      final page = await _api.fetchReviews(_work.id, pageSize: 10);
      if (!mounted) return;
      setState(() {
        _reviews = page;
        _loadingReviews = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 操作
  // ---------------------------------------------------------------------------

  Future<void> _playAll({bool shuffle = false, int startIndex = 0}) async {
    final l = L10n.of(context);
    if (_flatTracks.isEmpty) {
      _toast(_loadingTracks ? l('common.loading') : l('detail.noTracks'));
      return;
    }
    final player = context.read<PlayerState>();
    final result = await player.playWork(
      _work,
      _flatTracks,
      startIndex: startIndex,
      shuffle: shuffle,
    );
    if (!mounted) return;
    if (result.queued == 0) {
      _toast(player.error ?? l('detail.noTracks'));
      player.clearError();
      return;
    }
    if (result.unplayable > 0) {
      _toast('${result.unplayable} / ${_flatTracks.length} 首曲目需要登录后才能播放');
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PlayerScreen()));
  }

  Future<void> _playOne(int index) => _playAll(startIndex: index);

  Future<void> _toggleFavorite() async {
    final l = L10n.of(context);
    final library = context.read<LibraryState>();
    final nowFav = await library.toggleFavorite(_work);
    if (!mounted) return;
    _toast(nowFav ? l('action.favorited') : l('common.remove'));
  }

  Future<void> _download() async {
    final l = L10n.of(context);
    if (_flatTracks.isEmpty) {
      _toast(l('detail.noTracks'));
      return;
    }
    final downloads = context.read<DownloadState>();
    final auth = context.read<AuthState>();
    final result = await downloads.enqueueWork(_work, _flatTracks);
    if (!mounted) return;
    if (result.queued == 0) {
      _toast(auth.hasToken ? l('common.noMore') : l('download.needLogin'));
      return;
    }
    _toast(
      '${l('download.start')} · ${l('download.taskCount', {'n': result.queued})}',
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share() async {
    // 先取出文案，避免在 await 之后再用 context 访问本地化。
    final copiedLabel = L10n.of(context)('common.copied');
    final url = _api.webUrl(_work);
    try {
      await SharePlus.instance.share(ShareParams(text: '${_work.title}\n$url'));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      _toast(copiedLabel);
    }
  }

  Future<void> _openWeb() async {
    final copiedLabel = L10n.of(context)('common.copied');
    final uri = Uri.parse(_work.sourceUrl ?? _api.webUrl(_work));
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      _toast(copiedLabel);
    }
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final settings = context.watch<SettingsState>();
    final isFav = context.select<LibraryState, bool>(
      (s) => s.isFavorite(_work.id),
    );
    final downloads = context.watch<DownloadState>();
    final tasks = downloads.tasksOf(_work.id);
    final activeTasks = tasks.where((t) => t.isActive).length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            title: Text(
              _work.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _CoverBackdrop(work: _work),
            ),
            actions: [
              IconButton(
                tooltip: l('common.share'),
                onPressed: _share,
                icon: const Icon(Icons.share_outlined),
              ),
              IconButton(
                tooltip: l('work.openSource'),
                onPressed: _openWeb,
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: _HeaderCard(
              work: _work,
              loading: _loadingDetail,
              error: _detailError,
              isFavorite: isFav,
              trackCount: _flatTracks.length,
              activeDownloads: activeTasks,
              trackLoading: _loadingTracks,
              onPlay: () => _playAll(),
              onShuffle: () => _playAll(shuffle: true),
              onFavorite: _toggleFavorite,
              onPlaylist: () => showAddToPlaylistSheet(context, _work),
              onDownload: _download,
            ),
          ),
          if (_work.tags.isNotEmpty)
            SliverToBoxAdapter(
              child: _Section(
                title: l('work.tags'),
                icon: Icons.sell_outlined,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _work.tags)
                      ActionChip(
                        label: Text(tag.label(_langOf(context))),
                        onPressed: () => _openTagWorks(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          if (_work.vas.isNotEmpty)
            SliverToBoxAdapter(
              child: _Section(
                title: l('work.vas'),
                icon: Icons.mic_none_rounded,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final va in _work.vas)
                      Chip(
                        avatar: const Icon(Icons.person_outline, size: 16),
                        label: Text(va.name),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _Section(
              title: l('detail.tracks'),
              icon: Icons.queue_music_rounded,
              trailing: _flatTracks.isEmpty
                  ? null
                  : Text(
                      l('detail.trackCount', {'n': _flatTracks.length}),
                      style: theme.textTheme.labelSmall,
                    ),
              child: _TrackList(
                loading: _loadingTracks,
                error: _trackError,
                nodes: _tracks,
                flat: _flatTracks,
                currentTitle: context.select<PlayerState, String?>(
                  (p) => p.currentItem?.title,
                ),
                onRetry: _loadTracks,
                onPlayIndex: _playOne,
                onDownloadAll: _download,
              ),
            ),
          ),
          if (context.watch<AuthState>().hasToken)
            SliverToBoxAdapter(
              child: _Section(
                title: l('detail.reviews'),
                icon: Icons.forum_outlined,
                child: _ReviewList(
                  loading: _loadingReviews,
                  page: _reviews,
                  onRefresh: _loadReviews,
                ),
              ),
            ),
          if (_work.circleId > 0)
            SliverToBoxAdapter(
              child: WorkRail(
                title: _work.circleName.isEmpty
                    ? l('work.circle')
                    : _work.circleName,
                subtitle: l('work.circle'),
                icon: Icons.groups_2_outlined,
                query: WorkQuery(
                  circles: [_work.circleId],
                  order: WorkOrder.dlCount,
                  nsfw: settings.showNsfw ? null : false,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  AppLang _langOf(BuildContext context) {
    switch (Localizations.localeOf(context).languageCode) {
      case 'ja':
        return AppLang.ja;
      case 'en':
        return AppLang.en;
      default:
        return AppLang.zh;
    }
  }

  void _openTagWorks(Tag tag) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => TagBrowseScreen(initialTag: tag)));
  }
}

/// 详情页顶部的封面背景（模糊放大 + 渐变遮罩）。
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        CoverImage(
          url: work.mainCoverUrl,
          seedId: work.id,
          radius: 0,
          blur: false,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surface.withValues(alpha: 0.15),
                scheme.surface.withValues(alpha: 0.65),
                scheme.surface,
              ],
              stops: const [0.0, 0.62, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.work,
    required this.loading,
    required this.error,
    required this.isFavorite,
    required this.trackCount,
    required this.activeDownloads,
    required this.trackLoading,
    required this.onPlay,
    required this.onShuffle,
    required this.onFavorite,
    required this.onPlaylist,
    required this.onDownload,
  });

  final Work work;
  final bool loading;
  final String? error;
  final bool isFavorite;
  final int trackCount;
  final int activeDownloads;
  final bool trackLoading;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback onFavorite;
  final VoidCallback onPlaylist;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = context.watch<SettingsState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 118,
                child: CoverImage(
                  url: work.mainCoverUrl,
                  seedId: work.id,
                  radius: 16,
                  blur: settings.blurNsfw && work.nsfw,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            work.circleName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        AgeBadge(
                          nsfw: work.nsfw,
                          label: work.nsfw
                              ? l('work.adult')
                              : l('work.general'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (work.rateAverage > 0) ...[
                      RatingBadge(
                        rating: work.rateAverage,
                        count: work.rateCount,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Icon(
                          Icons.download_rounded,
                          size: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          Fmt.count(work.dlCount),
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.forum_outlined,
                          size: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${work.reviewCount}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Fmt.price(work.price, l('work.free')),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: work.isFree
                            ? const Color(0xFF3DDC97)
                            : scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    trackLoading
                        ? l('common.loading')
                        : '${l('action.play')}${trackCount > 0 ? ' ($trackCount)' : ''}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShuffle,
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: Text(l('action.shuffle')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ActionButton(
                icon: isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: isFavorite
                    ? l('action.favorited')
                    : l('action.favorite'),
                active: isFavorite,
                onTap: onFavorite,
              ),
              _ActionButton(
                icon: Icons.playlist_add_rounded,
                label: l('action.addToPlaylist'),
                onTap: onPlaylist,
              ),
              _ActionButton(
                icon: activeDownloads > 0
                    ? Icons.downloading_rounded
                    : Icons.download_outlined,
                label: activeDownloads > 0
                    ? '$activeDownloads'
                    : l('action.download'),
                onTap: onDownload,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          _InfoTable(work: work),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, size: 21, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 作品信息表格。
class _InfoTable extends StatelessWidget {
  const _InfoTable({required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      (l('work.no'), work.workNo),
      (l('work.release'), Fmt.date(work.release)),
      (l('work.created'), Fmt.relative(work.createDate)),
      if ((work.duration ?? 0) > 0)
        (l('work.duration'), Fmt.duration(work.duration)),
      if (work.languageEditions.isNotEmpty)
        (
          l('work.languages'),
          work.languageEditions.map((e) => e.label).join(' / '),
        ),
      if (work.rank.isNotEmpty)
        (
          l('work.rank'),
          work.rank.map((r) => '${r.term} #${r.rank}').take(3).join(' · '),
        ),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(rows[i].$1, style: theme.textTheme.labelSmall),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].$2.isEmpty ? '—' : rows[i].$2,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 详情页小节容器。
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 7),
              ],
              Text(title, style: theme.textTheme.titleMedium),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 曲目树。
class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.loading,
    required this.error,
    required this.nodes,
    required this.flat,
    required this.onRetry,
    required this.onPlayIndex,
    required this.onDownloadAll,
    this.currentTitle,
  });

  final bool loading;
  final String? error;
  final List<TrackNode> nodes;
  final List<AudioTrack> flat;
  final String? currentTitle;
  final VoidCallback onRetry;
  final void Function(int index) onPlayIndex;
  final VoidCallback onDownloadAll;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);

    if (loading) {
      return Column(
        children: [
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: ShimmerBox(height: 48, radius: 14),
            ),
        ],
      );
    }

    if (error != null) {
      return ErrorView(message: error!, onRetry: onRetry, compact: true);
    }

    if (flat.isEmpty) {
      return EmptyView(
        message: l('detail.noTracks'),
        icon: Icons.music_off_rounded,
      );
    }

    var index = -1;
    final rows = <Widget>[];
    void walk(List<TrackNode> list, int depth) {
      for (final node in list) {
        if (node.isAudio) {
          index++;
          final i = index;
          final isCurrent = currentTitle != null && currentTitle == node.title;
          rows.add(
            _TrackRow(
              title: Fmt.stripExt(node.title),
              subtitle: node.duration == null
                  ? null
                  : Fmt.duration(node.duration),
              depth: depth,
              isCurrent: isCurrent,
              onPlay: () => onPlayIndex(i),
            ),
          );
        } else {
          rows.add(
            Padding(
              padding: EdgeInsets.fromLTRB(6.0 + depth * 14, 12, 0, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.title,
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          );
          walk(node.children, depth + 1);
        }
      }
    }

    walk(nodes, 0);

    return Column(
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: onDownloadAll,
              icon: const Icon(Icons.download_outlined, size: 17),
              label: Text(l('download.start')),
            ),
          ],
        ),
        ...rows,
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.title,
    required this.depth,
    required this.isCurrent,
    required this.onPlay,
    this.subtitle,
  });

  final String title;
  final int depth;
  final bool isCurrent;
  final VoidCallback onPlay;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0, bottom: 6),
      child: Material(
        color: isCurrent
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isCurrent
                      ? Icons.graphic_eq_rounded
                      : Icons.play_circle_outline_rounded,
                  size: 21,
                  color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isCurrent ? scheme.primary : scheme.onSurface,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 评论列表。
class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.loading,
    required this.page,
    required this.onRefresh,
  });

  final bool loading;
  final ReviewPage page;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (loading && page.reviews.isEmpty) {
      return const Column(
        children: [
          ShimmerBox(height: 72, radius: 14),
          SizedBox(height: 10),
          ShimmerBox(height: 72, radius: 14),
        ],
      );
    }

    if (page.reviews.isEmpty) {
      return Row(
        children: [
          Expanded(
            child: Text(
              l('common.empty'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onRefresh, child: Text(l('common.retry'))),
        ],
      );
    }

    return Column(
      children: [
        for (final r in page.reviews)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RatingBadge(rating: r.rating.toDouble()),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.userName ?? '匿名',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Text(
                      Fmt.relative(r.createdAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                if (r.hasText) ...[
                  const SizedBox(height: 8),
                  Text(
                    r.text!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurface, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
