import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models/subtitle.dart';
import 'library_state.dart';
import 'player_state.dart';

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

/// Per-track portable notes. Generation checks keep slow reads from replacing
/// the notes for a newly selected track.
class ListeningNotes extends ChangeNotifier {
  ListeningNotes(this.library, this.player) {
    player.addListener(_trackChanged);
    library.addListener(_libraryChanged);
    _trackChanged();
  }
  final LibraryState library;
  final PlayerState player;
  String? _key;
  int _generation = 0;
  bool _disposed = false;
  bool loading = false;
  String? error;
  List<ListeningBookmark> bookmarks = [];
  List<SubtitleCue> cues = [];
  String subtitleName = '';
  String _source = '';
  int offsetMs = 0;
  String? get key => _key;

  static String trackKey(PlayItem item) =>
      '${item.workId}:${item.hash ?? '${item.folderLabel}/${item.title}'}';
  void _trackChanged() {
    final item = player.currentItem;
    final key = item == null ? null : trackKey(item);
    if (_key == key) return;
    _key = key;
    unawaited(reload());
  }

  void _libraryChanged() {
    unawaited(reload());
  }

  Future<void> reload() async {
    final generation = ++_generation;
    final key = _key;
    loading = true;
    bookmarks = [];
    cues = [];
    subtitleName = '';
    _source = '';
    offsetMs = 0;
    error = null;
    _notify();
    try {
      if (key == null) return;
      final values = await Future.wait([
        library.readDocument('bookmarks:$key'),
        library.readDocument('subtitle:$key'),
      ]);
      if (generation != _generation || _disposed) return;
      final rawMarks = values[0];
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
      }
      final rawSub = values[1];
      if (rawSub is Map) {
        _source = rawSub['source'] as String;
        subtitleName = rawSub['name'] as String;
        offsetMs = rawSub['offsetMs'] as int? ?? 0;
        cues = Subtitles.parse(_source);
      }
    } catch (e) {
      if (generation == _generation) error = '$e';
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> addBookmark(String note, {int? positionMs}) async {
    final itemKey = _key;
    if (itemKey == null || loading) return;
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
    if (itemKey == null || loading) return;
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
    await library.writeDocument(
      'bookmarks:$itemKey',
      next.map((b) => b.toJson()).toList(),
    );
    if (_key == itemKey) {
      bookmarks = next;
      _notify();
    }
  }

  Future<void> importSubtitle(String name, String source) async {
    final itemKey = _key;
    if (itemKey == null) return;
    final parsed = Subtitles.parse(source);
    await library.writeDocument('subtitle:$itemKey', {
      'name': name,
      'source': source,
      'offsetMs': 0,
    });
    if (_key == itemKey) {
      subtitleName = name;
      _source = source;
      offsetMs = 0;
      cues = parsed;
      _notify();
    }
  }

  Future<void> setOffset(int value) async {
    final itemKey = _key;
    if (itemKey == null || cues.isEmpty) return;
    await library.writeDocument('subtitle:$itemKey', {
      'name': subtitleName,
      'source': _source,
      'offsetMs': value,
    });
    if (_key == itemKey) {
      offsetMs = value;
      _notify();
    }
  }

  Future<void> removeSubtitle() async {
    final itemKey = _key;
    if (itemKey == null) return;
    await library.writeDocument('subtitle:$itemKey', null);
    if (_key == itemKey) {
      cues = [];
      _source = '';
      subtitleName = '';
      offsetMs = 0;
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
    super.dispose();
  }
}
