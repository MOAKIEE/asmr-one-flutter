import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../state/auth_state.dart';
import '../state/download_state.dart';
import '../state/library_state.dart';
import '../state/player_state.dart';
import '../state/settings_state.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

/// 设置页。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = context.watch<SettingsState>();
    final auth = context.watch<AuthState>();

    return Scaffold(
      appBar: AppBar(title: Text(l('settings.title'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // ---------------- 外观 ----------------
          SectionHeader(
            title: l('settings.appearance'),
            icon: Icons.palette_outlined,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RowLabel(l('settings.theme')),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l('settings.theme.system')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l('settings.theme.light')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l('settings.theme.dark')),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => settings.themeMode = s.first,
                ),
                const SizedBox(height: 20),
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
                const SizedBox(height: 8),
                _RowLabel(l('settings.language')),
                const SizedBox(height: 4),
                _LanguageSelector(settings: settings),
                const SizedBox(height: 20),
                _RowLabel('${l('browse.gridView')} · ${settings.gridColumns}'),
                Slider(
                  value: settings.gridColumns.toDouble(),
                  min: 1,
                  max: 4,
                  divisions: 3,
                  label: '${settings.gridColumns}',
                  onChanged: (v) => settings.gridColumns = v.round(),
                ),
              ],
            ),
          ),

          // ---------------- 内容 ----------------
          SectionHeader(
            title: l('settings.content'),
            icon: Icons.shield_outlined,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.no_adult_content_rounded),
            title: Text(l('settings.showNsfw')),
            value: settings.showNsfw,
            onChanged: (v) => settings.showNsfw = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.blur_on_rounded),
            title: Text(l('settings.blurNsfw')),
            value: settings.blurNsfw,
            onChanged: (v) => settings.blurNsfw = v,
          ),

          // ---------------- 网络 ----------------
          SectionHeader(title: l('settings.network'), icon: Icons.wifi_rounded),
          SwitchListTile(
            secondary: const Icon(Icons.auto_mode_rounded),
            title: Text(l('settings.lineAuto')),
            subtitle: Text(
              l('settings.lineCurrent', {'host': settings.currentHost}),
            ),
            value: settings.autoSelectLine,
            onChanged: (v) => settings.autoSelectLine = v,
          ),
          if (!settings.autoSelectLine)
            for (var i = 0; i < ApiClient.baseUrls.length; i++)
              ListTile(
                leading: Icon(
                  settings.preferredLineIndex == i
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: Text(Uri.parse(ApiClient.baseUrls[i]).host),
                onTap: () => settings.preferredLineIndex = i,
              ),

          // ---------------- 播放 ----------------
          SectionHeader(
            title: l('settings.playback'),
            icon: Icons.headphones_rounded,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.data_saver_on_rounded),
            title: Text(l('player.lowQuality')),
            value: settings.preferLowQuality,
            onChanged: (v) => settings.preferLowQuality = v,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.skip_next_rounded),
            title: Text(l('player.autoNext')),
            value: settings.autoPlayNext,
            onChanged: (v) => settings.autoPlayNext = v,
          ),
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: Text(l('player.speed')),
            subtitle: Text('${settings.playbackSpeed}x'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickSpeed(context, settings),
          ),

          // ---------------- 存储 ----------------
          SectionHeader(
            title: l('settings.storage'),
            icon: Icons.sd_storage_outlined,
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(l('settings.clearCache')),
            onTap: () async {
              await DefaultCacheManager().emptyCache();
              if (context.mounted) _toast(context, l('settings.cacheCleared'));
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(l('settings.clearData')),
            subtitle: Text(l('settings.clearDataConfirm')),
            onTap: () => _confirmClear(context, settings, auth),
          ),

          // ---------------- 关于 ----------------
          SectionHeader(
            title: l('settings.about'),
            icon: Icons.info_outline_rounded,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              l('settings.aboutText'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(height: 1.5),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(l('auth.login')),
            subtitle: Text(
              auth.hasToken
                  ? (auth.user.displayName)
                  : l('library.notLoggedIn'),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.tag_rounded),
            title: Text(l('settings.version')),
            trailing: Text('1.0.0 (${settings.currentHost})'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSpeed(BuildContext context, SettingsState settings) async {
    final l = L10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l('player.speed'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final v in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                leading: Icon(
                  settings.playbackSpeed == v
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: Text('${v}x'),
                onTap: () {
                  settings.playbackSpeed = v;
                  // 立即作用于当前播放。
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
    AuthState auth,
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
    // 先删掉本地的离线音频文件，再清空数据库记录。
    for (final row in library.downloads) {
      await downloads.deleteFile(row);
    }
    await library.clearAllLocalData();
    await settings.clearSearchHistory();
    if (!context.mounted) return;
    _toast(context, l('settings.cleared'));
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 界面语言选择器。
class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.settings});

  final SettingsState settings;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final current = settings.locale;
    final options = <(String, Locale?)>[
      (l('settings.language.system'), null),
      ('简体中文', const Locale('zh', 'CN')),
      ('日本語', const Locale('ja', 'JP')),
      ('English', const Locale('en', 'US')),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, locale) in options)
          ChoiceChip(
            label: Text(label),
            selected:
                current?.languageCode == locale?.languageCode &&
                current?.countryCode == locale?.countryCode,
            onSelected: (_) => settings.locale = locale,
          ),
      ],
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
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
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
