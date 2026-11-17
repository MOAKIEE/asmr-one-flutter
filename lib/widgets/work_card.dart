import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/work.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../screens/work_detail_screen.dart';
import '../state/library_state.dart';
import '../state/settings_state.dart';
import 'common.dart';

/// 网格模式的作品卡片。
class WorkCard extends StatelessWidget {
  /// 根据当前字号缩放估算封面下方文字区所需的最小高度（标题两行 + 两行元信息），
  /// 供网格与横滑栏计算 `mainAxisExtent`，避免放大字号后发生溢出。
  static double textHeightFor(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final bodySize = text.bodyMedium?.fontSize ?? 14;
    final labelMedSize = text.labelMedium?.fontSize ?? 12;
    final labelSmallSize = text.labelSmall?.fontSize ?? 11;
    final titleH = scaler.scale(bodySize) * 1.35 * 2;
    final row1H = math.max(scaler.scale(labelMedSize) * 1.45, 16.0);
    final row2H = math.max(scaler.scale(labelSmallSize) * 1.45, 15.0);
    // 8 (封面与文字间距) + 6 (标题与元信息缓冲) + 3 (两行元信息间距) + 8 (字体渲染行距冗余)
    return (8 + titleH + 6 + row1H + 3 + row2H + 8).ceilToDouble();
  }

  const WorkCard({
    super.key,
    required this.work,
    this.onTap,
    this.showFavoriteMark = true,
  });

  final Work work;
  final VoidCallback? onTap;
  final bool showFavoriteMark;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final langCode = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final settings = context.watch<SettingsState>();
    final isFav = showFavoriteMark
        ? context.select<LibraryState, bool>((s) => s.isFavorite(work.id))
        : false;
    final textHeight = textHeightFor(context);

    return InkWell(
      onTap: onTap ?? () => openWork(context, work),
      borderRadius: BorderRadius.circular(AppDecor.radiusCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 115;
              final badgePad = compact ? 5.0 : 8.0;
              return Stack(
                children: [
                  CoverImage(
                    url: work.mainCoverUrl,
                    seedId: work.id,
                    aspectRatio: 1,
                    radius: compact ? 12 : 16,
                    blur: settings.blurNsfw && work.nsfw,
                  ),
                  Positioned(
                    left: badgePad,
                    right: badgePad,
                    top: badgePad,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: AgeBadge(
                              nsfw: work.nsfw,
                              label: work.nsfw
                                  ? l('work.adult')
                                  : l('work.general'),
                              overlay: true,
                            ),
                          ),
                        ),
                        if (work.hasSubtitle) ...[
                          const SizedBox(width: 4),
                          _MiniBadge(
                            icon: Icons.subtitles_rounded,
                            color: Colors.black.withValues(alpha: 0.62),
                            compact: compact,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (work.isFree || isFav)
                    Positioned(
                      left: badgePad,
                      right: badgePad,
                      bottom: badgePad,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (work.isFree)
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 5 : 7,
                                    vertical: compact ? 2 : 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF3DDC97,
                                    ).withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    l('work.free'),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w800,
                                      fontSize: compact ? 9 : 10,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          if (isFav) ...[
                            if (work.isFree) const SizedBox(width: 4),
                            _MiniBadge(
                              icon: Icons.favorite_rounded,
                              color: const Color(0xFFE0487B),
                              compact: compact,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: textHeight - 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  work.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        work.circleName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    if (work.rateAverage > 0) ...[
                      const SizedBox(width: 4),
                      Flexible(
                        flex: 2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: RatingBadge(
                            rating: work.rateAverage,
                            compact: true,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Icon(
                            Icons.download_rounded,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              Fmt.count(work.dlCount, languageCode: langCode),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      flex: 2,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          Fmt.price(work.price, l('work.free')),
                          maxLines: 1,
                          softWrap: false,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: work.isFree
                                ? const Color(0xFF3DDC97)
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.icon,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 3.5 : 4.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(compact ? 6 : 7),
      ),
      child: Icon(icon, size: compact ? 10.5 : 12, color: Colors.white),
    );
  }
}

/// 列表模式的作品行。
class WorkListTile extends StatelessWidget {
  const WorkListTile({
    super.key,
    required this.work,
    this.onTap,
    this.trailing,
    this.subtitleOverride,
  });

  final Work work;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final langCode = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = context.watch<SettingsState>();
    final isFav = context.select<LibraryState, bool>(
      (s) => s.isFavorite(work.id),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ?? () => openWork(context, work),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: CoverImage(
                      url: work.mainCoverUrl,
                      seedId: work.id,
                      radius: 12,
                      blur: settings.blurNsfw && work.nsfw,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 78),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            work.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.28,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitleOverride ?? work.circleName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (work.rateAverage > 0)
                                RatingBadge(
                                  rating: work.rateAverage,
                                  count: work.rateCount,
                                  compact: true,
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.download_rounded,
                                    size: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    Fmt.count(
                                      work.dlCount,
                                      languageCode: langCode,
                                    ),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                              if (work.duration != null && work.duration! > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        Fmt.duration(work.duration),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 78),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AgeBadge(
                          nsfw: work.nsfw,
                          label: work.nsfw ? l('work.adult') : l('work.general'),
                        ),
                        if (trailing != null)
                          trailing!
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isFav) ...[
                                Icon(
                                  Icons.favorite_rounded,
                                  size: 15,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                Fmt.price(work.price, l('work.free')),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: work.isFree
                                      ? const Color(0xFF3DDC97)
                                      : scheme.primary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 打开作品详情页。
void openWork(BuildContext context, Work work) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => WorkDetailScreen(work: work)));
}
