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
  /// 封面下方文字区所需的高度（标题两行 + 两行元信息），
  /// 网格布局用它计算 mainAxisExtent，避免出现溢出条纹。
  static const double textHeight = 94;

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
    final theme = Theme.of(context);
    final settings = context.watch<SettingsState>();
    final isFav = showFavoriteMark
        ? context.select<LibraryState, bool>((s) => s.isFavorite(work.id))
        : false;

    return InkWell(
      onTap: onTap ?? () => openWork(context, work),
      borderRadius: BorderRadius.circular(AppDecor.radiusCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              CoverImage(
                url: work.mainCoverUrl,
                seedId: work.id,
                aspectRatio: 1,
                radius: 16,
                blur: settings.blurNsfw && work.nsfw,
              ),
              Positioned(
                left: 8,
                top: 8,
                child: AgeBadge(
                  nsfw: work.nsfw,
                  label: work.nsfw ? l('work.adult') : l('work.general'),
                  overlay: true,
                ),
              ),
              if (work.hasSubtitle)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _MiniBadge(
                    icon: Icons.subtitles_rounded,
                    color: Colors.black.withValues(alpha: 0.62),
                  ),
                ),
              if (isFav)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _MiniBadge(
                    icon: Icons.favorite_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
              if (work.isFree)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3DDC97).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l('work.free'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
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
                      child: Text(
                        work.circleName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    if (work.rateAverage > 0) ...[
                      const SizedBox(width: 6),
                      RatingBadge(rating: work.rateAverage, compact: true),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.download_rounded,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      Fmt.count(work.dlCount),
                      style: theme.textTheme.labelSmall,
                    ),
                    const Spacer(),
                    Text(
                      Fmt.price(work.price, l('work.free')),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: work.isFree
                            ? const Color(0xFF3DDC97)
                            : theme.colorScheme.primary,
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
  const _MiniBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 12, color: Colors.white),
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
                                  Fmt.count(work.dlCount),
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
                SizedBox(
                  height: 78,
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
    );
  }
}

/// 打开作品详情页。
void openWork(BuildContext context, Work work) {
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => WorkDetailScreen(work: work)));
}
