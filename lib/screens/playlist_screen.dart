import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/playlist.dart';
import '../core/storage/library_db.dart';
import '../core/models/work.dart';
import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/library_state.dart';
import '../state/settings_state.dart';
import '../widgets/common.dart';
import '../widgets/work_card.dart';

/// 播放列表总览：本地列表 + 云端列表。
class PlaylistListScreen extends StatelessWidget {
  const PlaylistListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final auth = context.watch<AuthState>();
    final library = context.watch<LibraryState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l('playlist.title')),
        actions: [
          IconButton(
            tooltip: l('playlist.create'),
            onPressed: () => showCreatePlaylistSheet(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (auth.hasToken) ...[
            SectionHeader(
              title: l('playlist.mine'),
              icon: Icons.cloud_outlined,
              action: l('common.reset'),
              onAction: () => auth.loadPlaylists(force: true),
            ),
            if (auth.playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l('playlist.empty'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final p in auth.playlists)
                _PlaylistTile(
                  name: p.name,
                  subtitle: l('playlist.worksCount', {'n': p.worksCount}),
                  trailing: p.isPublic
                      ? Icons.public_rounded
                      : Icons.lock_outline_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailScreen.cloud(playlist: p),
                    ),
                  ),
                ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: Text(l('playlist.needLogin')),
                  subtitle: Text(l('library.loginHint')),
                ),
              ),
            ),
          SectionHeader(
            title: l('playlist.local'),
            icon: Icons.folder_outlined,
          ),
          if (library.localPlaylists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l('playlist.empty'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final p in library.localPlaylists)
              _PlaylistTile(
                name: p.name,
                subtitle: l('playlist.worksCount', {'n': p.worksCount}),
                trailing: Icons.smartphone_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistDetailScreen.local(row: p),
                  ),
                ),
                onLongPress: () => _confirmDeleteLocal(context, library, p),
              ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteLocal(
    BuildContext context,
    LibraryState library,
    LocalPlaylistRow row,
  ) async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l('common.delete')),
        content: Text(row.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l('common.delete')),
          ),
        ],
      ),
    );
    if (ok == true) await library.deleteLocalPlaylist(row.id);
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.name,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.onLongPress,
  });

  final String name;
  final String subtitle;
  final IconData trailing;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: AppDecor.placeholderGradient(
            Theme.of(context).colorScheme,
            name.hashCode,
          ),
        ),
        child: const Icon(
          Icons.playlist_play_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: Icon(trailing, size: 18),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// 列表详情：本地列表直接读数据库，云端列表走接口。
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen.cloud({super.key, required Playlist playlist})
    : _cloud = playlist,
      _local = null;

  const PlaylistDetailScreen.local({super.key, required LocalPlaylistRow row})
    : _local = row,
      _cloud = null;

  final Playlist? _cloud;
  final LocalPlaylistRow? _local;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<Work> _works = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cloud = widget._cloud;
      final local = widget._local;
      if (cloud != null) {
        final detail = await context.read<AuthState>().fetchPlaylistDetail(
          cloud.id,
        );
        _works = detail.works;
      } else if (local != null) {
        _works = await context.read<LibraryState>().localPlaylistWorks(
          local.id,
        );
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _title => widget._cloud?.name ?? widget._local?.name ?? '';

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(title: Text(_title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? GridSkeleton(columns: settings.gridColumns)
          : _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _works.isEmpty
          ? EmptyView(
              message: l('playlist.empty'),
              icon: Icons.playlist_remove_rounded,
            )
          : WorkFeedViewStub(works: _works, columns: settings.gridColumns),
    );
  }
}

/// 静态作品网格（不参与分页）。
class WorkFeedViewStub extends StatelessWidget {
  const WorkFeedViewStub({super.key, required this.works, this.columns = 2});

  final List<Work> works;
  final int columns;

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
            final w = works[i];
            return WorkCard(work: w, onTap: () => openWork(context, w));
          },
        );
      },
    );
  }
}

/// 新建播放列表（云端或本地）。
Future<void> showCreatePlaylistSheet(BuildContext context) async {
  final l = L10n.of(context);
  final auth = context.read<AuthState>();
  final library = context.read<LibraryState>();
  final nameController = TextEditingController();
  final descController = TextEditingController();
  var privacy = 'private';
  var cloud = auth.hasToken;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l('playlist.create'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(labelText: l('playlist.name')),
                ),
                const SizedBox(height: 12),
                if (cloud) ...[
                  TextField(
                    controller: descController,
                    decoration: InputDecoration(
                      labelText: l('playlist.description'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l('playlist.privacy'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'private',
                        label: Text(l('playlist.privacy.private')),
                      ),
                      ButtonSegment(
                        value: 'known',
                        label: Text(l('playlist.privacy.known')),
                      ),
                      ButtonSegment(
                        value: 'public',
                        label: Text(l('playlist.privacy.public')),
                      ),
                    ],
                    selected: {privacy},
                    onSelectionChanged: (s) =>
                        setState(() => privacy = s.first),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;
                      if (cloud) {
                        await auth.createPlaylist(
                          name: name,
                          description: descController.text.trim(),
                          privacy: privacy,
                        );
                      } else {
                        await library.createLocalPlaylist(name);
                      }
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                    child: Text(l('common.create')),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

/// 「加入播放列表」选择面板。
Future<void> showAddToPlaylistSheet(BuildContext context, Work work) async {
  final l = L10n.of(context);
  final auth = context.read<AuthState>();
  final library = context.read<LibraryState>();
  final localIds = await library.localPlaylistIdsFor(work.id);

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                l('playlist.selectTarget'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(l('playlist.create')),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await showCreatePlaylistSheet(context);
              },
            ),
            const Divider(height: 1),
            if (auth.hasToken) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  l('playlist.mine'),
                  style: Theme.of(sheetContext).textTheme.labelMedium,
                ),
              ),
              if (auth.playlists.isEmpty)
                ListTile(
                  dense: true,
                  title: Text(l('playlist.empty')),
                  onTap: () => auth.loadPlaylists(force: true),
                )
              else
                for (final p in auth.playlists)
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: Text(p.name),
                    subtitle: Text(
                      l('playlist.worksCount', {'n': p.worksCount}),
                    ),
                    trailing: const Icon(Icons.add_rounded, size: 18),
                    onTap: () async {
                      final err = await auth.addWorkToPlaylist(p.id, work);
                      if (!sheetContext.mounted) return;
                      Navigator.of(sheetContext).pop();
                      _toast(
                        context,
                        err ?? l('playlist.addedTo', {'name': p.name}),
                      );
                    },
                  ),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                l('playlist.local'),
                style: Theme.of(sheetContext).textTheme.labelMedium,
              ),
            ),
            if (library.localPlaylists.isEmpty)
              ListTile(
                dense: true,
                title: Text(l('playlist.empty')),
                subtitle: Text(l('playlist.create')),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await showCreatePlaylistSheet(context);
                },
              )
            else
              for (final p in library.localPlaylists)
                ListTile(
                  leading: const Icon(Icons.smartphone_rounded),
                  title: Text(p.name),
                  subtitle: Text(l('playlist.worksCount', {'n': p.worksCount})),
                  trailing: localIds.contains(p.id)
                      ? const Icon(Icons.check_rounded, size: 18)
                      : const Icon(Icons.add_rounded, size: 18),
                  onTap: () async {
                    if (localIds.contains(p.id)) {
                      await library.removeFromLocalPlaylist(p.id, work.id);
                    } else {
                      await library.addToLocalPlaylist(p.id, work);
                    }
                    if (!sheetContext.mounted) return;
                    Navigator.of(sheetContext).pop();
                    _toast(
                      context,
                      localIds.contains(p.id)
                          ? l('playlist.removed')
                          : l('playlist.addedTo', {'name': p.name}),
                    );
                  },
                ),
          ],
        ),
      );
    },
  );
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
