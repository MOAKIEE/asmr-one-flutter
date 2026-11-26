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
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/download_state.dart';
import '../state/library_state.dart';
import '../state/listening_notes.dart';
import '../state/player_state.dart';
import '../state/settings_state.dart';
import '../widgets/app_motion.dart';
import '../widgets/player_scaffold.dart';
import '../widgets/common.dart';
import '../widgets/work_rail.dart';
import 'login_screen.dart';
import 'player_screen.dart';
import 'playlist_screen.dart';
import 'similar_works_screen.dart';
import 'tag_browse_screen.dart';

/// 作品详情页。
class WorkDetailScreen extends StatefulWidget {
  const WorkDetailScreen({
    super.key,
    required this.work,
    this.coverTag,
    this.api,
  });

  /// 列表页传入的作品（可能是列表接口的精简数据，进入后会补全）。
  final Work work;
  final ApiClient? api;
  final Object? coverTag;

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

  ListeningStatus? _listeningStatus;
  bool _statusConfirmed = false;
  bool _loadingStatus = false;
  bool _savingStatus = false;
  bool _statusNeedsReconcile = false;
  String? _statusError;
  int _statusGeneration = 0;
  String? _observedAccountKey;

  String? _detailError;
  String? _trackError;

  ApiClient get _api => widget.api ?? ApiClient.instance;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthState>(context);
    final nextKey = auth.accountKey;
    if (_observedAccountKey == null) {
      _observedAccountKey = nextKey;
      _loadingDetail = true;
      _detailError = null;
      if (auth.hasToken) {
        _loadingStatus = true;
        _statusError = null;
      }
      _loadDetail(auth: auth, emitInitialState: false);
      return;
    }
    if (_observedAccountKey != nextKey) {
      _observedAccountKey = nextKey;
      _resetAccountBoundState();
      if (auth.hasToken) {
        _loadingDetail = true;
        _detailError = null;
        _loadingStatus = true;
        _statusError = null;
        _loadDetail(auth: auth, emitInitialState: false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant WorkDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.work.id != widget.work.id) {
      _work = widget.work;
      _tracks = const [];
      _flatTracks = const [];
      _detailError = null;
      _trackError = null;
      _resetAccountBoundState();
      _loadTracks();
      _loadDetail(auth: context.read<AuthState>());
    }
  }

  void _resetAccountBoundState() {
    _statusGeneration++;
    _listeningStatus = null;
    _statusConfirmed = false;
    _loadingStatus = false;
    _savingStatus = false;
    _statusNeedsReconcile = false;
    _statusError = null;
    _reviews = ReviewPage.empty;
    _loadingReviews = false;
  }

  bool _isStatusScopeValid(int workId, String accountKey, int generation) =>
      mounted &&
      _work.id == workId &&
      _observedAccountKey == accountKey &&
      _statusGeneration == generation;

  Future<void> _loadDetail({
    AuthState? auth,
    bool emitInitialState = true,
  }) async {
    final activeAuth = auth ?? context.read<AuthState>();
    final workId = _work.id;
    final accountKey = activeAuth.accountKey;
    final hasToken = activeAuth.hasToken;
    final generation = ++_statusGeneration;

    if (emitInitialState) {
      setState(() {
        _loadingDetail = true;
        _detailError = null;
        if (hasToken) {
          _loadingStatus = true;
          _statusError = null;
        }
      });
    }
    try {
      final full = await _api.fetchWork(workId);
      if (!_isStatusScopeValid(workId, accountKey, generation)) return;
      setState(() {
        _work = full;
        _loadingDetail = false;
        if (hasToken && full.hasProgressField) {
          _listeningStatus = full.listeningStatus;
          _statusConfirmed = true;
          _loadingStatus = false;
          _statusError = null;
          _statusNeedsReconcile = false;
        } else if (!hasToken) {
          _listeningStatus = null;
          _statusConfirmed = false;
          _loadingStatus = false;
          _statusError = null;
        }
      });
      if (hasToken) {
        if (!full.hasProgressField) {
          _resolveStatusFromReviews(workId, activeAuth, accountKey, generation);
        }
        _loadReviews(workId: workId, accountKey: accountKey);
      }
    } catch (e) {
      // 列表页已经带了基础信息，详情失败时降级展示而不是白屏。
      if (!_isStatusScopeValid(workId, accountKey, generation)) return;
      final message = e is ApiException ? e.message : '$e';
      setState(() {
        _loadingDetail = false;
        _detailError = message;
        if (hasToken) {
          _loadingStatus = false;
          _statusError = message;
        }
      });
    }
  }

  Future<void> _resolveStatusFromReviews(
    int workId,
    AuthState auth,
    String accountKey,
    int generation,
  ) async {
    try {
      final resolved = await _api.fetchMyListeningStatusFromReviews(
        workId,
        userId: auth.user.id,
        userName: auth.user.name,
      );
      if (!_isStatusScopeValid(workId, accountKey, generation)) return;
      setState(() {
        _listeningStatus = resolved;
        _statusConfirmed = true;
        _loadingStatus = false;
        _statusError = null;
        _statusNeedsReconcile = false;
      });
    } catch (e) {
      if (!_isStatusScopeValid(workId, accountKey, generation)) return;
      setState(() {
        _loadingStatus = false;
        _statusError = e is ApiException ? e.message : '$e';
      });
    }
  }

  Future<({Work? work, ListeningStatus? status})> _readRemoteStatus(
    int workId,
    AuthState auth,
  ) async {
    final full = await _api.fetchWork(workId);
    if (full.hasProgressField) {
      return (work: full, status: full.listeningStatus);
    }
    final fromReviews = await _api.fetchMyListeningStatusFromReviews(
      workId,
      userId: auth.user.id,
      userName: auth.user.name,
    );
    return (work: full, status: fromReviews);
  }

  Future<void> _retryLoadStatus() async {
    final auth = context.read<AuthState>();
    if (!auth.hasToken || _savingStatus) return;
    final workId = _work.id;
    final accountKey = auth.accountKey;
    final generation = ++_statusGeneration;
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });
    try {
      final res = await _readRemoteStatus(workId, auth);
      if (!_isStatusScopeValid(workId, accountKey, generation)) return;
      setState(() {
        if (res.work != null) _work = res.work!;
        _listeningStatus = res.status;
        _statusConfirmed = true;
        _loadingStatus = false;
        _statusError = null;
        _statusNeedsReconcile = false;
      });
    } catch (e) {
      if (!_isStatusScopeValid(workId, accountKey, generation)) return;
      setState(() {
        _loadingStatus = false;
        _statusError = e is ApiException ? e.message : '$e';
      });
    }
  }

  Future<void> _openStatusPicker() async {
    final auth = context.read<AuthState>();
    if (!auth.hasToken) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    if (_savingStatus || _loadingStatus) return;
    if (_statusError != null && !_statusConfirmed) {
      await _retryLoadStatus();
      return;
    }
    final picked = await showModalBottomSheet<ListeningStatus>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => _ListeningStatusSheet(
        current: _statusConfirmed ? _listeningStatus : null,
      ),
    );
    if (!mounted || picked == null) return;
    await _saveListeningStatus(picked);
  }

  Future<void> _saveListeningStatus(ListeningStatus target) async {
    final auth = context.read<AuthState>();
    if (!auth.hasToken || _savingStatus) return;
    final l = L10n.of(context);
    final updatedLabel = l('status.updated', {'status': l(target.labelKey)});
    final timeoutVerifyLabel = l('status.timeoutVerify');

    final workId = _work.id;
    final accountKey = auth.accountKey;
    final generation = ++_statusGeneration;

    setState(() {
      _savingStatus = true;
      _statusError = null;
    });

    // 若上次写入超时，再次提交前先读回服务端状态，避免盲目重复写入。
    if (_statusNeedsReconcile) {
      try {
        final synced = await _readRemoteStatus(workId, auth);
        if (!_isStatusScopeValid(workId, accountKey, generation)) return;
        setState(() {
          if (synced.work != null) _work = synced.work!;
          _listeningStatus = synced.status;
          _statusConfirmed = true;
          _statusNeedsReconcile = false;
        });
        if (synced.status == target) {
          setState(() => _savingStatus = false);
          _toast(updatedLabel);
          return;
        }
      } catch (e) {
        if (!_isStatusScopeValid(workId, accountKey, generation)) return;
        final message = e is ApiException ? e.message : '$e';
        setState(() {
          _savingStatus = false;
          _statusError = message;
        });
        _toast(message);
        return;
      }
    }

    try {
      await _api.updateWorkProgress(workId: workId, status: target);
      if (!_isStatusScopeValid(workId, accountKey, generation)) return;
      setState(() {
        _listeningStatus = target;
        _statusConfirmed = true;
        _statusNeedsReconcile = false;
        _savingStatus = false;
        _statusError = null;
      });
      _toast(updatedLabel);
    } on ApiException catch (e) {
      if (!_isStatusScopeValid(workId, accountKey, generation)) return;
      if (e.isTimeout) {
        // 超时可能发生在服务端已写入之后，先尝试读回一次以核实结果。
        _statusNeedsReconcile = true;
        try {
          final synced = await _readRemoteStatus(workId, auth);
          if (!_isStatusScopeValid(workId, accountKey, generation)) return;
          setState(() {
            if (synced.work != null) _work = synced.work!;
            _listeningStatus = synced.status;
            _statusConfirmed = true;
            _statusNeedsReconcile = false;
            _savingStatus = false;
            _statusError = null;
          });
          _toast(synced.status == target ? updatedLabel : e.message);
        } catch (_) {
          if (!_isStatusScopeValid(workId, accountKey, generation)) return;
          setState(() {
            _savingStatus = false;
            _statusError = e.message;
          });
          _toast(timeoutVerifyLabel);
        }
      } else {
        setState(() {
          _savingStatus = false;
          _statusError = e.message;
        });
        _toast(e.message);
      }
    } catch (e) {
      if (!_isStatusScopeValid(workId, accountKey, generation)) return;
      final message = '$e';
      setState(() {
        _savingStatus = false;
        _statusError = message;
      });
      _toast(message);
    }
  }

  Future<void> _loadTracks() async {
    final workId = _work.id;
    setState(() {
      _loadingTracks = true;
      _trackError = null;
    });
    try {
      final nodes = await _api.fetchTracks(workId);
      if (!mounted || _work.id != workId) return;
      try {
        context.read<ListeningNotes>().cacheTrackTree(workId, nodes);
      } on ProviderNotFoundException {
        // Standalone detail widget tests may omit app-level ListeningNotes.
      }
      setState(() {
        _tracks = nodes;
        _flatTracks = nodes.expand((n) => n.flatten()).toList();
        _loadingTracks = false;
      });
    } catch (e) {
      if (!mounted || _work.id != workId) return;
      setState(() {
        _loadingTracks = false;
        _trackError = e is ApiException ? e.message : '$e';
      });
    }
  }

  Future<void> _loadReviews({int? workId, String? accountKey}) async {
    final auth = context.read<AuthState>();
    if (!auth.hasToken) return;
    final targetWorkId = workId ?? _work.id;
    final targetAccount = accountKey ?? auth.accountKey;
    setState(() => _loadingReviews = true);
    try {
      final page = await _api.fetchReviews(targetWorkId, pageSize: 10);
      if (!mounted ||
          _work.id != targetWorkId ||
          _observedAccountKey != targetAccount) {
        return;
      }
      setState(() {
        _reviews = page;
        _loadingReviews = false;
      });
    } catch (_) {
      if (mounted &&
          _work.id == targetWorkId &&
          _observedAccountKey == targetAccount) {
        setState(() => _loadingReviews = false);
      }
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
      _toast(
        l('detail.needLoginSomeTracks', {
          'unplayable': result.unplayable,
          'total': _flatTracks.length,
        }),
      );
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

    return PlayerScaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: theme.scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            title: Builder(
              builder: (ctx) {
                final bar = ctx
                    .dependOnInheritedWidgetOfExactType<
                      FlexibleSpaceBarSettings
                    >();
                final opacity = bar == null
                    ? 1.0
                    : (1 - (bar.currentExtent - bar.minExtent) / 48).clamp(
                        0.0,
                        1.0,
                      );
                return Opacity(
                  opacity: opacity,
                  child: Text(
                    _work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
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
              coverTag: widget.coverTag,
              work: _work,
              loading: _loadingDetail,
              error: _detailError,
              isFavorite: isFav,
              trackCount: _flatTracks.length,
              activeDownloads: activeTasks,
              trackLoading: _loadingTracks,
              hasToken: context.watch<AuthState>().hasToken,
              listeningStatus: _statusConfirmed ? _listeningStatus : null,
              statusLoading: _loadingStatus,
              statusSaving: _savingStatus,
              statusError: _statusError,
              onPlay: () => _playAll(),
              onShuffle: () => _playAll(shuffle: true),
              onFavorite: _toggleFavorite,
              onPlaylist: () => showAddToPlaylistSheet(context, _work),
              onDownload: _download,
              onListeningStatus: _openStatusPicker,
              onRetryStatus: _retryLoadStatus,
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: AppGroupCard(
                radius: 16,
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.auto_awesome_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  title: Text(l('similar.title')),
                  subtitle: Text(
                    l('similar.subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openSimilarWorks,
                ),
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
                api: widget.api,
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

  void _openSimilarWorks() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SimilarWorksScreen(work: _work, api: widget.api),
      ),
    );
  }
}

/// 详情页顶部的封面背景（模糊放大 + 渐变遮罩）。
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    final scaffold = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        CoverImage(
          url: work.mainCoverUrl,
          seedId: work.id,
          radius: 0,
          blur: true,
          showRevealButton: false,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scaffold.withValues(alpha: 0.52),
                scaffold.withValues(alpha: 0.18),
                scaffold.withValues(alpha: 0.72),
                scaffold,
              ],
              stops: const [0.0, 0.3, 0.68, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Object? coverTag;
  const _HeaderCard({
    required this.coverTag,
    required this.work,
    required this.loading,
    required this.error,
    required this.isFavorite,
    required this.trackCount,
    required this.activeDownloads,
    required this.trackLoading,
    required this.hasToken,
    required this.listeningStatus,
    required this.statusLoading,
    required this.statusSaving,
    required this.statusError,
    required this.onPlay,
    required this.onShuffle,
    required this.onFavorite,
    required this.onPlaylist,
    required this.onDownload,
    required this.onListeningStatus,
    required this.onRetryStatus,
  });

  final Work work;
  final bool loading;
  final String? error;
  final bool isFavorite;
  final int trackCount;
  final int activeDownloads;
  final bool trackLoading;
  final bool hasToken;
  final ListeningStatus? listeningStatus;
  final bool statusLoading;
  final bool statusSaving;
  final String? statusError;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback onFavorite;
  final VoidCallback onPlaylist;
  final VoidCallback onDownload;
  final VoidCallback onListeningStatus;
  final VoidCallback onRetryStatus;

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
                child: CoverHero(
                  tag: coverTag,
                  child: CoverImage(
                    url: work.mainCoverUrl,
                    seedId: work.id,
                    radius: 16,
                    blur: settings.blurNsfw && work.nsfw,
                  ),
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
                          Fmt.count(
                            work.dlCount,
                            languageCode: Localizations.localeOf(context)
                                .languageCode,
                          ),
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
                flex: 3,
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      trackLoading
                          ? l('common.loading')
                          : '${l('action.play')}${trackCount > 0 ? ' ($trackCount)' : ''}',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: onShuffle,
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(l('action.shuffle')),
                  ),
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
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.playlist_add_rounded,
                label: l('action.addToPlaylist'),
                onTap: onPlaylist,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: activeDownloads > 0
                    ? Icons.downloading_rounded
                    : Icons.download_outlined,
                label: activeDownloads > 0
                    ? l('detail.downloadingCount', {'n': activeDownloads})
                    : l('action.download'),
                active: activeDownloads > 0,
                onTap: onDownload,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ListeningStatusBar(
            hasToken: hasToken,
            status: listeningStatus,
            loading: statusLoading,
            saving: statusSaving,
            error: statusError,
            onTap: onListeningStatus,
            onRetry: onRetryStatus,
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
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: 0.14)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: active
                ? scheme.primary.withValues(alpha: 0.4)
                : scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: AppMotion.duration(context, AppMotion.quick),
                  transitionBuilder: (child, animation) {
                    if (child.key != const ValueKey(Icons.favorite_rounded)) {
                      return FadeTransition(opacity: animation, child: child);
                    }
                    final pulse = TweenSequence<double>([
                      TweenSequenceItem(
                        tween: Tween(begin: 1, end: 1.16),
                        weight: 45,
                      ),
                      TweenSequenceItem(
                        tween: Tween(begin: 1.16, end: 1),
                        weight: 55,
                      ),
                    ]);
                    return ScaleTransition(
                      scale: animation.drive(pulse),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    size: 20,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
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
    final langCode = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      (l('work.no'), work.workNo),
      (l('work.release'), Fmt.date(work.release)),
      (
        l('work.created'),
        Fmt.relative(work.createDate, languageCode: langCode),
      ),
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
        decoration: AppDecor.groupBox(theme.colorScheme, radius: 16),
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
        } else if (node.isFolder || node.children.isNotEmpty) {
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
        } else {
          final lower = node.title.toLowerCase();
          final isSub =
              lower.endsWith('.lrc') ||
              lower.endsWith('.srt') ||
              lower.endsWith('.vtt') ||
              lower.endsWith('.ass');
          rows.add(
            Padding(
              padding: EdgeInsets.fromLTRB(6.0 + depth * 14, 6, 6, 6),
              child: Row(
                children: [
                  Icon(
                    isSub
                        ? Icons.subtitles_outlined
                        : Icons.description_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
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
                    if (r.listeningStatus != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          l(r.listeningStatus!.labelKey),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.userName ?? l('detail.anonymous'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Text(
                      Fmt.relative(
                        r.createdAt,
                        languageCode: Localizations.localeOf(context)
                            .languageCode,
                      ),
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

IconData _statusIcon(ListeningStatus? status) => switch (status) {
  ListeningStatus.marked => Icons.bookmark_border_rounded,
  ListeningStatus.listening => Icons.headphones_rounded,
  ListeningStatus.listened => Icons.check_circle_outline_rounded,
  ListeningStatus.replay => Icons.replay_rounded,
  ListeningStatus.postponed => Icons.pause_circle_outline_rounded,
  null => Icons.bookmark_add_outlined,
};

/// 作品收听状态入口条（区分游客、加载、读取失败、保存中与已确认标记）。
class _ListeningStatusBar extends StatelessWidget {
  const _ListeningStatusBar({
    required this.hasToken,
    required this.status,
    required this.loading,
    required this.saving,
    required this.error,
    required this.onTap,
    required this.onRetry,
  });

  final bool hasToken;
  final ListeningStatus? status;
  final bool loading;
  final bool saving;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = hasToken && status != null;
    final busy = loading || saving;
    final showLoadError = hasToken && !busy && status == null && error != null;

    final String valueLabel;
    if (!hasToken) {
      valueLabel = l('status.loginToMark');
    } else if (saving) {
      valueLabel = l('status.saving');
    } else if (loading) {
      valueLabel = l('common.loading');
    } else if (showLoadError) {
      valueLabel = l('status.loadFailed');
    } else if (status != null) {
      valueLabel = l(status!.labelKey);
    } else {
      valueLabel = l('status.unset');
    }

    final accent = active
        ? scheme.primary
        : (showLoadError ? scheme.error : scheme.onSurfaceVariant);

    return Material(
      color: active
          ? scheme.primary.withValues(alpha: 0.12)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: active
              ? scheme.primary.withValues(alpha: 0.4)
              : (showLoadError
                    ? scheme.error.withValues(alpha: 0.45)
                    : scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: InkWell(
        onTap: busy ? null : (showLoadError ? onRetry : onTap),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(_statusIcon(hasToken ? status : null), size: 19, color: accent),
              const SizedBox(width: 10),
              Text(
                l('status.title'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  valueLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (showLoadError)
                Icon(Icons.refresh_rounded, size: 18, color: scheme.error)
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 五种互斥收听状态选择器面板。
class _ListeningStatusSheet extends StatelessWidget {
  const _ListeningStatusSheet({required this.current});

  final ListeningStatus? current;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(l('status.title'), style: theme.textTheme.titleMedium),
            ),
            for (final status in ListeningStatus.values)
              ListTile(
                leading: Icon(
                  _statusIcon(status),
                  color: current == status
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                title: Text(
                  l(status.labelKey),
                  style: current == status
                      ? TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        )
                      : null,
                ),
                subtitle: Text(l(status.hintKey)),
                trailing: Icon(
                  current == status
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: current == status ? scheme.primary : null,
                ),
                onTap: () => Navigator.of(context).pop(status),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
