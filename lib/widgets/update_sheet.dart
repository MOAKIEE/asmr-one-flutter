import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api/update_client.dart';
import '../core/app_info.dart';
import '../core/models/release.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/update_state.dart';
import 'common.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

/// 在外部浏览器打开链接；无法唤起时复制到剪贴板并提示。
Future<bool> openExternalUrl(
  BuildContext context,
  String url, {
  ExternalUrlLauncher? launcher,
}) async {
  final copiedLabel = L10n.of(context)('common.copied');
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri.tryParse(url);
  if (uri == null) return false;

  var opened = false;
  try {
    opened = launcher != null
        ? await launcher(uri)
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }

  if (!opened) {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copiedLabel)));
  }
  return opened;
}

/// 触发手动检查更新并按结果展示弹窗或提示条。
Future<void> runManualUpdateCheck(
  BuildContext context, {
  ExternalUrlLauncher? launcher,
}) async {
  final updates = context.readUpdateOrNull();
  if (updates == null) return;

  final outcome = await updates.checkForUpdates(manual: true);
  if (!context.mounted) return;

  final l = L10n.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  switch (outcome) {
    case UpdateCheckOutcome.available:
      final release = updates.latestRelease;
      if (release == null) return;
      await showUpdateSheet(
        context,
        release: release,
        currentVersion: updates.currentVersion,
        showIgnoreAction: !updates.isIgnored(release.tagName),
        onIgnore: () => updates.ignoreRelease(release.tagName),
        launcher: launcher,
      );
    case UpdateCheckOutcome.upToDate:
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l('update.upToDateDetail', {
                'version': AppVersion.normalizeLabel(updates.currentVersion),
              }),
            ),
          ),
        );
    case UpdateCheckOutcome.failed:
      final message = switch (updates.lastError) {
        UpdateErrorKind.network => l('update.errorNetwork'),
        UpdateErrorKind.rateLimited => l('update.errorRateLimited'),
        UpdateErrorKind.invalidResponse ||
        UpdateErrorKind.unknown ||
        null => l('update.errorFailed'),
      };
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: l('update.openReleasesPage'),
              onPressed: () {
                if (context.mounted) {
                  openExternalUrl(
                    context,
                    AppInfo.releasesUrl,
                    launcher: launcher,
                  );
                }
              },
            ),
          ),
        );
    case UpdateCheckOutcome.skipped:
      return;
  }
}

/// 展示版本更新详情底部面板。
Future<void> showUpdateSheet(
  BuildContext context, {
  required ReleaseInfo release,
  required String currentVersion,
  bool showIgnoreAction = true,
  Future<void> Function()? onIgnore,
  ExternalUrlLauncher? launcher,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) => UpdateSheet(
      release: release,
      currentVersion: currentVersion,
      showIgnoreAction: showIgnoreAction,
      onIgnore: onIgnore,
      launcher: launcher,
    ),
  );
}

/// 紧凑的更新状态角标（与下载计数徽章视觉统一）。
class UpdateBadge extends StatelessWidget {
  const UpdateBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// 版本更新详情底部面板内容。
class UpdateSheet extends StatelessWidget {
  const UpdateSheet({
    super.key,
    required this.release,
    required this.currentVersion,
    this.showIgnoreAction = true,
    this.onIgnore,
    this.launcher,
  });

  final ReleaseInfo release;
  final String currentVersion;
  final bool showIgnoreAction;
  final Future<void> Function()? onIgnore;
  final ExternalUrlLauncher? launcher;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentTag = 'v${AppVersion.normalizeLabel(currentVersion)}';
    final published = release.publishedAt?.toLocal();
    final publishedText = published == null
        ? null
        : Fmt.date(
            '${published.year.toString().padLeft(4, '0')}-'
            '${published.month.toString().padLeft(2, '0')}-'
            '${published.day.toString().padLeft(2, '0')}',
          );
    final apks = release.apkAssets;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部：标题、版本对比与发布日期
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    color: scheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l('update.availableTitle'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _VersionPill(
                            label: currentTag,
                            highlighted: false,
                          ),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          _VersionPill(
                            label: release.versionTag,
                            highlighted: true,
                          ),
                          if (publishedText != null)
                            Text(
                              l('update.publishedAt', {'date': publishedText}),
                              style: theme.textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 中间可滚动区域：更新内容与 APK 资产列表
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l('update.changelog'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: release.body.isEmpty
                        ? Text(
                            l('update.noChangelog'),
                            style: theme.textTheme.bodySmall,
                          )
                        : _ReleaseNotesView(markdown: release.body),
                  ),
                  if (apks.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      l('update.apkDownloads'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppGroupCard(
                      radius: 16,
                      color: scheme.surfaceContainer,
                      child: Column(
                        children: [
                          for (var i = 0; i < apks.length; i++) ...[
                            if (i > 0)
                              const Divider(indent: 52, endIndent: 14),
                            _ApkAssetTile(
                              asset: apks[i],
                              onTap: () => openExternalUrl(
                                context,
                                apks[i].downloadUrl,
                                launcher: launcher,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 底部固定操作栏
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () => openExternalUrl(
                      context,
                      release.htmlUrl,
                      launcher: launcher,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(l('update.openRelease')),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      if (showIgnoreAction && onIgnore != null)
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            await onIgnore!();
                            if (context.mounted) Navigator.of(context).pop();
                          },
                          child: Text(l('update.ignoreVersion')),
                        ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l('update.later')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({required this.label, required this.highlighted});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primary.withValues(alpha: 0.16)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: highlighted
            ? Border.all(color: scheme.primary.withValues(alpha: 0.45))
            : null,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: highlighted ? scheme.primary : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ApkAssetTile extends StatelessWidget {
  const _ApkAssetTile({required this.asset, required this.onTap});

  final ReleaseAsset asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Icon(Icons.android_rounded, color: scheme.primary, size: 22),
      title: Text(
        asset.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (asset.size > 0)
            Text(Fmt.size(asset.size), style: theme.textTheme.labelSmall),
          if (asset.isRecommendedApk)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l('update.recommended'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      trailing: const Icon(Icons.download_rounded, size: 20),
      onTap: onTap,
    );
  }
}

/// 轻量 Release Notes 展示器：格式化常见 Markdown 标题、列表、加粗与行内代码。
class _ReleaseNotesView extends StatelessWidget {
  const _ReleaseNotesView({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final children = <Widget>[];
    var pendingGap = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        if (children.isNotEmpty) pendingGap = true;
        continue;
      }

      if (pendingGap) {
        children.add(const SizedBox(height: 8));
        pendingGap = false;
      }

      final headingMatch = RegExp(r'^#{1,4}\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: 6));
        }
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              headingMatch.group(1)!.trim(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        );
        continue;
      }

      final bulletMatch = RegExp(r'^[-*]\s+(.+)$').firstMatch(line);
      if (bulletMatch != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 8),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: _InlineMarkdownText(text: bulletMatch.group(1)!),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _InlineMarkdownText(text: line),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _InlineMarkdownText extends StatelessWidget {
  const _InlineMarkdownText({required this.text});

  final String text;

  static final RegExp _tokenPattern = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurface.withValues(alpha: 0.88),
      height: 1.5,
    );

    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _tokenPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('**') && token.endsWith('**') && token.length > 4) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: baseStyle?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        );
      } else if (token.startsWith('`') &&
          token.endsWith('`') &&
          token.length > 2) {
        spans.add(
          TextSpan(
            text: ' ${token.substring(1, token.length - 1)} ',
            style: baseStyle?.copyWith(
              color: scheme.primary,
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: token));
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}
