import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/app_info.dart';
import '../core/models/release.dart';
import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/download_state.dart';
import '../state/library_state.dart';
import '../state/player_state.dart';
import '../state/settings_state.dart';
import '../state/update_state.dart';
import '../widgets/common.dart';
import '../widgets/player_scaffold.dart';
import '../widgets/update_sheet.dart';
import 'backup_screen.dart';
import 'login_screen.dart';

/// 设置页：顶部账号入口 + 5 组紧凑设置卡片 + 底部版本尾注。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();
    final auth = context.watch<AuthState>();
    final updates = context.watchUpdateOrNull();
    final version = AppVersion.normalizeLabel(
      updates?.currentVersion ?? AppInfo.fallbackVersion,
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final extraPad = (AppLayout.horizontalInset(context, maxWidth: 680) - 16)
        .clamp(0.0, double.infinity);

    return PlayerScaffold(
      appBar: AppBar(title: Text(l('settings.title'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(extraPad, 8, extraPad, 40),
        children: [
          // ---------------- 账号 ----------------
          _GroupCard(
            child: _AccountTile(
              auth: auth,
              onTap: () => _handleAccountTap(context, auth),
            ),
          ),

          // ---------------- 外观 ----------------
          SectionHeader(
            title: l('settings.appearance'),
            icon: Icons.palette_outlined,
          ),
          _GroupCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.contrast_rounded),
                  title: Text(l('settings.themeAndColor')),
                  subtitle: Text(_themeSummary(l, settings)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: settings.effectiveAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.outlineVariant,
                            width: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () => _openAppearanceSheet(context),
                ),
                const Divider(indent: 56, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.translate_rounded),
                  title: Text(l('settings.language')),
                  subtitle: Text(_languageLabel(l, settings.locale)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openLanguageSheet(context),
                ),
                const Divider(indent: 56, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.grid_view_rounded),
                  title: Text(
                    '${l('settings.gridColumns')} · ${settings.gridColumns}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openGridColumnsSheet(context),
                ),
              ],
            ),
          ),

          // ---------------- 内容与网络 ----------------
          SectionHeader(
            title: l('settings.contentAndNetwork'),
            icon: Icons.shield_outlined,
          ),
          _GroupCard(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.no_adult_content_rounded),
                  title: Text(l('settings.showNsfw')),
                  value: settings.showNsfw,
                  onChanged: (v) => settings.showNsfw = v,
                ),
                const Divider(indent: 56, endIndent: 16),
                SwitchListTile(
                  secondary: const Icon(Icons.blur_on_rounded),
                  title: Text(l('settings.blurNsfw')),
                  value: settings.blurNsfw,
                  onChanged: (v) => settings.blurNsfw = v,
                ),
                const Divider(indent: 56, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.wifi_rounded),
                  title: Text(l('settings.line')),
                  subtitle: Text(
                    settings.autoSelectLine
                        ? '${l('settings.lineAutoShort')} · ${settings.currentHost}'
                        : settings.currentHost,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openLineSheet(context),
                ),
              ],
            ),
          ),

          // ---------------- 播放 ----------------
          SectionHeader(
            title: l('settings.playback'),
            icon: Icons.headphones_rounded,
          ),
          _GroupCard(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.data_saver_on_rounded),
                  title: Text(l('player.lowQuality')),
                  value: settings.preferLowQuality,
                  onChanged: (v) => settings.preferLowQuality = v,
                ),
                const Divider(indent: 56, endIndent: 16),
                SwitchListTile(
                  secondary: const Icon(Icons.skip_next_rounded),
                  title: Text(l('player.autoNext')),
                  value: settings.autoPlayNext,
                  onChanged: (v) => settings.autoPlayNext = v,
                ),
                const Divider(indent: 56, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.speed_rounded),
                  title: Text(l('player.speed')),
                  subtitle: Text('${settings.playbackSpeed}x'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _pickSpeed(context, settings),
                ),
              ],
            ),
          ),

          // ---------------- 存储 ----------------
          SectionHeader(
            title: l('settings.storage'),
            icon: Icons.sd_storage_outlined,
          ),
          _GroupCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.import_export_rounded),
                  title: Text(l('backup.title')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BackupScreen()),
                  ),
                ),
                const Divider(indent: 56, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(l('settings.clearCache')),
                  onTap: () async {
                    await DefaultCacheManager().emptyCache();
                    if (context.mounted) {
                      _toast(context, l('settings.cacheCleared'));
                    }
                  },
                ),
                const Divider(indent: 56, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: scheme.error,
                  ),
                  title: Text(
                    l('settings.clearData'),
                    style: TextStyle(color: scheme.error),
                  ),
                  onTap: () => _confirmClear(context, settings),
                ),
              ],
            ),
          ),

          // ---------------- 关于 ----------------
          SectionHeader(
            title: l('settings.about'),
            icon: Icons.info_outline_rounded,
          ),
          _GroupCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update_rounded),
                  title: Text(l('settings.checkUpdate')),
                  subtitle: _buildUpdateSubtitle(context, l, updates, version),
                  trailing: _buildUpdateTrailing(updates),
                  onTap: updates == null || updates.checking
                      ? null
                      : () {
                          if (updates.hasUpdate &&
                              updates.latestRelease != null) {
                            final release = updates.latestRelease!;
                            showUpdateSheet(
                              context,
                              release: release,
                              currentVersion: updates.currentVersion,
                              showIgnoreAction: !updates.isIgnored(
                                release.tagName,
                              ),
                              onIgnore: () =>
                                  updates.ignoreRelease(release.tagName),
                            );
                          } else {
                            runManualUpdateCheck(context);
                          }
                        },
                ),
                const Divider(indent: 56, endIndent: 16),
                SwitchListTile(
                  secondary: const Icon(Icons.autorenew_rounded),
                  title: Text(l('settings.autoCheckUpdate')),
                  value: updates?.autoCheckUpdate ?? true,
                  onChanged: updates == null
                      ? null
                      : (v) => updates.autoCheckUpdate = v,
                ),
                const Divider(indent: 56, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: Text(l('settings.githubRepo')),
                  subtitle: const Text(AppInfo.repoDisplayUrl),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 19),
                  onTap: () => openExternalUrl(context, AppInfo.repoUrl),
                  onLongPress: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: AppInfo.repoUrl),
                    );
                    if (context.mounted) {
                      _toast(context, l('common.copied'));
                    }
                  },
                ),
              ],
            ),
          ),

          // 底部版本与免责尾注
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            child: Column(
              children: [
                Text(
                  '${l('app.name')} · ${l('settings.version')} v$version',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l('settings.aboutText'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _themeSummary(L10n l, SettingsState settings) {
    final mode = switch (settings.themeMode) {
      ThemeMode.system => l('settings.theme.system'),
      ThemeMode.light => l('settings.theme.light'),
      ThemeMode.dark => l('settings.theme.dark'),
    };
    return settings.useCoverAccent ? '$mode · ${l('settings.coverAccent')}' : mode;
  }

  String _languageLabel(L10n l, Locale? locale) {
    if (locale == null) return l('settings.language.system');
    return switch (locale.languageCode) {
      'zh' => '简体中文',
      'ja' => '日本語',
      'en' => 'English',
      _ => l('settings.language.system'),
    };
  }

  Future<void> _openAppearanceSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const _AppearanceSheet(),
    );
  }

  Future<void> _openLanguageSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) {
        final l = L10n.of(sheetContext);
        final settings = sheetContext.watch<SettingsState>();
        final current = settings.locale;
        final options = <(String, Locale?)>[
          (l('settings.language.system'), null),
          ('简体中文', const Locale('zh', 'CN')),
          ('日本語', const Locale('ja', 'JP')),
          ('English', const Locale('en', 'US')),
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l('settings.language'),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              for (final (label, locale) in options)
                ListTile(
                  leading: Icon(
                    current?.languageCode == locale?.languageCode &&
                            current?.countryCode == locale?.countryCode
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color:
                        current?.languageCode == locale?.languageCode &&
                            current?.countryCode == locale?.countryCode
                        ? Theme.of(sheetContext).colorScheme.primary
                        : null,
                  ),
                  title: Text(label),
                  onTap: () {
                    settings.locale = locale;
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openGridColumnsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) {
        final l = L10n.of(sheetContext);
        final settings = sheetContext.watch<SettingsState>();
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l('settings.gridColumns'),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              for (final count in const [1, 2, 3, 4])
                ListTile(
                  leading: Icon(
                    settings.gridColumns == count
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: settings.gridColumns == count
                        ? scheme.primary
                        : null,
                  ),
                  title: Text('$count'),
                  onTap: () {
                    settings.gridColumns = count;
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openLineSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) {
        final l = L10n.of(sheetContext);
        final settings = sheetContext.watch<SettingsState>();
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l('settings.line'),
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.auto_mode_rounded),
                  title: Text(l('settings.lineAuto')),
                  subtitle: Text(
                    l('settings.lineCurrent', {'host': settings.currentHost}),
                  ),
                  value: settings.autoSelectLine,
                  onChanged: (v) => settings.autoSelectLine = v,
                ),
                if (!settings.autoSelectLine) ...[
                  const Divider(height: 1),
                  for (var i = 0; i < ApiClient.baseUrls.length; i++)
                    ListTile(
                      leading: Icon(
                        settings.preferredLineIndex == i
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: settings.preferredLineIndex == i
                            ? scheme.primary
                            : null,
                      ),
                      title: Text(Uri.parse(ApiClient.baseUrls[i]).host),
                      onTap: () {
                        settings.preferredLineIndex = i;
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickSpeed(BuildContext context, SettingsState settings) async {
    final l = L10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l('player.speed'),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            for (final v in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                leading: Icon(
                  settings.playbackSpeed == v
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: settings.playbackSpeed == v
                      ? Theme.of(sheetContext).colorScheme.primary
                      : null,
                ),
                title: Text('${v}x'),
                onTap: () {
                  settings.playbackSpeed = v;
                  sheetContext.read<PlayerState>().setSpeed(v);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    SettingsState settings,
  ) async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l('settings.clearData')),
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
    if (!context.mounted) return;

    final library = context.read<LibraryState>();
    final downloads = context.read<DownloadState>();
    await context.read<PlayerState>().stop();
    final failed = await downloads.clearAll();
    await library.clearAllLocalData();
    await settings.clearSearchHistory();
    if (!context.mounted) return;
    _toast(
      context,
      failed == 0
          ? l('settings.cleared')
          : l('settings.clearedWithFailures', {'n': failed}),
    );
  }

  Future<void> _handleAccountTap(BuildContext context, AuthState auth) async {
    if (!auth.hasToken) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }
    final l = L10n.of(context);
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(auth.user.displayName),
        content: Text(l('auth.logoutConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: Text(l('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('switch'),
            child: Text(l('auth.login')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('logout'),
            child: Text(l('library.logout')),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'logout') {
      await auth.logout();
    } else if (action == 'switch') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Widget _buildUpdateSubtitle(
    BuildContext context,
    L10n l,
    UpdateState? updates,
    String version,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (updates?.checking == true) {
      return Text(l('settings.checkingUpdate'));
    }
    if (updates != null && updates.hasUpdate && updates.latestRelease != null) {
      return Text(
        l('update.availableTitle'),
        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      );
    }
    if (updates?.status == UpdateStatus.upToDate) {
      return Text(l('update.upToDate'));
    }
    return Text('v$version');
  }

  Widget _buildUpdateTrailing(UpdateState? updates) {
    if (updates?.checking == true) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    }
    if (updates != null && updates.hasUpdate && updates.latestRelease != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UpdateBadge(label: updates.latestRelease!.versionTag),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded),
        ],
      );
    }
    return const Icon(Icons.chevron_right_rounded);
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.auth, required this.onTap});

  final AuthState auth;
  final VoidCallback onTap;

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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: scheme.primary.withValues(alpha: 0.14),
        child: auth.hasToken
            ? Text(
                _initial(auth.user.name),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              )
            : Icon(
                Icons.person_outline_rounded,
                color: scheme.primary,
                size: 20,
              ),
      ),
      title: Text(
        auth.hasToken
            ? l('settings.loggedInAs', {'name': auth.user.displayName})
            : l('auth.login'),
      ),
      subtitle: Text(
        auth.hasToken
            ? (auth.user.group ?? l('auth.guest'))
            : l('library.notLoggedIn'),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

/// 外观与主题配置面板（主题模式 + 强调色 + 封面取色）。
class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l('settings.appearance'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _RowLabel(l('settings.theme')),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l('settings.theme.system'), maxLines: 1),
                    ),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l('settings.theme.light'), maxLines: 1),
                    ),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l('settings.theme.dark'), maxLines: 1),
                    ),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) => settings.themeMode = s.first,
              ),
            ),
            const SizedBox(height: 18),
            _RowLabel(l('settings.accent')),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in AppTheme.accentChoices)
                  _Swatch(
                    color: color,
                    selected: settings.accentSeed == color.toARGB32(),
                    onTap: () => settings.accentSeed = color.toARGB32(),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l('settings.coverAccent')),
              subtitle: Text(l('settings.coverAccentHint')),
              value: settings.useCoverAccent,
              onChanged: (v) {
                settings.useCoverAccent = v;
                if (!v) settings.setDynamicAccent(null);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppGroupCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.4,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}
