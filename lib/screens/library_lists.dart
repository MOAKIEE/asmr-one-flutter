import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/work.dart';
import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../state/settings_state.dart';
import '../widgets/common.dart';
import '../widgets/work_card.dart';
import 'playlist_screen.dart';

/// 收藏列表。
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();
    final library = context.watch<LibraryState>();
    final works = library.favorites;

    return Scaffold(
      appBar: AppBar(
        title: Text(l('library.favorites')),
        actions: [
          if (works.isNotEmpty)
            IconButton(
              tooltip: l('settings.clearData'),
              onPressed: () => _confirmClear(context, library),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: works.isEmpty
          ? EmptyView(
              message: l('library.emptyFavorites'),
              icon: Icons.favorite_border_rounded,
            )
          : _LocalWorkGrid(
              works: works,
              columns: settings.gridColumns,
              onLongPress: (w) => _showActions(context, w, isFavorite: true),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, LibraryState library) async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l('library.favorites')),
        content: Text(l('settings.clearDataConfirm')),
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
    if (ok != true) return;
    // 先取快照，避免在 await 之后再次触碰 context。
    final snapshot = [...library.favorites];
    for (final w in snapshot) {
      await library.toggleFavorite(w);
    }
  }

  void _showActions(
    BuildContext context,
    Work work, {
    required bool isFavorite,
  }) {
    showWorkActionSheet(context, work, isFavorite: isFavorite);
  }
}

/// 收听历史。
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final library = context.watch<LibraryState>();
    final works = library.history;

    return Scaffold(
      appBar: AppBar(
        title: Text(l('library.history')),
        actions: [
          if (works.isNotEmpty)
            IconButton(
              tooltip: l('search.clearHistory'),
              onPressed: library.clearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: works.isEmpty
          ? EmptyView(
              message: l('library.emptyHistory'),
              icon: Icons.history_rounded,
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 28),
              itemCount: works.length,
              itemBuilder: (context, i) {
                final work = works[i];
                return WorkListTile(
                  work: work,
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => library.removeHistory(work.id),
                  ),
                );
              },
            ),
    );
  }
}

/// 本地作品网格（收藏等离线数据）。
class _LocalWorkGrid extends StatelessWidget {
  const _LocalWorkGrid({
    required this.works,
    required this.columns,
    this.onLongPress,
  });

  final List<Work> works;
  final int columns;
  final void Function(Work work)? onLongPress;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(16, 4, 16, 28);
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final available = constraints.maxWidth - padding.horizontal;
        final cols = columns.clamp(1, 5);
        final itemWidth = (available - spacing * (cols - 1)) / cols;
        return GridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 18,
            mainAxisExtent: itemWidth + WorkCard.textHeight,
          ),
          itemCount: works.length,
          itemBuilder: (context, i) {
            final work = works[i];
            return GestureDetector(
              onLongPress: onLongPress == null
                  ? null
                  : () => onLongPress!(work),
              child: WorkCard(work: work),
            );
          },
        );
      },
    );
  }
}

/// 作品长按操作面板（收藏 / 加入列表 / 打开浏览器）。
Future<void> showWorkActionSheet(
  BuildContext context,
  Work work, {
  required bool isFavorite,
}) async {
  final l = L10n.of(context);
  final library = context.read<LibraryState>();

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              work.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheetContext).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              isFavorite
                  ? Icons.favorite_border_rounded
                  : Icons.favorite_rounded,
            ),
            title: Text(isFavorite ? l('common.remove') : l('action.favorite')),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await library.toggleFavorite(work);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: Text(l('action.addToPlaylist')),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await showAddToPlaylistSheet(context, work);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
