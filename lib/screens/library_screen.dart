import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/app_info.dart';
import '../core/models/release.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/download_state.dart';
import '../state/library_state.dart';
import '../state/update_state.dart';
import '../widgets/common.dart';
import '../widgets/update_sheet.dart';
import 'downloads_screen.dart';
import 'library_lists.dart';
import 'login_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';

/// 「我的」页：账号状态 + 资料库入口。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final auth = context.watch<AuthState>();
    final library = context.watch<LibraryState>();
    final downloads = context.watch<DownloadState>();
    final updates = context.watchUpdateOrNull();
    final version = AppVersion.normalizeLabel(
      updates?.currentVersion ?? AppInfo.fallbackVersion,
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final activeDownloads = downloads.activeCount;
    final extraPad = (AppLayout.horizontalInset(context, maxWidth: 680) - 16)
        .clamp(0.0, double.infinity);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          extraPad,
          MediaQuery.paddingOf(context).top + 16,
          extraPad,
          32,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(l('library.title'), style: theme.textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  tooltip: l('settings.title'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  icon: Badge(
                    isLabelVisible: updates?.hasUnignoredUpdate == true,
                    backgroundColor: scheme.primary,
                    child: const Icon(Icons.settings_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _AccountCard(auth: auth),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _StatCard(
                  label: l('library.favorites'),
                  value: '${library.favoriteCount}',
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFFF6FB5),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                  ),
                ),
                const SizedBox(width: 10),
                _StatCard(
                  label: l('library.history'),
                  value: '${library.history.length}',
                  icon: Icons.history_rounded,
                  color: const Color(0xFF4FC3F7),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  ),
                ),
                const SizedBox(width: 10),
                _StatCard(
                  label: l('library.downloads'),
                  value: activeDownloads > 0
                      ? '$activeDownloads'
                      : Fmt.size(library.downloadBytes),
                  icon: Icons.download_rounded,
                  color: const Color(0xFF3DDC97),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppGroupCard(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _MenuTile(
                  icon: Icons.favorite_border_rounded,
                  title: l('library.favorites'),
                  subtitle: '${library.favoriteCount}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                  ),
                ),
                const Divider(indent: 62, endIndent: 16),
                _MenuTile(
                  icon: Icons.history_rounded,
                  title: l('library.history'),
                  subtitle: '${library.history.length}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  ),
                ),
                const Divider(indent: 62, endIndent: 16),
                _MenuTile(
                  icon: Icons.playlist_play_rounded,
                  title: l('library.playlists'),
                  subtitle: auth.hasToken
                      ? '${auth.playlists.length + library.localPlaylists.length}'
                      : '${library.localPlaylists.length}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PlaylistListScreen(),
                    ),
                  ),
                ),
                const Divider(indent: 62, endIndent: 16),
                _MenuTile(
                  icon: Icons.download_outlined,
                  title: l('library.downloads'),
                  subtitle: library.downloads.isEmpty
                      ? ''
                      : Fmt.size(library.downloadBytes),
                  badge: activeDownloads > 0 ? '$activeDownloads' : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (updates != null &&
              updates.hasUnignoredUpdate &&
              updates.latestRelease != null) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.tonalIcon(
                  onPressed: () => showUpdateSheet(
                    context,
                    release: updates.latestRelease!,
                    currentVersion: updates.currentVersion,
                    onIgnore: () =>
                        updates.ignoreRelease(updates.latestRelease!.tagName),
                  ),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.system_update_rounded, size: 17),
                  label: Text(
                    l('update.foundShort', {
                      'version': updates.latestRelease!.versionTag,
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${l('settings.version')} $version · ${ApiClient.instance.baseUrlHost}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => openExternalUrl(context, AppInfo.repoUrl),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.code_rounded,
                        size: 14,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'GitHub · ${AppInfo.repoSlug}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 12,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.auth});

  final AuthState auth;

  /// 头像占位字符：用户名可能为空，需回退到 '?'。
  static String _initial(String? name) {
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!auth.hasToken) {
      final fg = AppDecor.heroForeground(scheme);
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppDecor.heroGradient(scheme),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  color: fg,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  l('library.notLoggedIn'),
                  style: theme.textTheme.titleMedium?.copyWith(color: fg),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l('library.loginHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
              style: FilledButton.styleFrom(
                backgroundColor: AppDecor.heroButtonBg(scheme),
                foregroundColor: AppDecor.heroButtonFg(scheme),
              ),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(l('auth.login')),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primary.withValues(alpha: 0.18),
            child: Text(
              _AccountCard._initial(auth.user.name),
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  auth.user.group == null ? l('auth.guest') : auth.user.group!,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _confirmLogout(context, auth),
            child: Text(l('library.logout')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AuthState auth) async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l('library.logout')),
        content: Text(l('auth.logoutConfirm')),
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
    if (ok == true) await auth.logout();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: color.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(height: 9),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      shape: const RoundedRectangleBorder(),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 19, color: scheme.primary),
      ),
      title: Text(title),
      subtitle: (subtitle ?? '').isEmpty ? null : Text(subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                badge!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}
