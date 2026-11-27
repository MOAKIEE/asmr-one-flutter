// 命名参数无法使用私有初始化形参（`this._settings`），此处显式赋值。
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:just_audio_background/just_audio_background.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path/path.dart' as p;

import '../core/api/api_client.dart';
import '../core/models/track.dart';
import '../core/models/work.dart';
import '../core/storage/library_db.dart';
import '../core/storage/stream_audio_cache.dart';
import 'library_state.dart';
import 'settings_state.dart';

/// 播放队列中的一项。
class PlayItem {
  const PlayItem({
    required this.workId,
    required this.workTitle,
    required this.title,
    required this.url,
    required this.coverUrl,
    this.hash,
    this.circleName = '',
    this.folderLabel = '',
    this.duration,
    this.localPath,
    this.lowQuality = false,
  });

  final int workId;
  final String workTitle;
  final String title;
  final String url;
  final String coverUrl;
  final String? hash;
  final String circleName;
  final String folderLabel;
  final Duration? duration;
  final String? localPath;
  final bool lowQuality;

  bool get isLocal => (localPath ?? '').isNotEmpty;
}

/// 播放器状态：队列管理、进度、倍速、定时关闭、封面取色。
class PlayerState extends ChangeNotifier {
  PlayerState({
    required SettingsState settings,
    required LibraryState library,
    ja.AudioPlayer? audioPlayer,
    ApiClient? api,
    StreamAudioCache? audioCache,
    String? Function()? accountScope,
    this.readSession,
    this.writeSession,
    DateTime Function()? now,
  }) : _settings = settings,
       _now = now ?? DateTime.now,
       _library = library,
       _api = api ?? ApiClient.instance,
       _audioCache = audioCache,
       _accountScope = accountScope,
       _player = audioPlayer ?? ja.AudioPlayer() {
    _autoPlayNext = settings.autoPlayNext;
    _streamCacheEnabled = settings.streamCacheEnabled;
    _settings.addListener(_settingsChanged);
    _player.setSpeed(settings.playbackSpeed);
    _bind();
  }

  final SettingsState _settings;
  final LibraryState _library;
  final ApiClient _api;
  final StreamAudioCache? _audioCache;
  final String? Function()? _accountScope;
  String? _activeRouteGroupId;
  String? _buildingRouteGroupId;
  Map<int, String> _queueCacheKeys = const {};
  String? _activePlayingCacheKey;
  String? _appliedCacheScope;
  String? _buildingCacheScope;
  Future<void>? _inFlightSourceUpdate;
  bool _lastSourceUpdateOk = false;
  bool _lastSourceUpdatePreloaded = true;
  bool _autoPlayAllowedForLoad = false;
  bool? _resumeAfterReload;
  Duration? _reloadPosition;
  Duration? _pendingSeekPosition;

  final ja.AudioPlayer _player;
  final DateTime Function() _now;
  final Future<Map<String, Object?>> Function(List<String>)? readSession;
  final Future<void> Function(Map<String, Object?>)? writeSession;
  static const _cursorDocument = 'playerSession';
  static const _queueDocument = 'playerQueue';
  List<PlayItem>? _persistedQueue;
  Future<void> _sessionWrites = Future.value();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;
  bool _restoring = false;
  int _loadVersion = 0;
  int _sourceVersion = 0;
  String? _appliedMediaToken;
  bool _stopAfterTrack = false;
  bool get stopAfterTrack => _stopAfterTrack;
  bool _fadeSleep = true;
  double? _sleepVolume;
  Duration? _loopStart;
  Duration? _loopEnd;
  bool _loopSeeking = false;
  Duration? get loopStart => _loopStart;
  Duration? get loopEnd => _loopEnd;

  Future<void> _persistSession() async {
    final write = writeSession;
    if (_restoring || write == null) return;
    final queue = _queue;
    final cursor = queue.isEmpty
        ? null
        : {
            'index': _currentIndex,
            'position': _player.position.inMilliseconds,
            'shuffle': _player.shuffleModeEnabled,
            'loop': _loopMode.index,
          };
    final save = _sessionWrites.then((_) async {
      if (identical(queue, _persistedQueue)) {
        if (cursor != null) await write({_cursorDocument: cursor});
        return;
      }
      await write({
        _cursorDocument: cursor,
        _queueDocument: queue.isEmpty
            ? null
            : [
                for (final item in queue)
                  {
                    'workId': item.workId,
                    'workTitle': item.workTitle,
                    'title': item.title,
                    'hash': item.hash,
                    'url': _cleanUrl(item.url),
                    'coverUrl': item.coverUrl,
                    'circleName': item.circleName,
                    'folderLabel': item.folderLabel,
                    'duration': item.duration?.inMilliseconds,
                    'localPath': item.localPath,
                    if (item.lowQuality) 'lowQuality': true,
                  },
              ],
      });
      _persistedQueue = queue;
    });
    _sessionWrites = save.catchError((Object _) {});
    await save;
  }

  static String _cleanUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri == null
        ? ''
        : uri
              .replace(
                queryParameters: {...uri.queryParameters}..remove('token'),
              )
              .toString();
  }

  static bool _isApiMedia(Uri uri) =>
      uri.scheme == 'https' &&
      uri.path.startsWith('/api/media/') &&
      ApiClient.baseUrls.any((base) => Uri.parse(base).host == uri.host);

  static String _queueUrl(String? url) {
    if (url == null) return '';
    final uri = Uri.tryParse(url);
    return uri != null && _isApiMedia(uri) ? _cleanUrl(url) : url;
  }

  Future<void> restoreSession() async {
    if (readSession == null || hasQueue) return;
    final version = _loadVersion;
    final documents = await readSession!([_cursorDocument, _queueDocument]);
    final saved = documents[_cursorDocument];
    if (saved is! Map || hasQueue || version != _loadVersion) {
      return;
    }
    final legacyItems = saved['items'];
    final storedItems = legacyItems is List
        ? legacyItems
        : documents[_queueDocument];
    if (storedItems is! List) return;
    _restoring = true;
    try {
      final items = <PlayItem>[];
      var index = 0;
      var selectedExists = false;
      final savedIndex = saved['index'] as int? ?? 0;
      var sourceIndex = 0;
      for (final raw in storedItems) {
        final m = raw as Map;
        final local = m['localPath'] as String?;
        final originalIndex = sourceIndex++;
        if (local != null && !await File(local).exists()) continue;
        if (originalIndex < savedIndex) index++;
        if (originalIndex == savedIndex) selectedExists = true;
        items.add(
          PlayItem(
            workId: m['workId'] as int,
            workTitle: m['workTitle'] as String,
            title: m['title'] as String,
            url: _queueUrl(m['url'] as String?),
            coverUrl: m['coverUrl'] as String,
            hash: m['hash'] as String?,
            circleName: m['circleName'] as String? ?? '',
            folderLabel: m['folderLabel'] as String? ?? '',
            localPath: local,
            lowQuality: m['lowQuality'] == true,
            duration: m['duration'] == null
                ? null
                : Duration(milliseconds: m['duration'] as int),
          ),
        );
      }
      if (items.isEmpty || hasQueue || version != _loadVersion) return;
      _loopMode = ja.LoopMode.values[(saved['loop'] as int? ?? 0).clamp(0, 2)];
      index = index.clamp(0, items.length - 1);
      final item = items[index];
      _work = Work.fromJson({
        'id': item.workId,
        'title': item.workTitle,
        'name': item.circleName,
      });
      final restored = await _load(
        items,
        index: index,
        shuffle: saved['shuffle'] == true,
        initialPosition: Duration(
          milliseconds: selectedExists
              ? (saved['position'] as int? ?? 0).clamp(0, 1 << 40)
              : 0,
        ),
      );
      if (restored && identical(items, _queue)) {
        if (legacyItems is! List && items.length == storedItems.length) {
          _persistedQueue = items;
        } else {
          _restoring = false;
          await _persistSession();
        }
      }
      // Restoring a session never starts playback without user interaction.
    } catch (e) {
      _error = '恢复播放队列失败：$e';
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  void markLoopStart() {
    _loopStart = _player.position;
    _loopEnd = null;
    notifyListeners();
  }

  bool markLoopEnd() {
    if (_loopStart == null ||
        _player.position <= _loopStart! + const Duration(milliseconds: 500)) {
      return false;
    }
    _loopEnd = _player.position;
    notifyListeners();
    return true;
  }

  void clearAbLoop() {
    _loopStart = null;
    _loopEnd = null;
    notifyListeners();
  }

  Future<void> setStopAfterTrack(bool enabled) async {
    clearSleepTimer();
    _stopAfterTrack = enabled;
    if (hasQueue) await _reloadPlaybackMode();
    notifyListeners();
  }

  late bool _autoPlayNext;
  late bool _streamCacheEnabled;
  bool _singleSource = false;
  bool _changingSources = false;
  ja.LoopMode _loopMode = ja.LoopMode.off;

  ja.AudioPlayer get player => _player;

  List<PlayItem> _queue = const [];
  List<int> _singleShuffleOrder = [];
  Work? _work;
  int _currentIndex = -1;
  String? _error;
  Timer? _sleepTimer;
  DateTime? _sleepDeadline;
  Timer? _progressTimer;
  String? _accentSourceUrl;

  List<PlayItem> get queue => _queue;
  Work? get work => _work;
  int get currentIndex => _currentIndex;
  String? get error => _error;
  bool get hasQueue => _queue.isNotEmpty;
  bool get playing => _player.playing;
  bool get hasNext => _relativeIndex(1) != null;
  bool get hasPrevious => _relativeIndex(-1) != null;
  double get speed => _player.speed;
  bool get shuffleEnabled => _player.shuffleModeEnabled;
  ja.LoopMode get loopMode => _loopMode;

  List<int> get _playOrder => !shuffleEnabled
      ? List.generate(_queue.length, (index) => index)
      : _singleSource
      ? _singleShuffleOrder
      : _player.effectiveIndices;

  int? _relativeIndex(int offset) {
    final order = _playOrder;
    final current = order.indexOf(_currentIndex);
    if (current < 0 || order.isEmpty) return null;
    var next = current + offset;
    if (next < 0 || next >= order.length) {
      if (_loopMode != ja.LoopMode.all) return null;
      next %= order.length;
    }
    return order[next];
  }

  void _shuffleSingleQueue(int index) {
    _singleShuffleOrder = List.generate(_queue.length, (i) => i)..shuffle();
    _singleShuffleOrder
      ..remove(index)
      ..insert(0, index);
  }

  PlayItem? get currentItem =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
      ? _queue[_currentIndex]
      : null;

  DateTime? get sleepDeadline => _sleepDeadline;

  Duration get sleepRemaining {
    final d = _sleepDeadline;
    if (d == null) return Duration.zero;
    final left = d.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  // ---------------------------------------------------------------------------
  // 事件绑定
  // ---------------------------------------------------------------------------

  void _bind() {
    _subscriptions.add(
      _player.currentIndexStream.listen((index) {
        if (index == null || _singleSource || _changingSources) return;
        _currentIndex = index;
        _setActivePlayingCacheKey(_queueCacheKeys[index]);
        clearAbLoop();
        _onItemChanged();
      }),
    );
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        if (!_changingSources &&
            hasQueue &&
            state.processingState == ja.ProcessingState.completed) {
          if (!_settings.autoPlayNext || _stopAfterTrack) {
            _player.pause();
            _player.seek(Duration.zero, index: 0);
          } else if (_player.loopMode == ja.LoopMode.off) {
            // 队列播完，回到开头并暂停。
            _player.pause();
            _player.seek(Duration.zero, index: _playOrder.first);
          }
        }
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.errorStream.listen((e) {
        _error = '播放失败：${e.message ?? e.code}';
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        if (_loopStart != null &&
            _loopEnd != null &&
            position >= _loopEnd! &&
            !_loopSeeking &&
            playing) {
          _loopSeeking = true;
          _player.seek(_loopStart!).whenComplete(() => _loopSeeking = false);
        }
      }),
    );
    // 每 5 秒保存一次收听进度，用于「继续播放」。
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.playing) _saveProgress().ignore();
    });
  }

  Future<void> _onItemChanged() async {
    final item = currentItem;
    if (item == null) return;
    notifyListeners();
    await _applyAccent(item.coverUrl);
  }

  void _settingsChanged() {
    final autoPlayChanged = _autoPlayNext != _settings.autoPlayNext;
    final cacheToggleChanged =
        _streamCacheEnabled != _settings.streamCacheEnabled;
    if (!autoPlayChanged && !cacheToggleChanged) return;
    _autoPlayNext = _settings.autoPlayNext;
    _streamCacheEnabled = _settings.streamCacheEnabled;
    if (_queue.isEmpty) return;
    if (cacheToggleChanged && _audioCache != null) {
      final buildingGroup = _buildingRouteGroupId;
      if (buildingGroup != null) {
        _audioCache.releaseRouteGroup(buildingGroup);
      }
    }
    if (autoPlayChanged) {
      unawaited(_reloadPlaybackMode(resetPlatform: cacheToggleChanged));
    } else if (cacheToggleChanged && _audioCache != null) {
      final hasOnlineItem = _queue.any(
        (item) => !item.isLocal && item.url.isNotEmpty,
      );
      if (_hasAppliedOrPendingCacheRoutes ||
          (_streamCacheEnabled && hasOnlineItem)) {
        unawaited(_reloadPlaybackMode(resetPlatform: true));
      }
    }
  }

  Future<void> _reloadPlaybackMode({bool resetPlatform = false}) async {
    // 连续重建期间沿用用户最近一次主动选择的播放意图与进度，避免前一次 stop() 将播放态误判为暂停。
    _resumeAfterReload ??= playing;
    _reloadPosition ??= _player.position;
    final resumePosition = _reloadPosition!;
    try {
      final loaded = await _setSources(
        _queue,
        _currentIndex,
        resumePosition,
        resetPlatform: resetPlatform,
      );
      if (loaded) {
        final shouldResume = _resumeAfterReload ?? false;
        _resumeAfterReload = null;
        _reloadPosition = null;
        if (shouldResume && !_player.playing) unawaited(_player.play());
      }
    } catch (e) {
      if (!_changingSources) {
        _resumeAfterReload = null;
        _reloadPosition = null;
        _pendingSeekPosition = null;
      }
      _error = '更新播放模式失败：$e';
    }
    notifyListeners();
  }

  // 关闭自动下一首时只向底层提交当前曲目，保留应用内完整队列。
  Future<bool> _setSources(
    List<PlayItem> items,
    int index,
    Duration position, {
    bool resetPlatform = false,
    bool preload = true,
  }) {
    final future = _setSourcesImpl(
      items,
      index,
      position,
      resetPlatform: resetPlatform,
      preload: preload,
    );
    final settled = future.then<void>((_) {}, onError: (Object _) {});
    _inFlightSourceUpdate = settled;
    unawaited(
      settled.whenComplete(() {
        if (identical(_inFlightSourceUpdate, settled)) {
          _inFlightSourceUpdate = null;
        }
      }),
    );
    return future;
  }

  Future<bool> _setSourcesImpl(
    List<PlayItem> items,
    int index,
    Duration position, {
    bool resetPlatform = false,
    bool preload = true,
  }) async {
    final version = ++_sourceVersion;
    _changingSources = true;
    _lastSourceUpdateOk = false;
    _lastSourceUpdatePreloaded = preload;
    _singleSource = !_settings.autoPlayNext || _stopAfterTrack;
    if (_singleSource && _singleShuffleOrder.length != items.length) {
      _shuffleSingleQueue(index);
    }
    _currentIndex = index;
    final cacheScope = _desiredCacheScope();
    final nextRouteGroup = cacheScope != null
        ? _audioCache?.createRouteGroup()
        : null;
    final prevBuildingGroup = _buildingRouteGroupId;
    _buildingRouteGroupId = nextRouteGroup;
    _buildingCacheScope = cacheScope;
    if (prevBuildingGroup != null && prevBuildingGroup != nextRouteGroup) {
      _audioCache?.releaseRouteGroup(prevBuildingGroup);
    }
    var needsRetry = false;
    try {
      if (resetPlatform) {
        await _player.stop();
        if (version != _sourceVersion) {
          _audioCache?.releaseRouteGroup(nextRouteGroup);
          return false;
        }
        // 账号/缓存配置重置时立即撤销旧代理路由，避免旧路由在重建期间继续写入旧账号缓存。
        final staleRouteGroup = _activeRouteGroupId;
        _activeRouteGroupId = null;
        _setActivePlayingCacheKey(null);
        _audioCache?.releaseRouteGroup(staleRouteGroup);
      }
      await _player.setLoopMode(
        _stopAfterTrack || (_singleSource && _loopMode == ja.LoopMode.all)
            ? ja.LoopMode.off
            : _loopMode,
      );
      if (version != _sourceVersion) {
        _audioCache?.releaseRouteGroup(nextRouteGroup);
        return false;
      }
      final ids = _mediaIds(items);
      final token = _api.token ?? '';
      final targetIndices = _singleSource
          ? [index]
          : List.generate(items.length, (i) => i);
      final nextQueueCacheKeys = <int, String>{};
      final sources = <ja.UriAudioSource>[];
      var hasApiMedia = false;
      for (final i in targetIndices) {
        final item = items[i];
        if (!item.isLocal && item.url.isNotEmpty) {
          final parsed = Uri.tryParse(item.url);
          if (parsed != null && _isApiMedia(parsed)) hasApiMedia = true;
        }
        sources.add(
          await _resolveSource(
            item,
            ids[i],
            token,
            cacheScope: cacheScope,
            routeGroup: nextRouteGroup,
            onCacheKey: (keyId) => nextQueueCacheKeys[i] = keyId,
          ),
        );
        if (version != _sourceVersion) {
          _audioCache?.releaseRouteGroup(nextRouteGroup);
          return false;
        }
      }
      // 安装音源前复核当前配置，避免在途创建期间开关或账号变更导致旧路由装入播放器。
      if (_desiredCacheScope() != cacheScope ||
          (hasApiMedia && (_api.token ?? '') != token)) {
        _audioCache?.releaseRouteGroup(nextRouteGroup);
        if (version == _sourceVersion) {
          needsRetry = true;
        } else {
          return false;
        }
      }
      if (!needsRetry) {
        final nextMediaToken = hasApiMedia ? token : null;
        final initialTargetPosition = _pendingSeekPosition ?? position;
        await _player.setAudioSources(
          sources,
          preload: preload,
          initialIndex: _singleSource ? 0 : index,
          initialPosition: initialTargetPosition,
        );
        if (version != _sourceVersion) {
          _audioCache?.releaseRouteGroup(nextRouteGroup);
          return false;
        }
        // 重建期间若用户继续拖动进度，装源完成后立即同步到最后一次目标位置。
        var appliedPosition = initialTargetPosition;
        while (_pendingSeekPosition != null &&
            _pendingSeekPosition != appliedPosition) {
          final seekTarget = _pendingSeekPosition!;
          await _player.seek(seekTarget);
          if (version != _sourceVersion) {
            _audioCache?.releaseRouteGroup(nextRouteGroup);
            return false;
          }
          appliedPosition = seekTarget;
        }
        if (version == _sourceVersion) {
          _pendingSeekPosition = null;
        }
        final hasCachedRoutes = nextQueueCacheKeys.isNotEmpty;
        if (!hasCachedRoutes && nextRouteGroup != null) {
          _audioCache?.releaseRouteGroup(nextRouteGroup);
        }
        final prevRouteGroup = _activeRouteGroupId;
        _activeRouteGroupId = hasCachedRoutes ? nextRouteGroup : null;
        _queueCacheKeys = nextQueueCacheKeys;
        _setActivePlayingCacheKey(_queueCacheKeys[index]);
        _audioCache?.releaseRouteGroup(prevRouteGroup);
        _appliedMediaToken = nextMediaToken;
        _appliedCacheScope = hasCachedRoutes ? cacheScope : null;
        _lastSourceUpdateOk = true;
      }
    } catch (_) {
      _audioCache?.releaseRouteGroup(nextRouteGroup);
      if (version == _sourceVersion) rethrow;
      return false;
    } finally {
      if (version == _sourceVersion) {
        _changingSources = false;
        if (_buildingRouteGroupId == nextRouteGroup) {
          _buildingRouteGroupId = null;
        }
        _buildingCacheScope = null;
      }
    }
    if (needsRetry) {
      return _setSources(
        items,
        index,
        position,
        resetPlatform: resetPlatform,
        preload: preload,
      );
    }
    unawaited(_onItemChanged());
    return true;
  }

  Future<void> _saveProgress() {
    final session = _persistSession();
    final item = currentItem;
    final hash = item?.hash;
    if (item == null || hash == null || hash.isEmpty) return session;
    final pos = _player.position.inMilliseconds;
    final dur = (_player.duration?.inMilliseconds) ?? 0;
    if (dur <= 0 || pos < 3000) return session;
    _library.saveProgress(
      hash: hash,
      workId: item.workId,
      positionMs: pos,
      durationMs: dur,
    );
    return session;
  }

  /// 从封面提取主色并交给设置状态作为动态强调色。
  Future<void> _applyAccent(String coverUrl) async {
    if (!_settings.useCoverAccent) return;
    if (coverUrl.isEmpty || _accentSourceUrl == coverUrl) return;
    _accentSourceUrl = coverUrl;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(coverUrl),
        size: const Size(96, 96),
        maximumColorCount: 12,
      );
      final color =
          palette.vibrantColor?.color ??
          palette.darkVibrantColor?.color ??
          palette.dominantColor?.color;
      if (color != null) _settings.setDynamicAccent(color);
    } catch (_) {
      // 取色失败不影响播放。
    }
  }

  // ---------------------------------------------------------------------------
  // 播放控制
  // ---------------------------------------------------------------------------

  /// 播放某个作品的曲目。
  ///
  /// 返回实际入队的曲目数量；`unplayable` 为无法解析出地址的曲目数量
  /// （通常是付费内容且未登录）。
  Future<({int queued, int unplayable})> playWork(
    Work work,
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) async {
    final cover = _api.coverUrl(work.id, type: 'main');
    // 优先使用本地已下载文件。
    final localPaths = await _library.downloadedPaths(work.id);

    final items = <PlayItem>[];
    var unplayable = 0;
    var selectedIndex = 0;
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      final hash = t.hash;
      final downloaded = hash == null ? null : localPaths[hash];
      final useLocal = downloaded != null && downloaded.isNotEmpty;
      final target = useLocal
          ? null
          : _api.resolveStreamTarget(
              t.node,
              preferLowQuality: _settings.preferLowQuality,
            );
      final local = useLocal ? downloaded : null;
      final url = target?.url;
      if (local == null && url == null) {
        unplayable++;
        continue;
      }
      if (i < startIndex) selectedIndex++;
      items.add(
        PlayItem(
          workId: work.id,
          workTitle: work.title,
          title: t.title,
          hash: hash,
          url: _queueUrl(url),
          localPath: local,
          lowQuality: !useLocal && (target?.lowQuality ?? false),
          coverUrl: cover,
          circleName: work.circleName,
          folderLabel: t.folderLabel,
          duration: t.hasDuration
              ? Duration(seconds: t.duration.round())
              : null,
        ),
      );
    }

    if (items.isEmpty) {
      _error = unplayable > 0 ? '该作品的音频需要登录后才能播放。' : '没有可播放的曲目。';
      notifyListeners();
      return (queued: 0, unplayable: unplayable);
    }

    final index = selectedIndex.clamp(0, items.length - 1);
    _work = work;
    if (!await _load(items, index: index, shuffle: shuffle, autoPlay: true)) {
      return (queued: 0, unplayable: unplayable);
    }
    await _library.recordHistory(work);
    if (_consumeLoadAutoPlay() && !_player.playing) {
      unawaited(_player.play());
    }
    notifyListeners();
    return (queued: items.length, unplayable: unplayable);
  }

  /// 直接播放已下载到本地的音频（无需网络）。
  ///
  /// [hashToPath] 为 `曲目 hash -> 本地文件路径`。返回是否成功入队。
  Future<bool> playLocalFiles(
    Work work,
    Map<String, String> hashToPath, {
    List<DownloadRow> metadata = const [],
  }) async {
    if (hashToPath.isEmpty) {
      _error = '没有找到本地文件。';
      notifyListeners();
      return false;
    }
    final cover = _api.coverUrl(work.id, type: 'main');
    final byHash = {for (final row in metadata) row.hash: row};
    final ordered = hashToPath.entries.toList()
      ..sort((a, b) {
        final left = byHash[a.key];
        final right = byHash[b.key];
        final order = (left?.trackIndex ?? 0).compareTo(right?.trackIndex ?? 0);
        return order != 0
            ? order
            : (left?.title ?? p.basename(a.value)).compareTo(
                right?.title ?? p.basename(b.value),
              );
      });
    final items = ordered
        .map(
          (e) => PlayItem(
            workId: work.id,
            workTitle: work.title,
            title: byHash[e.key]?.title ?? p.basename(e.value),
            folderLabel: byHash[e.key]?.folderLabel ?? '',
            duration: byHash[e.key] == null
                ? null
                : Duration(
                    milliseconds: (byHash[e.key]!.duration * 1000).round(),
                  ),
            hash: e.key,
            url: '',
            localPath: e.value,
            coverUrl: cover,
            circleName: work.circleName,
          ),
        )
        .toList();

    _work = work;
    if (!await _load(items, autoPlay: true)) return false;
    await _library.recordHistory(work);
    if (_consumeLoadAutoPlay() && !_player.playing) {
      unawaited(_player.play());
    }
    notifyListeners();
    return true;
  }

  /// 播放单曲（例如曲目列表里的「播放这一首」）。
  Future<void> playSingle(Work work, AudioTrack track) async {
    final cover = _api.coverUrl(work.id, type: 'main');
    final localPaths = await _library.downloadedPaths(work.id);
    final hash = track.hash;
    final downloaded = hash == null ? null : localPaths[hash];
    final useLocal = downloaded != null && downloaded.isNotEmpty;
    final target = useLocal
        ? null
        : _api.resolveStreamTarget(
            track.node,
            preferLowQuality: _settings.preferLowQuality,
          );
    final local = useLocal ? downloaded : null;
    final url = target?.url;
    if (local == null && url == null) {
      _error = '无法解析该曲目的播放地址，可能需要登录。';
      notifyListeners();
      return;
    }
    final item = PlayItem(
      workId: work.id,
      workTitle: work.title,
      title: track.title,
      hash: hash,
      url: _queueUrl(url),
      localPath: local,
      lowQuality: !useLocal && (target?.lowQuality ?? false),
      coverUrl: cover,
      circleName: work.circleName,
      folderLabel: track.folderLabel,
      duration: track.hasDuration
          ? Duration(seconds: track.duration.round())
          : null,
    );
    _work = work;
    if (!await _load([item], autoPlay: true)) return;
    await _library.recordHistory(work);
    if (_consumeLoadAutoPlay() && !_player.playing) {
      unawaited(_player.play());
    }
    notifyListeners();
  }

  bool _consumeLoadAutoPlay() {
    final allowed = _autoPlayAllowedForLoad && _lastSourceUpdatePreloaded;
    _autoPlayAllowedForLoad = false;
    return allowed;
  }

  Future<bool> _load(
    List<PlayItem> items, {
    int index = 0,
    bool shuffle = false,
    Duration? initialPosition,
    bool autoPlay = false,
  }) async {
    final version = ++_loadVersion;
    _autoPlayAllowedForLoad = autoPlay;
    _resumeAfterReload = autoPlay ? true : null;
    _reloadPosition = null;
    _pendingSeekPosition = null;
    clearAbLoop();
    _saveProgress().ignore();
    _error = null;
    _queue = items;
    _singleShuffleOrder = [];
    _currentIndex = index;
    notifyListeners();

    try {
      final item = items[index];
      final saved = item.hash == null
          ? 0
          : await _library.progressFor(item.hash!);
      final duration = item.duration?.inMilliseconds;
      final resume =
          initialPosition ??
          (saved > 0 && (duration == null || saved < duration - 3000)
              ? Duration(milliseconds: saved)
              : Duration.zero);
      if (version != _loadVersion) return false;
      _reloadPosition ??= resume;
      var loaded = await _setSources(items, index, resume);
      // 若本次建源被同队列的配置重建（如切换缓存或退登）接替，等待接替建源结束并沿用其结果。
      if (!loaded && version == _loadVersion) {
        while (_inFlightSourceUpdate != null && version == _loadVersion) {
          await _inFlightSourceUpdate;
        }
        if (version != _loadVersion) return false;
        loaded = _lastSourceUpdateOk;
      }
      if (!loaded || version != _loadVersion) return false;
      if (!_changingSources) {
        _resumeAfterReload = null;
        _reloadPosition = null;
        _pendingSeekPosition = null;
      }
      if (resume > Duration.zero &&
          _player.position == resume &&
          _player.duration != null &&
          resume >= _player.duration! - const Duration(seconds: 3)) {
        await _player.seek(Duration.zero);
      }
      await _player.setSpeed(_settings.playbackSpeed);
      await _player.setShuffleModeEnabled(shuffle);
      if (shuffle) await _player.shuffle();
      await _persistSession();
      return true;
    } catch (e) {
      if (version != _loadVersion) return false;
      _autoPlayAllowedForLoad = false;
      if (!_changingSources) {
        _resumeAfterReload = null;
        _reloadPosition = null;
        _pendingSeekPosition = null;
      }
      _error = '加载音频失败：$e';
      await _player.stop();
      notifyListeners();
      return false;
    }
  }

  List<String> _mediaIds(List<PlayItem> items) {
    final seen = <String>{};
    return [
      for (var i = 0; i < items.length; i++)
        _uniqueMediaId(items[i], i, seen),
    ];
  }

  String _uniqueMediaId(PlayItem item, int index, Set<String> seen) {
    final hash = item.hash;
    final base = (hash != null && hash.isNotEmpty)
        ? 'work:${item.workId}:hash:$hash'
        : 'work:${item.workId}:track:$index';
    if (seen.add(base)) return base;
    final unique = '$base#$index';
    seen.add(unique);
    return unique;
  }

  String? _currentAccountScope() =>
      _accountScope != null ? _accountScope() : (_api.hasToken ? null : 'guest');

  String? _desiredCacheScope() =>
      (_settings.streamCacheEnabled && _audioCache != null)
      ? _currentAccountScope()
      : null;

  bool get _hasAppliedOrPendingCacheRoutes =>
      _queueCacheKeys.isNotEmpty ||
      _activeRouteGroupId != null ||
      _appliedCacheScope != null ||
      _buildingRouteGroupId != null ||
      _buildingCacheScope != null;

  String? get _effectiveCacheScope => _buildingCacheScope ?? _appliedCacheScope;

  void _setActivePlayingCacheKey(String? nextKey) {
    final cache = _audioCache;
    if (cache == null || _activePlayingCacheKey == nextKey) return;
    final prev = _activePlayingCacheKey;
    _activePlayingCacheKey = nextKey;
    if (nextKey != null) cache.markActive(nextKey);
    if (prev != null) cache.releaseActive(prev);
  }

  void _releaseAllActiveCacheKeys() {
    _setActivePlayingCacheKey(null);
    final prevGroup = _activeRouteGroupId;
    final buildingGroup = _buildingRouteGroupId;
    _activeRouteGroupId = null;
    _buildingRouteGroupId = null;
    _queueCacheKeys = const {};
    _appliedCacheScope = null;
    _buildingCacheScope = null;
    _audioCache?.releaseRouteGroup(prevGroup);
    if (buildingGroup != prevGroup) {
      _audioCache?.releaseRouteGroup(buildingGroup);
    }
  }

  Future<ja.UriAudioSource> _resolveSource(
    PlayItem item,
    String mediaId,
    String token, {
    required String? cacheScope,
    required String? routeGroup,
    required void Function(String keyId) onCacheKey,
  }) async {
    Uri uri;
    if (item.isLocal) {
      uri = Uri.file(item.localPath!);
    } else {
      var remoteUri = Uri.parse(item.url);
      if (_isApiMedia(remoteUri)) {
        remoteUri = remoteUri.replace(
          queryParameters: {...remoteUri.queryParameters, 'token': token},
        );
      }
      uri = remoteUri;
      final cache = _audioCache;
      // 账号身份尚未确认（cacheScope == null）时跳过账号缓存读写，避免跨账号碰撞。
      if (_settings.streamCacheEnabled &&
          cache != null &&
          cacheScope != null &&
          item.url.isNotEmpty) {
        final trackId = (item.hash != null && item.hash!.isNotEmpty)
            ? item.hash!
            : '${item.folderLabel}/${item.title}';
        final key = AudioCacheKey(
          accountScope: cacheScope,
          workId: item.workId,
          trackId: trackId,
          lowQuality: item.lowQuality,
        );
        final resolved = await cache.resolvePlayableUri(
          key: key,
          remoteUri: remoteUri,
          headers: const {'Referer': '${ApiClient.siteUrl}/'},
          routeGroup: routeGroup,
        );
        if (resolved != null) {
          uri = resolved;
          onCacheKey(key.id);
        }
      }
    }
    return ja.AudioSource.uri(
      uri,
      tag: MediaItem(
        id: mediaId,
        title: item.title,
        album: item.workTitle,
        artist: item.circleName.isEmpty ? null : item.circleName,
        duration: item.duration,
        artUri: item.coverUrl.isEmpty ? null : Uri.parse(item.coverUrl),
      ),
    );
  }

  /// 重新设定当前作品（用于最近播放列表恢复队列时补充元数据）。
  void attachWork(Work work) {
    _work = work;
    notifyListeners();
  }

  Future<void> toggle() async {
    final currentlyPlaying = _changingSources
        ? (_resumeAfterReload ?? _player.playing)
        : _player.playing;
    if (currentlyPlaying) {
      _autoPlayAllowedForLoad = false;
      if (_changingSources) _resumeAfterReload = false;
      await _player.pause();
      await _saveProgress();
    } else {
      if (_changingSources) _resumeAfterReload = true;
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> pause() async {
    _autoPlayAllowedForLoad = false;
    if (_changingSources) _resumeAfterReload = false;
    await _player.pause();
    await _saveProgress();
    notifyListeners();
  }

  Future<void> next() async {
    final index = _relativeIndex(1);
    if (index == null) return;
    await seekToIndex(index);
  }

  Future<void> previous() async {
    // 播放超过 3 秒时先回到本曲开头。
    if (_player.position.inSeconds > 3 || !hasPrevious) {
      await seek(Duration.zero);
      return;
    }
    await seekToIndex(_relativeIndex(-1)!);
  }

  Future<void> seek(Duration position) {
    if (_changingSources) {
      _reloadPosition = position;
      _pendingSeekPosition = position;
    }
    return _player.seek(position);
  }

  Future<void> seekToIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _resumeAfterReload = null;
    _reloadPosition = null;
    _pendingSeekPosition = null;
    _saveProgress().ignore();
    if (index != _currentIndex) clearAbLoop();
    if (_singleSource) {
      if (!await _setSources(_queue, index, Duration.zero)) return;
    } else {
      await _player.seek(Duration.zero, index: index);
    }
    unawaited(_player.play());
  }

  Future<void> setSpeed(double value) async {
    await _player.setSpeed(value);
    _settings.playbackSpeed = value;
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    final enable = !_player.shuffleModeEnabled;
    await _player.setShuffleModeEnabled(enable);
    if (enable) {
      await _player.shuffle();
      if (_singleSource) _shuffleSingleQueue(_currentIndex);
    }
    notifyListeners();
  }

  Future<void> cycleLoopMode() async {
    final next = switch (_loopMode) {
      ja.LoopMode.off => ja.LoopMode.all,
      ja.LoopMode.all => ja.LoopMode.one,
      ja.LoopMode.one => ja.LoopMode.off,
    };
    _loopMode = next;
    await _player.setLoopMode(
      _stopAfterTrack || (_singleSource && next == ja.LoopMode.all)
          ? ja.LoopMode.off
          : next,
    );
    notifyListeners();
  }

  Future<void> stop() async {
    _loadVersion++;
    final version = ++_sourceVersion;
    _changingSources = false;
    _autoPlayAllowedForLoad = false;
    _resumeAfterReload = null;
    _reloadPosition = null;
    _pendingSeekPosition = null;
    _saveProgress().ignore();
    _queue = const [];
    _currentIndex = -1;
    _work = null;
    _appliedMediaToken = null;
    _releaseAllActiveCacheKeys();
    clearSleepTimer();
    _stopAfterTrack = false;
    clearAbLoop();
    await _player.stop();
    if (version != _sourceVersion) return;
    await _player.setAudioSources(const [], preload: false);
    await _persistSession();
    notifyListeners();
  }

  /// 移除队列中的某一首；当前播放项之前的位置会被顺移。
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final next = [..._queue]..removeAt(index);
    if (next.isEmpty) {
      await stop();
      return;
    }
    final wasCurrent = index == _currentIndex;
    final resumeIndex = wasCurrent
        ? index.clamp(0, next.length - 1)
        : (index < _currentIndex ? _currentIndex - 1 : _currentIndex);
    final wasPlaying = _player.playing;
    final position = wasCurrent ? Duration.zero : _player.position;
    _queue = next;
    try {
      if (!await _setSources(next, resumeIndex, position)) return;
      await _persistSession();
      if (wasPlaying) await _player.play();
    } catch (e) {
      _error = '更新队列失败：$e';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 定时关闭
  // ---------------------------------------------------------------------------

  void setSleepTimer(int minutes, {bool fade = true}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;
    _fadeSleep = fade;
    final previousVolume = _sleepVolume;
    if (previousVolume != null) unawaited(_player.setVolume(previousVolume));
    _sleepVolume = null;
    if (_stopAfterTrack) {
      _stopAfterTrack = false;
      if (hasQueue) unawaited(_reloadPlaybackMode());
    }
    _settings.sleepMinutes = minutes;
    if (minutes <= 0) {
      notifyListeners();
      return;
    }
    _sleepDeadline = _now().add(Duration(minutes: minutes));
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final remaining = sleepRemaining;
      if (remaining == Duration.zero) {
        _sleepTimer?.cancel();
        await pause();
        clearSleepTimer();
      } else if (_fadeSleep && remaining <= const Duration(seconds: 30)) {
        _sleepVolume ??= _player.volume;
        await _player.setVolume(
          _sleepVolume! * remaining.inMilliseconds / 30000,
        );
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void clearSleepTimer() => setSleepTimer(0);

  /// 账号令牌或缓存账号身份变更后撤下旧媒体源，并用当前身份重新配置音频引擎。
  Future<void> refreshTokens() async {
    if (_disposed) return;
    while (!_disposed) {
      final token = _api.token ?? '';
      final item = currentItem;
      if (item == null) return;
      final tokenChanged =
          _appliedMediaToken != null && _appliedMediaToken != token;
      final desiredCacheScope = _desiredCacheScope();
      final hasOnlineItem = _queue.any((e) => !e.isLocal && e.url.isNotEmpty);
      final scopeChanged =
          _audioCache != null &&
          (_hasAppliedOrPendingCacheRoutes
              ? _effectiveCacheScope != desiredCacheScope
              : (desiredCacheScope != null && hasOnlineItem));
      if (!tokenChanged && !scopeChanged) {
        final pending = _inFlightSourceUpdate;
        if (pending != null) {
          await pending;
          continue;
        }
        return;
      }
      final buildingGroup = _buildingRouteGroupId;
      if (buildingGroup != null) {
        _audioCache?.releaseRouteGroup(buildingGroup);
      }
      final uri = item.isLocal ? null : Uri.tryParse(item.url);
      final preload = token.isNotEmpty || uri == null || !_isApiMedia(uri);
      _resumeAfterReload ??= playing;
      _reloadPosition ??= _player.position;
      final resumePosition = _reloadPosition!;
      try {
        final loaded = await _setSources(
          _queue,
          _currentIndex,
          resumePosition,
          resetPlatform: true,
          preload: preload,
        );
        if (loaded) {
          _error = null;
          final shouldResume = _resumeAfterReload ?? false;
          _resumeAfterReload = null;
          _reloadPosition = null;
          if (shouldResume && preload && !_player.playing) {
            unawaited(_player.play());
          }
        }
      } catch (_) {
        if (!_changingSources) {
          _resumeAfterReload = null;
          _reloadPosition = null;
          _pendingSeekPosition = null;
        }
        _error = '更新播放地址失败，请重试。';
      }
      notifyListeners();
      return;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _settings.removeListener(_settingsChanged);
    _sleepTimer?.cancel();
    _progressTimer?.cancel();
    _releaseAllActiveCacheKeys();
    _saveProgress().ignore();
    _player.dispose();
    super.dispose();
  }
}
