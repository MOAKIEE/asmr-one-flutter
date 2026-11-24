import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/subtitle_matcher.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../state/listening_notes.dart';
import '../state/player_state.dart';
import '../widgets/common.dart';

class ListeningToolsScreen extends StatefulWidget {
  const ListeningToolsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.expandReplace = false,
  });

  final int initialTabIndex;
  final bool expandReplace;

  @override
  State<ListeningToolsScreen> createState() => _ListeningToolsScreenState();
}

class _ListeningToolsScreenState extends State<ListeningToolsScreen> {
  ListeningNotes? _ownedNotes;
  bool _busy = false;

  ListeningNotes _resolveNotes(BuildContext context) {
    try {
      return context.watch<ListeningNotes>();
    } on ProviderNotFoundException {
      return _ownedNotes ??= ListeningNotes(
        context.read<LibraryState>(),
        context.read<PlayerState>(),
      );
    }
  }

  @override
  void dispose() {
    _ownedNotes?.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importLocal(ListeningNotes notes) async {
    final tooLargeMsg = L10n.of(context)('notes.tooLarge');
    final key = notes.key;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'srt', 'vtt'],
    );
    if (file == null) return;
    if ((await file.length() ?? 0) > 2 * 1024 * 1024) {
      throw FormatException(tooLargeMsg);
    }
    final source = utf8.decode(await file.readAsBytes());
    if (key != notes.key) return;
    await notes.importSubtitle(
      file.name,
      source,
      origin: SubtitleManualOrigin.local,
    );
  }

  Future<void> _pickWorkSubtitle(ListeningNotes notes) async {
    final player = context.read<PlayerState>();
    final item = player.currentItem;
    if (item == null) return;
    final key = notes.key;
    final index = await notes.getTrackIndex(item.workId);
    if (!mounted || key != notes.key) return;
    final l = L10n.of(context);
    if (index.subtitles.isEmpty) {
      throw FormatException(l('notes.noOnlineSubtitle'));
    }
    final selected = await showModalBottomSheet<SubtitleAttachment>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final maxH = MediaQuery.sizeOf(sheetContext).height * 0.72;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final sub in index.subtitles)
                  ListTile(
                    leading: const Icon(Icons.subtitles_outlined),
                    title: Text(
                      sub.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: sub.folderLabel.isEmpty
                        ? null
                        : Text(
                            sub.folderLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => Navigator.pop(sheetContext, sub),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || key != notes.key) return;
    await notes.selectWorkSubtitle(selected);
  }

  Future<void> _bookmark(
    ListeningNotes notes, [
    ListeningBookmark? bookmark,
  ]) async {
    final l = L10n.of(context);
    final key = notes.key;
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
    if (!mounted || note == null || key != notes.key) return;
    if (bookmark == null) {
      await _run(() => notes.addBookmark(note, positionMs: positionMs));
    } else {
      await _run(() => notes.editBookmark(bookmark, note));
    }
  }

  String _sourceLabel(ListeningNotes notes, L10n l) {
    switch (notes.subtitleSource) {
      case SubtitleSource.auto:
        return l('notes.sourceAuto');
      case SubtitleSource.manual:
        return switch (notes.manualOrigin) {
          SubtitleManualOrigin.work => l('notes.sourceManualWork'),
          SubtitleManualOrigin.local => l('notes.sourceManualLocal'),
          SubtitleManualOrigin.unknown => l('notes.sourceManual'),
        };
      case SubtitleSource.none:
        return l('notes.sourceNone');
    }
  }

  String _statusHeadline(ListeningNotes notes, L10n l) {
    if (notes.cues.isNotEmpty) return notes.subtitleName;
    return switch (notes.subtitleStatus) {
      SubtitleStatus.idle || SubtitleStatus.loading => l('subtitle.matching'),
      SubtitleStatus.empty || SubtitleStatus.loaded => l('subtitle.empty'),
      SubtitleStatus.ambiguous => l('subtitle.ambiguous'),
      SubtitleStatus.offlineEmpty => l('subtitle.offlineEmpty'),
      SubtitleStatus.networkError => l('subtitle.networkError'),
      SubtitleStatus.parseError => l('subtitle.parseError'),
    };
  }

  IconData _statusIcon(ListeningNotes notes) {
    if (notes.cues.isNotEmpty) return Icons.subtitles_rounded;
    return switch (notes.subtitleStatus) {
      SubtitleStatus.idle || SubtitleStatus.loading => Icons.sync_rounded,
      SubtitleStatus.empty ||
      SubtitleStatus.loaded => Icons.subtitles_off_outlined,
      SubtitleStatus.ambiguous => Icons.subtitles_outlined,
      SubtitleStatus.offlineEmpty => Icons.cloud_off_outlined,
      SubtitleStatus.networkError => Icons.wifi_off_rounded,
      SubtitleStatus.parseError => Icons.error_outline_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final notes = _resolveNotes(context);
    final l = L10n.of(context);
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l('notes.toolsTitle')),
          bottom: TabBar(
            tabs: [
              Tab(text: l('notes.subtitleSettings')),
              Tab(text: l('notes.bookmarks')),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: notes,
          builder: (context, _) {
            if (player.currentItem == null) {
              return Center(child: Text(l('player.nothing')));
            }
            final scheme = Theme.of(context).colorScheme;
            return Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: scheme.surfaceContainerLow,
                  child: Row(
                    children: [
                      Icon(
                        Icons.music_note_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          Fmt.stripExt(player.currentItem!.title),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_busy || notes.loading)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: TabBarView(
                    children: [
                      _subtitleSettings(notes, l),
                      _bookmarks(player, notes, l),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border(
                      top: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  child: SafeArea(
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
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                            IconButton(
                              onPressed: player.toggle,
                              color: scheme.primary,
                              icon: Icon(
                                player.playing
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                size: 30,
                              ),
                            ),
                            IconButton(
                              onPressed: player.hasNext ? player.next : null,
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _subtitleSettings(ListeningNotes notes, L10n l) {
    final scheme = Theme.of(context).colorScheme;
    final canRetry =
        notes.subtitleStatus == SubtitleStatus.networkError ||
        notes.subtitleStatus == SubtitleStatus.offlineEmpty ||
        notes.subtitleStatus == SubtitleStatus.parseError;
    final offsetLabel =
        '${notes.offsetMs > 0 ? '+' : ''}${(notes.offsetMs / 1000).toStringAsFixed(1)}s';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        AppGroupCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _statusIcon(notes),
                      color: notes.cues.isNotEmpty
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _statusHeadline(notes, l),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${l('notes.source')}：${_sourceLabel(notes, l)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (notes.subtitleSource == SubtitleSource.manual ||
                    canRetry) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (notes.subtitleSource == SubtitleSource.manual)
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(notes.restoreAutoSubtitle),
                          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                          label: Text(l('notes.restoreAuto')),
                        ),
                      if (canRetry)
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(notes.retrySubtitle),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(l('common.retry')),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (notes.cues.isNotEmpty)
          AppGroupCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l('notes.offset'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      IconButton(
                        tooltip: '-0.5s',
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => notes.setOffset(notes.offsetMs - 500),
                              ),
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 56),
                        child: Text(
                          offsetLabel,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: '+0.5s',
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => notes.setOffset(notes.offsetMs + 500),
                              ),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                      if (notes.offsetMs != 0)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => notes.setOffset(0)),
                          child: Text(l('common.reset')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l('notes.offsetHint'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        AppGroupCard(
          child: ExpansionTile(
            key: ValueKey('replace-${widget.expandReplace}-${notes.cues.isEmpty}'),
            initiallyExpanded: widget.expandReplace || notes.cues.isEmpty,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.swap_horiz_rounded),
            title: Text(
              l('notes.replaceSubtitle'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _pickWorkSubtitle(notes)),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: Text(l('notes.onlineSubtitle')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _importLocal(notes)),
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: Text(l('notes.importLocal')),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                l('notes.subtitleHint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bookmarks(PlayerState player, ListeningNotes notes, L10n l) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy || notes.bookmarksLoading
                ? null
                : () => _bookmark(notes),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(l('notes.addBookmark')),
          ),
        ),
      ),
      if (notes.bookmarkError != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            notes.bookmarkError!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      Expanded(
        child: notes.bookmarks.isEmpty
            ? Center(child: Text(l('notes.emptyBookmarks')))
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                children: [
                  for (final bookmark in notes.bookmarks)
                    AppGroupCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        subtitle: Text(
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
                              onPressed: _busy
                                  ? null
                                  : () => _bookmark(notes, bookmark),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => notes.editBookmark(bookmark, null),
                                    ),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}
