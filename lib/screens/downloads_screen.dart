import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/work.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/download_state.dart';
import '../state/library_state.dart';
import '../state/player_state.dart';
import '../core/storage/library_db.dart';
import '../widgets/common.dart';

/// 离线下载管理页。
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final downloads = context.watch<DownloadState>();
    final library = context.watch<LibraryState>();

    final rows = library.downloads;
    final active = downloads.tasks.where((t) => t.isActive).toList();
    final failed = downloads.tasks
        .where(
          (t) =>
              t.status == DownloadStatus.failed ||
              t.status == DownloadStatus.paused,
        )
        .toList();

    // 按作品聚合已完成的下载。
    final byWork = <int, List<DownloadRow>>{};
    for (final row in rows) {
      byWork.putIfAbsent(row.workId, () => []).add(row);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l('download.title')),
        actions: [
          if (downloads.tasks.any(
            (t) =>
                t.status == DownloadStatus.done ||
                t.status == DownloadStatus.cancelled,
          ))
            IconButton(
              tooltip: l('common.reset'),
              onPressed: downloads.clearFinished,
              icon: const Icon(Icons.cleaning_services_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SwitchListTile(
            title: Text(l('download.wifiOnly')),
            subtitle: downloads.waitingForWifi
                ? Text(l('download.waitingWifi'))
                : null,
            value: downloads.wifiOnly,
            onChanged: downloads.setWifiOnly,
          ),
          if (rows.isEmpty && active.isEmpty && failed.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l('download.empty')),
            ),
          if (active.isNotEmpty) ...[
            SectionHeader(
              title: l('download.downloading'),
              icon: Icons.downloading_rounded,
              subtitle: Fmt.size(active.fold(0, (s, t) => s + t.received)),
            ),
            for (final task in active)
              _TaskTile(
                task: task,
                onCancel: () => downloads.cancel(task),
                onPause: () => downloads.pauseTask(task),
              ),
          ],
          if (failed.isNotEmpty) ...[
            SectionHeader(
              title: l('download.failed'),
              icon: Icons.error_outline_rounded,
            ),
            for (final task in failed)
              _TaskTile(
                task: task,
                onCancel: () => downloads.retry(task),
                retry: true,
              ),
          ],
          if (byWork.isNotEmpty)
            SectionHeader(
              title: l('common.total', {'n': byWork.length}),
              icon: Icons.offline_pin_rounded,
              subtitle: Fmt.size(library.downloadBytes),
            ),
          for (final entry in byWork.entries)
            _WorkDownloadGroup(
              workId: entry.key,
              rows: entry.value,
              onPlay: (work) => _playWork(context, work),
              onDelete: () => downloads.deleteWorkFiles(entry.key),
            ),
        ],
      ),
    );
  }

  Future<void> _playWork(BuildContext context, Work work) async {
    final player = context.read<PlayerState>();
    final library = context.read<LibraryState>();
    final l = L10n.of(context);
    final paths = await library.downloadedPaths(work.id);
    if (!context.mounted) return;
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l('download.empty'))));
      return;
    }
    final rows = await library.downloadsFor(work.id);
    final ok = await player.playLocalFiles(work, paths, metadata: rows);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(player.error ?? l('download.failed'))),
      );
      player.clearError();
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l('download.done'))));
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onCancel,
    this.retry = false,
    this.onPause,
  });

  final DownloadTask task;
  final VoidCallback onCancel;
  final bool retry;
  final VoidCallback? onPause;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        retry ? Icons.refresh_rounded : Icons.downloading_rounded,
        color: retry ? theme.colorScheme.error : theme.colorScheme.primary,
      ),
      title: Text(
        Fmt.stripExt(task.title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          if (!retry)
            LinearProgressIndicator(
              value: task.progress > 0 ? task.progress : null,
              minHeight: 3,
            ),
          const SizedBox(height: 4),
          Text(
            retry
                ? (task.status == DownloadStatus.paused
                      ? L10n.of(context)('download.paused')
                      : task.error ?? '')
                : '${Fmt.size(task.received)}'
                      '${task.total > 0 ? ' / ${Fmt.size(task.total)}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPause != null)
            IconButton(
              onPressed: onPause,
              tooltip: L10n.of(context)('download.pause'),
              icon: const Icon(Icons.pause_rounded),
            ),
          IconButton(
            icon: Icon(retry ? Icons.refresh_rounded : Icons.close_rounded),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _WorkDownloadGroup extends StatelessWidget {
  const _WorkDownloadGroup({
    required this.workId,
    required this.rows,
    required this.onPlay,
    required this.onDelete,
  });

  final int workId;
  final List<DownloadRow> rows;
  final void Function(Work work) onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final library = context.watch<LibraryState>();
    // 从收藏 / 历史里找到对应作品补全展示信息。
    final work =
        _findWork(library, workId) ??
        Work.fromJson({
          'id': workId,
          'title': rows.first.workTitle ?? l('detail.title'),
        });
    final size = rows.fold<int>(0, (s, r) => s + r.size);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      rows.first.workTitle ?? work.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Fmt.size(size),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l('download.taskCount', {'n': rows.length}),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => onPlay(work),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(l('action.play')),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(l('common.delete')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Work? _findWork(LibraryState library, int id) {
    for (final w in library.favorites) {
      if (w.id == id) return w;
    }
    for (final w in library.history) {
      if (w.id == id) return w;
    }
    return null;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l('common.delete')),
        content: Text(l('download.deleteConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l('common.confirm')),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }
}
