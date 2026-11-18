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

  bool get isLocal => (localPath ?? '').isNotEmpty;
}

/// 播放器状态：队列管理、进度、倍速、定时关闭、封面取色。
class PlayerState extends ChangeNotifier {
  PlayerState({
    required SettingsState settings,
    required LibraryState library,
    ja.AudioPlayer? audioPlayer,
    ApiClient? api,
    this.readSession,
    this.writeSession,
    DateTime Function()? now,
  }) : _settings = settings,
       _now = now ?? DateTime.now,
       _library = library,
       _api = api ?? ApiClient.instance,
       _player = audioPlayer ?? ja.AudioPlayer() {
    _autoPlayNext = settings.autoPlayNext;
    _settings.addListener(_settingsChanged);
    _player.setSpeed(settings.playbackSpeed);
    _bind();
  }

  final SettingsState _settings;
  final LibraryState _library;
  final ApiClient _api;

  final ja.AudioPlayer _player;
  final DateTime Function() _now;
  final Future<Object?> Function()? readSession;
  final Future<void> Function(Object?)? writeSession;
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
    if (_restoring || writeSession == null) return;
    if (_queue.isEmpty) {
      await writeSession!(null);
      return;
    }
    await writeSession!({
      'index': _currentIndex,
      'position': _player.position.inMilliseconds,
      'shuffle': _player.shuffleModeEnabled,
      'loop': _loopMode.index,
      'items': [
        for (final item in _queue)
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
          },
      ],
    });
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
    final saved = await readSession!();
    if (saved is! Map ||
        saved['items'] is! List ||
        hasQueue ||
        version != _loadVersion) {
      return;
    }
    _restoring = true;
    try {
      final items = <PlayItem>[];
      var index = 0;
      var selectedExists = false;
      final savedIndex = saved['index'] as int? ?? 0;
      var sourceIndex = 0;
      for (final raw in saved['items'] as List) {
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
      await _load(
        items,
        index: index,
        shuffle: saved['shuffle'] == true,
        initialPosition: Duration(
          milliseconds: selectedExists
              ? (saved['position'] as int? ?? 0).clamp(0, 1 << 40)
              : 0,
        ),
      );
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
      if (_player.playing) _saveProgress();
    });
  }

  Future<void> _onItemChanged() async {
    final item = currentItem;
    if (item == null) return;
    notifyListeners();
    await _applyAccent(item.coverUrl);
  }

  void _settingsChanged() {
    if (_autoPlayNext == _settings.autoPlayNext) return;
    _autoPlayNext = _settings.autoPlayNext;
    if (_queue.isNotEmpty) unawaited(_reloadPlaybackMode());
  }

  Future<void> _reloadPlaybackMode() async {
    final wasPlaying = playing;
    try {
      final loaded = await _setSources(_queue, _currentIndex, _player.position);
      if (loaded && wasPlaying) unawaited(_player.play());
    } catch (e) {
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
  }) async {
    final version = ++_sourceVersion;
    _changingSources = true;
    _singleSource = !_settings.autoPlayNext || _stopAfterTrack;
    if (_singleSource && _singleShuffleOrder.length != items.length) {
      _shuffleSingleQueue(index);
    }
    _currentIndex = index;
    try {
      if (resetPlatform) {
        await _player.stop();
        if (version != _sourceVersion) return false;
      }
      await _player.setLoopMode(
        _stopAfterTrack || (_singleSource && _loopMode == ja.LoopMode.all)
            ? ja.LoopMode.off
            : _loopMode,
      );
      if (version != _sourceVersion) return false;
      final ids = _mediaIds(items);
      final token = _api.token ?? '';
      final sources = _singleSource
          ? [_toSource(items[index], ids[index], token)]
          : [
              for (var i = 0; i < items.length; i++)
                _toSource(items[i], ids[i], token),
            ];
      _appliedMediaToken = sources.any((source) => _isApiMedia(source.uri))
          ? token
          : null;
      await _player.setAudioSources(
        sources,
        preload: preload,
        initialIndex: _singleSource ? 0 : index,
        initialPosition: position,
      );
    } catch (_) {
      if (version == _sourceVersion) rethrow;
      return false;
    } finally {
      if (version == _sourceVersion) _changingSources = false;
    }
    if (version != _sourceVersion) return false;
    unawaited(_onItemChanged());
    return true;
  }

  void _saveProgress() {
    unawaited(_persistSession());
    final item = currentItem;
    if (item == null) return;
    final hash = item.hash;
    if (hash == null || hash.isEmpty) return;
    final pos = _player.position.inMilliseconds;
    final dur = (_player.duration?.inMilliseconds) ?? 0;
    if (dur <= 0 || pos < 3000) return;
    _library.saveProgress(
      hash: hash,
      workId: item.workId,
      positionMs: pos,
      durationMs: dur,
    );
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
      final local = hash == null ? null : localPaths[hash];
      final url = (local != null && local.isNotEmpty)
          ? null
          : _api.resolveStreamUrl(
              t.node,
              preferLowQuality: _settings.preferLowQuality,
            );
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
    if (!await _load(items, index: index, shuffle: shuffle)) {
      return (queued: 0, unplayable: unplayable);
    }
    await _library.recordHistory(work);
    _player.play();
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
    if (!await _load(items)) return false;
    await _library.recordHistory(work);
    unawaited(_player.play());
    notifyListeners();
    return true;
  }

  /// 播放单曲（例如曲目列表里的「播放这一首」）。
  Future<void> playSingle(Work work, AudioTrack track) async {
    final cover = _api.coverUrl(work.id, type: 'main');
    final localPaths = await _library.downloadedPaths(work.id);
    final hash = track.hash;
    final local = hash == null ? null : localPaths[hash];
    final url = (local != null && local.isNotEmpty)
        ? null
        : _api.resolveStreamUrl(
            track.node,
            preferLowQuality: _settings.preferLowQuality,
          );
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
      coverUrl: cover,
      circleName: work.circleName,
      folderLabel: track.folderLabel,
      duration: track.hasDuration
          ? Duration(seconds: track.duration.round())
          : null,
    );
    _work = work;
    if (!await _load([item])) return;
    await _library.recordHistory(work);
    _player.play();
    notifyListeners();
  }

  Future<bool> _load(
    List<PlayItem> items, {
    int index = 0,
    bool shuffle = false,
    Duration? initialPosition,
  }) async {
    final version = ++_loadVersion;
    clearAbLoop();
    _saveProgress();
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
      final loaded = await _setSources(items, index, resume);
      if (!loaded || version != _loadVersion) return false;
      if (resume > Duration.zero &&
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

  ja.UriAudioSource _toSource(PlayItem item, String mediaId, String token) {
    var uri = item.isLocal ? Uri.file(item.localPath!) : Uri.parse(item.url);
    if (_isApiMedia(uri)) {
      uri = uri.replace(
        queryParameters: {...uri.queryParameters, 'token': token},
      );
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
    if (_player.playing) {
      await _player.pause();
      _saveProgress();
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> pause() async {
    await _player.pause();
    _saveProgress();
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
      await _player.seek(Duration.zero);
      return;
    }
    await seekToIndex(_relativeIndex(-1)!);
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> seekToIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _saveProgress();
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
    _saveProgress();
    _queue = const [];
    _currentIndex = -1;
    _work = null;
    _appliedMediaToken = null;
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

  /// 账号令牌变更后撤下旧媒体源，并用当前令牌重新配置音频引擎。
  Future<void> refreshTokens() async {
    final token = _api.token ?? '';
    final item = currentItem;
    if (_disposed ||
        item == null ||
        _appliedMediaToken == null ||
        _appliedMediaToken == token) {
      return;
    }
    final uri = item.isLocal ? null : Uri.tryParse(item.url);
    final preload = token.isNotEmpty || uri == null || !_isApiMedia(uri);
    final wasPlaying = playing;
    try {
      final loaded = await _setSources(
        _queue,
        _currentIndex,
        _player.position,
        resetPlatform: true,
        preload: preload,
      );
      if (loaded && wasPlaying && preload) unawaited(_player.play());
    } catch (_) {
      _error = '更新播放地址失败，请重试。';
    }
    notifyListeners();
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
    _saveProgress();
    _player.dispose();
    super.dispose();
  }
}
