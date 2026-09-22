import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/models/subtitle.dart';
import '../core/models/track.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../state/listening_notes.dart';
import '../state/player_state.dart';

class ListeningToolsScreen extends StatefulWidget {
  const ListeningToolsScreen({super.key});
  @override
  State<ListeningToolsScreen> createState() => _ListeningToolsScreenState();
}

class _ListeningToolsScreenState extends State<ListeningToolsScreen> {
  late final ListeningNotes _notes;
  final _scroll = ScrollController();
  bool _busy = false;
  bool _follow = true;
  int _lastActive = -1;
  @override
  void initState() {
    super.initState();
    _notes = ListeningNotes(
      context.read<LibraryState>(),
      context.read<PlayerState>(),
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final key = _notes.key;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'srt', 'vtt'],
    );
    if (file == null) return;
    if ((await file.length() ?? 0) > 2 * 1024 * 1024) {
      throw const FormatException('字幕超过 2 MB');
    }
    final source = utf8.decode(await file.readAsBytes());
    if (key != _notes.key) return;
    await _notes.importSubtitle(file.name, source);
  }

  Future<void> _online() async {
    final player = context.read<PlayerState>();
    final item = player.currentItem;
    if (item == null) return;
    final key = _notes.key;
    final nodes = await ApiClient.instance.fetchTracks(item.workId);
    final subtitles = <TrackNode>[];
    void walk(List<TrackNode> nodes) {
      for (final node in nodes) {
        if (RegExp(
          r'\.(lrc|srt|vtt)$',
          caseSensitive: false,
        ).hasMatch(node.title)) {
          subtitles.add(node);
        }
        walk(node.children);
      }
    }

    walk(nodes);
    if (!mounted || key != _notes.key) return;
    final l = L10n.of(context);
    if (subtitles.isEmpty) throw FormatException(l('notes.noOnlineSubtitle'));
    final selected = await showModalBottomSheet<TrackNode>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final node in subtitles)
              ListTile(
                title: Text(node.title),
                onTap: () => Navigator.pop(context, node),
              ),
          ],
        ),
      ),
    );
    if (selected == null || key != _notes.key) return;
    final source = await ApiClient.instance.fetchSubtitle(selected);
    if (key != _notes.key) return;
    await _notes.importSubtitle(selected.title, source);
  }

  Future<void> _bookmark([ListeningBookmark? bookmark]) async {
    final l = L10n.of(context);
    final key = _notes.key;
    var text = bookmark?.note ?? '';
    final positionMs = context
        .read<PlayerState>()
        .player
        .position
        .inMilliseconds;
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l('notes.bookmark')),
        content: TextFormField(
          initialValue: text,
          onChanged: (v) => text = v,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(hintText: l('notes.noteHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text),
            child: Text(l('common.confirm')),
          ),
        ],
      ),
    );
    if (!mounted || note == null || key != _notes.key) return;
    if (bookmark == null) {
      await _run(() => _notes.addBookmark(note, positionMs: positionMs));
    } else {
      await _run(() => _notes.editBookmark(bookmark, note));
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final l = L10n.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l('notes.title')),
          bottom: TabBar(
            tabs: [
              Tab(text: l('notes.subtitles')),
              Tab(text: l('notes.bookmarks')),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: _notes,
          builder: (context, _) {
            if (player.currentItem == null) {
              return Center(child: Text(l('player.nothing')));
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    player.currentItem!.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_busy || _notes.loading) const LinearProgressIndicator(),
                if (_notes.error != null) Text(_notes.error!),
                Expanded(
                  child: TabBarView(
                    children: [_subtitles(player, l), _bookmarks(player, l)],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: player.markLoopStart,
                            child: Text(
                              'A ${player.loopStart == null ? "—" : Fmt.position(player.loopStart!)}',
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              if (!player.markLoopEnd()) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l('notes.invalidLoop')),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              'B ${player.loopEnd == null ? "—" : Fmt.position(player.loopEnd!)}',
                            ),
                          ),
                          TextButton(
                            onPressed: player.clearAbLoop,
                            child: Text(l('notes.clearLoop')),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: player.previous,
                            icon: const Icon(Icons.skip_previous),
                          ),
                          IconButton(
                            onPressed: player.toggle,
                            icon: Icon(
                              player.playing ? Icons.pause : Icons.play_arrow,
                            ),
                          ),
                          IconButton(
                            onPressed: player.hasNext ? player.next : null,
                            icon: const Icon(Icons.skip_next),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _bookmarks(PlayerState player, L10n l) => Column(
    children: [
      FilledButton.icon(
        onPressed: _busy || _notes.loading ? null : () => _bookmark(),
        icon: const Icon(Icons.bookmark_add_outlined),
        label: Text(l('notes.addBookmark')),
      ),
      Expanded(
        child: _notes.bookmarks.isEmpty
            ? Center(child: Text(l('notes.emptyBookmarks')))
            : ListView(
                children: [
                  for (final bookmark in _notes.bookmarks)
                    ListTile(
                      leading: Text(
                        Fmt.position(
                          Duration(milliseconds: bookmark.positionMs),
                        ),
                      ),
                      title: Text(
                        bookmark.note.isEmpty
                            ? l('notes.bookmark')
                            : bookmark.note,
                      ),
                      onTap: () => player.seek(
                        Duration(milliseconds: bookmark.positionMs),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _busy ? null : () => _bookmark(bookmark),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _notes.editBookmark(bookmark, null),
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    ],
  );

  Widget _subtitles(PlayerState player, L10n l) => Column(
    children: [
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: _busy || _notes.loading ? null : () => _run(_import),
            icon: const Icon(Icons.file_open_outlined),
            label: Text(l('notes.importSubtitle')),
          ),
          TextButton.icon(
            onPressed: _busy || _notes.loading ? null : () => _run(_online),
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(l('notes.onlineSubtitle')),
          ),
          if (_notes.cues.isNotEmpty)
            IconButton(
              onPressed: _busy ? null : () => _run(_notes.removeSubtitle),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      if (_notes.cues.isNotEmpty) ...[
        Text(_notes.subtitleName, maxLines: 1, overflow: TextOverflow.ellipsis),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => _notes.setOffset(_notes.offsetMs - 500)),
              icon: const Icon(Icons.remove),
            ),
            Text(
              '${l('notes.offset')} ${(_notes.offsetMs / 1000).toStringAsFixed(1)}s',
            ),
            IconButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => _notes.setOffset(_notes.offsetMs + 500)),
              icon: const Icon(Icons.add),
            ),
            FilterChip(
              label: Text(l('notes.follow')),
              selected: _follow,
              onSelected: (v) => setState(() {
                _follow = v;
                _lastActive = -1;
              }),
            ),
          ],
        ),
      ],
      Expanded(
        child: _notes.cues.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l('notes.subtitleHint')),
                ),
              )
            : StreamBuilder<Duration>(
                stream: player.player.positionStream,
                builder: (context, snapshot) {
                  final active = Subtitles.activeIndex(
                    _notes.cues,
                    (snapshot.data ?? player.player.position).inMilliseconds,
                    offsetMs: _notes.offsetMs,
                  );
                  if (_follow && active >= 0 && active != _lastActive) {
                    _lastActive = active;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _scroll.hasClients) {
                        _scroll.animateTo(
                          (active * 88.0 - 88).clamp(
                            0,
                            _scroll.position.maxScrollExtent,
                          ),
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  }
                  return ListView.builder(
                    controller: _scroll,
                    itemExtent: 88,
                    itemCount: _notes.cues.length,
                    itemBuilder: (context, i) {
                      final cue = _notes.cues[i];
                      return ListTile(
                        selected: i == active,
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        leading: Text(
                          Fmt.position(Duration(milliseconds: cue.startMs)),
                        ),
                        title: Text(
                          cue.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => player.seek(
                          Duration(
                            milliseconds: (cue.startMs + _notes.offsetMs).clamp(
                              0,
                              1 << 40,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    ],
  );
}
