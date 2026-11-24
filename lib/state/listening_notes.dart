// 命名参数无法使用私有初始化形参（`this._settings`），此处显式赋值。
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/api/api_client.dart';
import '../core/models/subtitle.dart';
import '../core/models/subtitle_matcher.dart';
import '../core/models/track.dart';
import 'library_state.dart';
import 'player_state.dart';
import 'settings_state.dart';

class ListeningBookmark {
  const ListeningBookmark(this.id, this.positionMs, this.note);
  final String id;
  final int positionMs;
  final String note;
  Map<String, Object> toJson() => {
    'id': id,
    'positionMs': positionMs,
    'note': note,
  };
}

enum SubtitleSource { none, auto, manual }

enum SubtitleManualOrigin { unknown, work, local }

enum SubtitleStatus {
  idle,
  loading,
  loaded,
  empty,
  ambiguous,
  offlineEmpty,
  networkError,
  parseError,
}

/// App-scoped per-track notes and automatic chapter subtitle controller.
///
/// Separate generation counters isolate bookmark refreshes from subtitle loads
/// and discard stale async completions after rapid track switches.
class ListeningNotes extends ChangeNotifier {
  ListeningNotes(
    this.library,
    this.player, {
    SettingsState? settings,
    ApiClient? api,
    Future<List<ConnectivityResult>> Function()? checkNetwork,
    String Function()? languageResolver,
  }) : _settings = settings,
       _api = api ?? ApiClient.instance,
       _checkNetwork = checkNetwork ?? Connectivity().checkConnectivity,
       _languageResolver = languageResolver {
    _seenDocumentsVersion = _readDocumentsVersion();
    _lastLanguage = _preferredLanguage();
    player.addListener(_trackChanged);
    library.addListener(_libraryChanged);
    _settings?.addListener(_settingsChanged);
    _trackChanged();
  }

  final LibraryState library;
  final PlayerState player;
  final SettingsState? _settings;
  final ApiClient _api;
  final Future<List<ConnectivityResult>> Function() _checkNetwork;
  final String Function()? _languageResolver;

  PlayItem? _currentItem;
  String? _key;
  int _bookmarkGeneration = 0;
  int _subtitleGeneration = 0;
  int _seenDocumentsVersion = 0;
  String _lastLanguage = 'zh';
  bool _disposed = false;

  bool bookmarksLoading = false;
  String? bookmarkError;
  List<ListeningBookmark> bookmarks = [];

  SubtitleStatus subtitleStatus = SubtitleStatus.idle;
  SubtitleSource subtitleSource = SubtitleSource.none;
  SubtitleManualOrigin manualOrigin = SubtitleManualOrigin.unknown;
  String? subtitleError;
  List<SubtitleCue> cues = [];
  String subtitleName = '';
  String _source = '';
  int offsetMs = 0;
  String? _matchedAttachmentId;
  String? _matchedLanguage;
  List<SubtitleAttachment> ambiguousCandidates = const [];

  bool _showPlayerSubtitles = false;
  bool get showPlayerSubtitles => _showPlayerSubtitles;
  set showPlayerSubtitles(bool value) {
    if (_showPlayerSubtitles == value) return;
    _showPlayerSubtitles = value;
    _notify();
  }

  final Map<int, WorkTrackIndex> _indexCache = {};
  final Map<int, Future<WorkTrackIndex>> _inFlightIndex = {};

  String? get key => _key;
  bool get loading => bookmarksLoading || subtitleStatus == SubtitleStatus.loading;
  String? get error => bookmarkError ?? subtitleError;

  static String trackKey(PlayItem item) =>
      '${item.workId}:${item.hash ?? '${item.folderLabel}/${item.title}'}';

  /// Caches a track tree already loaded by [WorkDetailScreen] so playback avoids
  /// redundant `fetchTracks` calls and re-evaluates auto-matching when needed.
  void cacheTrackTree(int workId, List<TrackNode> nodes) {
    final index = WorkTrackIndex.fromNodes(workId, nodes);
    _indexCache[workId] = index;
    final item = _currentItem;
    if (item != null &&
        item.workId == workId &&
        subtitleSource != SubtitleSource.manual) {
      unawaited(_loadSubtitle(forceReevaluate: true));
    }
  }

  WorkTrackIndex? cachedTrackIndex(int workId) => _indexCache[workId];

  /// Returns the cached work attachment index or merges concurrent `fetchTracks` requests.
  Future<WorkTrackIndex> getTrackIndex(
    int workId, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      final cached = _indexCache[workId];
      if (cached != null) return Future.value(cached);
    }
    final existing = _inFlightIndex[workId];
    if (existing != null) return existing;

    final future = _api
        .fetchTracks(workId)
        .then((nodes) {
          final index = WorkTrackIndex.fromNodes(workId, nodes);
          _indexCache[workId] = index;
          return index;
        })
        .whenComplete(() {
          _inFlightIndex.remove(workId);
        });
    _inFlightIndex[workId] = future;
    return future;
  }

  int _readDocumentsVersion() {
    try {
      return library.documentsVersion;
    } on NoSuchMethodError {
      return 0;
    }
  }

  String _preferredLanguage() {
    if (_languageResolver != null) return _languageResolver();
    final locale = _settings?.locale ?? PlatformDispatcher.instance.locale;
    final lang = locale.languageCode.toLowerCase();
    final script = locale.scriptCode?.toLowerCase() ?? '';
    final country = locale.countryCode?.toLowerCase() ?? '';
    if (lang == 'zh') {
      if (script == 'hant' || country == 'tw' || country == 'hk') {
        return 'zh-hant';
      }
      return 'zh-hans';
    }
    return lang.isEmpty ? 'zh-hans' : lang;
  }

  Future<bool> _isOffline() async {
    try {
      final results = await _checkNetwork();
      return results.isEmpty ||
          results.every((r) => r == ConnectivityResult.none);
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  void _trackChanged() {
    final item = player.currentItem;
    final nextKey = item == null ? null : trackKey(item);
    if (_key == nextKey) return;
    _currentItem = item;
    _key = nextKey;

    if (item == null) {
      // Session ended: reset cover/subtitle view for the next playback session.
      _showPlayerSubtitles = false;
      _bookmarkGeneration++;
      _subtitleGeneration++;
      bookmarksLoading = false;
      bookmarkError = null;
      bookmarks = [];
      _clearSubtitleFields(SubtitleStatus.idle);
      _notify();
      return;
    }

    // Immediately clear the previous track's text before async loading starts.
    _clearSubtitleFields(SubtitleStatus.loading);
    bookmarks = [];
    bookmarkError = null;
    bookmarksLoading = true;
    _notify();

    unawaited(_loadBookmarks());
    unawaited(_loadSubtitle());
  }

  void _libraryChanged() {
    final nextVersion = _readDocumentsVersion();
    if (nextVersion == _seenDocumentsVersion) return;
    _seenDocumentsVersion = nextVersion;
    if (_key == null) return;
    unawaited(_loadBookmarks());
    unawaited(_loadSubtitle());
  }

  void _settingsChanged() {
    final nextLang = _preferredLanguage();
    if (nextLang == _lastLanguage) return;
    _lastLanguage = nextLang;
    if (_key == null || subtitleSource == SubtitleSource.manual) return;
    unawaited(_loadSubtitle(forceReevaluate: true));
  }

  void _clearSubtitleFields(SubtitleStatus nextStatus) {
    subtitleStatus = nextStatus;
    subtitleSource = SubtitleSource.none;
    manualOrigin = SubtitleManualOrigin.unknown;
    subtitleError = null;
    cues = [];
    subtitleName = '';
    _source = '';
    offsetMs = 0;
    _matchedAttachmentId = null;
    _matchedLanguage = null;
    ambiguousCandidates = const [];
  }

  bool _isBookmarkCurrent(String itemKey, int generation) =>
      !_disposed && _key == itemKey && _bookmarkGeneration == generation;

  bool _isSubtitleCurrent(String itemKey, int generation) =>
      !_disposed && _key == itemKey && _subtitleGeneration == generation;

  Future<void> reload() async {
    await Future.wait([_loadBookmarks(), _loadSubtitle()]);
  }

  Future<void> retrySubtitle() =>
      _loadSubtitle(forceReevaluate: true, refreshIndex: true);

  Future<void> _loadBookmarks() async {
    final generation = ++_bookmarkGeneration;
    final itemKey = _key;
    if (itemKey == null) {
      bookmarksLoading = false;
      bookmarks = [];
      bookmarkError = null;
      _notify();
      return;
    }
    bookmarksLoading = true;
    bookmarkError = null;
    _notify();
    try {
      final rawMarks = await library.readDocument('bookmarks:$itemKey');
      if (!_isBookmarkCurrent(itemKey, generation)) return;
      if (rawMarks is List) {
        bookmarks =
            rawMarks
                .map(
                  (r) => ListeningBookmark(
                    r['id'] as String,
                    r['positionMs'] as int,
                    r['note'] as String,
                  ),
                )
                .toList()
              ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
      } else {
        bookmarks = [];
      }
    } catch (e) {
      if (_isBookmarkCurrent(itemKey, generation)) bookmarkError = '$e';
    } finally {
      if (_isBookmarkCurrent(itemKey, generation)) {
        bookmarksLoading = false;
        _notify();
      }
    }
  }

  Future<void> _loadSubtitle({
    bool forceReevaluate = false,
    bool refreshIndex = false,
  }) async {
    final generation = ++_subtitleGeneration;
    final item = _currentItem;
    final itemKey = _key;
    final lang = _preferredLanguage();

    if (item == null || itemKey == null) {
      _clearSubtitleFields(SubtitleStatus.idle);
      _notify();
      return;
    }

    if (!forceReevaluate) {
      _clearSubtitleFields(SubtitleStatus.loading);
      _notify();
    } else if (subtitleStatus != SubtitleStatus.loaded) {
      subtitleStatus = SubtitleStatus.loading;
      subtitleError = null;
      _notify();
    }

    // 1. Read saved manual subtitle and cached auto-match from local storage.
    Object? rawManual;
    Object? rawMatched;
    try {
      final values = await Future.wait([
        library.readDocument('subtitle:$itemKey'),
        library.readDocument('matchedSubtitle:$itemKey'),
      ]);
      if (!_isSubtitleCurrent(itemKey, generation)) return;
      rawManual = values[0];
      rawMatched = values[1];
    } catch (e) {
      if (!_isSubtitleCurrent(itemKey, generation)) return;
      _clearSubtitleFields(SubtitleStatus.parseError);
      subtitleError = '$e';
      _notify();
      return;
    }

    // Manual subtitle always wins over automatic matching.
    if (rawManual is Map) {
      final source = rawManual['source'] as String? ?? '';
      final name = rawManual['name'] as String? ?? '';
      final savedOffset = rawManual['offsetMs'] as int? ?? 0;
      final origin = _parseManualOrigin(rawManual['origin'] as String?);
      try {
        final parsed = Subtitles.parse(source);
        if (!_isSubtitleCurrent(itemKey, generation)) return;
        cues = parsed;
        subtitleName = name;
        _source = source;
        offsetMs = savedOffset;
        subtitleSource = SubtitleSource.manual;
        manualOrigin = origin;
        subtitleStatus = SubtitleStatus.loaded;
        subtitleError = null;
        _matchedAttachmentId = null;
        _matchedLanguage = null;
        ambiguousCandidates = const [];
        _notify();
      } catch (e) {
        if (!_isSubtitleCurrent(itemKey, generation)) return;
        _clearSubtitleFields(SubtitleStatus.parseError);
        subtitleName = name;
        subtitleSource = SubtitleSource.manual;
        manualOrigin = origin;
        subtitleError = '$e';
        _notify();
      }
      return;
    }

    // Check cached auto-match record.
    final cached = _CachedAutoSubtitle.tryParse(rawMatched);
    final cacheMatchesPrefs =
        cached != null &&
        cached.ruleVersion == SubtitleMatcher.ruleVersion &&
        cached.language == lang;

    if (!forceReevaluate && !refreshIndex && cacheMatchesPrefs) {
      if (_commitCachedAuto(cached, itemKey, generation)) return;
    }

    // 2. Obtain the work's track tree index (reuse cached index or fetch online).
    WorkTrackIndex? index = refreshIndex ? null : _indexCache[item.workId];
    if (index == null) {
      if (await _isOffline()) {
        if (!_isSubtitleCurrent(itemKey, generation)) return;
        if (cached != null && _commitCachedAuto(cached, itemKey, generation)) {
          return;
        }
        _clearSubtitleFields(SubtitleStatus.offlineEmpty);
        _notify();
        return;
      }
      if (!_isSubtitleCurrent(itemKey, generation)) return;
      try {
        index = await getTrackIndex(item.workId, forceRefresh: refreshIndex);
      } catch (e) {
        if (!_isSubtitleCurrent(itemKey, generation)) return;
        if (cached != null && _commitCachedAuto(cached, itemKey, generation)) {
          return;
        }
        final offlineNow = await _isOffline();
        if (!_isSubtitleCurrent(itemKey, generation)) return;
        if (offlineNow) {
          _clearSubtitleFields(SubtitleStatus.offlineEmpty);
        } else {
          _clearSubtitleFields(SubtitleStatus.networkError);
          subtitleError = e is ApiException ? e.message : '$e';
        }
        _notify();
        return;
      }
      if (!_isSubtitleCurrent(itemKey, generation)) return;
    }

    // 3. Locate the original audio node and match within the same work.
    final audio =
        index.findAudio(
          workId: item.workId,
          hash: item.hash,
          folderLabel: item.folderLabel,
          title: item.title,
        ) ??
        AudioTrack(
          node: TrackNode(type: 'audio', title: item.title, hash: item.hash),
          folderPath: item.folderLabel.isEmpty
              ? const []
              : item.folderLabel.split(' / '),
        );

    final matchResult = SubtitleMatcher.match(
      index: index,
      audio: audio,
      preferredLanguage: lang,
    );

    switch (matchResult.outcome) {
      case SubtitleMatchOutcome.noMatch:
        if (!_isSubtitleCurrent(itemKey, generation)) return;
        _clearSubtitleFields(SubtitleStatus.empty);
        _notify();
        return;

      case SubtitleMatchOutcome.ambiguous:
        if (!_isSubtitleCurrent(itemKey, generation)) return;
        _clearSubtitleFields(SubtitleStatus.ambiguous);
        ambiguousCandidates = matchResult.candidates;
        _notify();
        return;

      case SubtitleMatchOutcome.matched:
        final attachment = matchResult.attachment!;

        // Already loaded with the same attachment: update language metadata if needed without re-downloading.
        if (subtitleSource == SubtitleSource.auto &&
            subtitleStatus == SubtitleStatus.loaded &&
            _matchedAttachmentId == attachment.attachmentId &&
            cues.isNotEmpty) {
          if (_matchedLanguage != lang) {
            _matchedLanguage = lang;
            await library.writeDocument('matchedSubtitle:$itemKey', {
              'attachmentId': attachment.attachmentId,
              'name': subtitleName,
              'source': _source,
              'language': lang,
              'ruleVersion': SubtitleMatcher.ruleVersion,
              'offsetMs': offsetMs,
            });
          }
          return;
        }

        // Cache already contains this exact attachment: reuse without network.
        if (cached != null &&
            cached.attachmentId == attachment.attachmentId &&
            _commitCachedAuto(cached, itemKey, generation)) {
          if (cached.language != lang ||
              cached.ruleVersion != SubtitleMatcher.ruleVersion) {
            _matchedLanguage = lang;
            await library.writeDocument('matchedSubtitle:$itemKey', {
              'attachmentId': cached.attachmentId,
              'name': cached.name,
              'source': cached.source,
              'language': lang,
              'ruleVersion': SubtitleMatcher.ruleVersion,
              'offsetMs': cached.offsetMs,
            });
          }
          return;
        }

        if (await _isOffline()) {
          if (!_isSubtitleCurrent(itemKey, generation)) return;
          if (cached != null &&
              _commitCachedAuto(cached, itemKey, generation)) {
            return;
          }
          _clearSubtitleFields(SubtitleStatus.offlineEmpty);
          _notify();
          return;
        }
        if (!_isSubtitleCurrent(itemKey, generation)) return;

        // 4. Download, parse, and cache only after parsing succeeds.
        String source;
        try {
          source = await _api.fetchSubtitle(attachment.node);
        } on FormatException catch (e) {
          if (!_isSubtitleCurrent(itemKey, generation)) return;
          _clearSubtitleFields(SubtitleStatus.parseError);
          subtitleName = attachment.title;
          subtitleError = '$e';
          _notify();
          return;
        } catch (e) {
          if (!_isSubtitleCurrent(itemKey, generation)) return;
          if (e is ApiException && e.message.contains('2 MB')) {
            _clearSubtitleFields(SubtitleStatus.parseError);
            subtitleName = attachment.title;
            subtitleError = e.message;
            _notify();
            return;
          }
          if (cached != null &&
              _commitCachedAuto(cached, itemKey, generation)) {
            return;
          }
          final offlineNow = await _isOffline();
          if (!_isSubtitleCurrent(itemKey, generation)) return;
          if (offlineNow) {
            _clearSubtitleFields(SubtitleStatus.offlineEmpty);
          } else {
            _clearSubtitleFields(SubtitleStatus.networkError);
            subtitleError = _formatFetchError(e);
          }
          _notify();
          return;
        }

        if (!_isSubtitleCurrent(itemKey, generation)) return;

        List<SubtitleCue> parsed;
        try {
          parsed = Subtitles.parse(source);
        } catch (e) {
          if (!_isSubtitleCurrent(itemKey, generation)) return;
          // Do not cache corrupt or unparseable subtitle files.
          _clearSubtitleFields(SubtitleStatus.parseError);
          subtitleName = attachment.title;
          subtitleError = '$e';
          _notify();
          return;
        }

        if (!_isSubtitleCurrent(itemKey, generation)) return;
        final preservedOffset =
            cached?.attachmentId == attachment.attachmentId
            ? cached!.offsetMs
            : 0;

        await library.writeDocument('matchedSubtitle:$itemKey', {
          'attachmentId': attachment.attachmentId,
          'name': attachment.title,
          'source': source,
          'language': lang,
          'ruleVersion': SubtitleMatcher.ruleVersion,
          'offsetMs': preservedOffset,
        });

        if (!_isSubtitleCurrent(itemKey, generation)) return;
        cues = parsed;
        subtitleName = attachment.title;
        _source = source;
        offsetMs = preservedOffset;
        _matchedAttachmentId = attachment.attachmentId;
        _matchedLanguage = lang;
        subtitleSource = SubtitleSource.auto;
        manualOrigin = SubtitleManualOrigin.unknown;
        subtitleStatus = SubtitleStatus.loaded;
        subtitleError = null;
        ambiguousCandidates = const [];
        _notify();
    }
  }

  bool _commitCachedAuto(
    _CachedAutoSubtitle cached,
    String itemKey,
    int generation,
  ) {
    try {
      final parsed = Subtitles.parse(cached.source);
      if (!_isSubtitleCurrent(itemKey, generation)) return true;
      cues = parsed;
      subtitleName = cached.name;
      _source = cached.source;
      offsetMs = cached.offsetMs;
      _matchedAttachmentId = cached.attachmentId;
      _matchedLanguage = cached.language;
      subtitleSource = SubtitleSource.auto;
      manualOrigin = SubtitleManualOrigin.unknown;
      subtitleStatus = SubtitleStatus.loaded;
      subtitleError = null;
      ambiguousCandidates = const [];
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  static SubtitleManualOrigin _parseManualOrigin(String? raw) => switch (raw) {
    'work' => SubtitleManualOrigin.work,
    'local' => SubtitleManualOrigin.local,
    _ => SubtitleManualOrigin.unknown,
  };

  static String _formatFetchError(Object error) {
    if (error is ApiException) return error.message;
    if (error is DioException) return error.message ?? '$error';
    if (error is SocketException) return error.message;
    return '$error';
  }

  // ---------------------------------------------------------------------------
  // Bookmarks
  // ---------------------------------------------------------------------------

  Future<void> addBookmark(String note, {int? positionMs}) async {
    final itemKey = _key;
    if (itemKey == null || bookmarksLoading) return;
    final next = [
      ...bookmarks,
      ListeningBookmark(
        DateTime.now().microsecondsSinceEpoch.toString(),
        positionMs ?? player.player.position.inMilliseconds,
        note.trim(),
      ),
    ]..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    await _saveBookmarks(itemKey, next);
  }

  Future<void> editBookmark(ListeningBookmark bookmark, String? note) async {
    final itemKey = _key;
    if (itemKey == null || bookmarksLoading) return;
    final next = [
      for (final b in bookmarks)
        if (b.id != bookmark.id)
          b
        else if (note != null)
          ListeningBookmark(b.id, b.positionMs, note.trim()),
    ];
    await _saveBookmarks(itemKey, next);
  }

  Future<void> _saveBookmarks(
    String itemKey,
    List<ListeningBookmark> next,
  ) async {
    final generation = ++_bookmarkGeneration;
    await library.writeDocument(
      'bookmarks:$itemKey',
      next.map((b) => b.toJson()).toList(),
    );
    if (_isBookmarkCurrent(itemKey, generation)) {
      bookmarks = next;
      _notify();
    }
  }

  // ---------------------------------------------------------------------------
  // Manual subtitle override, offset, and restoring auto-match
  // ---------------------------------------------------------------------------

  Future<void> importSubtitle(
    String name,
    String source, {
    SubtitleManualOrigin origin = SubtitleManualOrigin.local,
  }) async {
    final itemKey = _key;
    if (itemKey == null) return;
    final parsed = Subtitles.parse(source);
    final generation = ++_subtitleGeneration;
    await library.writeDocument('subtitle:$itemKey', {
      'name': name,
      'source': source,
      'offsetMs': 0,
      'origin': origin.name,
    });
    if (_isSubtitleCurrent(itemKey, generation)) {
      subtitleName = name;
      _source = source;
      offsetMs = 0;
      cues = parsed;
      subtitleSource = SubtitleSource.manual;
      manualOrigin = origin;
      subtitleStatus = SubtitleStatus.loaded;
      subtitleError = null;
      _matchedAttachmentId = null;
      _matchedLanguage = null;
      ambiguousCandidates = const [];
      _notify();
    }
  }

  Future<void> selectWorkSubtitle(SubtitleAttachment attachment) async {
    final itemKey = _key;
    if (itemKey == null) return;
    final generation = ++_subtitleGeneration;
    final source = await _api.fetchSubtitle(attachment.node);
    if (!_isSubtitleCurrent(itemKey, generation)) return;
    final parsed = Subtitles.parse(source);
    if (!_isSubtitleCurrent(itemKey, generation)) return;
    await library.writeDocument('subtitle:$itemKey', {
      'name': attachment.title,
      'source': source,
      'offsetMs': 0,
      'origin': SubtitleManualOrigin.work.name,
    });
    if (_isSubtitleCurrent(itemKey, generation)) {
      subtitleName = attachment.title;
      _source = source;
      offsetMs = 0;
      cues = parsed;
      subtitleSource = SubtitleSource.manual;
      manualOrigin = SubtitleManualOrigin.work;
      subtitleStatus = SubtitleStatus.loaded;
      subtitleError = null;
      _matchedAttachmentId = null;
      _matchedLanguage = null;
      ambiguousCandidates = const [];
      _notify();
    }
  }

  Future<void> setOffset(int value) async {
    final itemKey = _key;
    if (itemKey == null || cues.isEmpty) return;
    final generation = _subtitleGeneration;
    if (subtitleSource == SubtitleSource.manual) {
      await library.writeDocument('subtitle:$itemKey', {
        'name': subtitleName,
        'source': _source,
        'offsetMs': value,
        if (manualOrigin != SubtitleManualOrigin.unknown)
          'origin': manualOrigin.name,
      });
    } else if (subtitleSource == SubtitleSource.auto) {
      await library.writeDocument('matchedSubtitle:$itemKey', {
        'attachmentId': _matchedAttachmentId ?? subtitleName,
        'name': subtitleName,
        'source': _source,
        'language': _matchedLanguage ?? _preferredLanguage(),
        'ruleVersion': SubtitleMatcher.ruleVersion,
        'offsetMs': value,
      });
    } else {
      return;
    }
    if (_isSubtitleCurrent(itemKey, generation)) {
      offsetMs = value;
      _notify();
    }
  }

  /// Removes the current chapter's manual override and re-runs automatic matching.
  Future<void> restoreAutoSubtitle() async {
    final itemKey = _key;
    if (itemKey == null) return;
    final generation = ++_subtitleGeneration;
    await library.writeDocument('subtitle:$itemKey', null);
    if (!_isSubtitleCurrent(itemKey, generation)) return;
    _clearSubtitleFields(SubtitleStatus.loading);
    _notify();
    await _loadSubtitle(forceReevaluate: true);
  }

  /// Removes manual subtitle (kept for compatibility).
  Future<void> removeSubtitle() async {
    final itemKey = _key;
    if (itemKey == null) return;
    final generation = ++_subtitleGeneration;
    await library.writeDocument('subtitle:$itemKey', null);
    if (_isSubtitleCurrent(itemKey, generation)) {
      _clearSubtitleFields(SubtitleStatus.empty);
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    player.removeListener(_trackChanged);
    library.removeListener(_libraryChanged);
    _settings?.removeListener(_settingsChanged);
    super.dispose();
  }
}

class _CachedAutoSubtitle {
  const _CachedAutoSubtitle({
    required this.attachmentId,
    required this.name,
    required this.source,
    required this.language,
    required this.ruleVersion,
    required this.offsetMs,
  });

  final String attachmentId;
  final String name;
  final String source;
  final String language;
  final int ruleVersion;
  final int offsetMs;

  static _CachedAutoSubtitle? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final attachmentId = raw['attachmentId'] as String?;
    final name = raw['name'] as String?;
    final source = raw['source'] as String?;
    final language = raw['language'] as String?;
    final ruleVersion = raw['ruleVersion'] as int?;
    final offsetMs = raw['offsetMs'] as int? ?? 0;
    if (attachmentId == null ||
        name == null ||
        source == null ||
        source.isEmpty ||
        language == null ||
        ruleVersion == null) {
      return null;
    }
    return _CachedAutoSubtitle(
      attachmentId: attachmentId,
      name: name,
      source: source,
      language: language,
      ruleVersion: ruleVersion,
      offsetMs: offsetMs,
    );
  }
}
