import 'package:flutter/material.dart';

import '../core/models/work.dart';
import '../l10n/app_localizations.dart';
import '../state/work_feed.dart';
import 'app_motion.dart';
import 'common.dart';
import 'work_card.dart';

/// 作品网格与骨架屏共用的列数与尺寸计算。
class WorkGridLayout {
  const WorkGridLayout._();

  /// 宽屏下若使用默认的 2 列则按可用宽度自动扩展列数，避免单卡过大。
  static int effectiveColumns(double availableWidth, int preferredColumns) {
    final safe = preferredColumns.clamp(1, 5);
    if (availableWidth >= 600 && safe == 2) {
      return (availableWidth / 210).floor().clamp(2, 5);
    }
    return safe;
  }

  static SliverGridDelegateWithFixedCrossAxisCount delegate(
    BuildContext context, {
    required double availableWidth,
    required int columns,
    double spacing = 12,
    double mainAxisSpacing = 18,
  }) {
    final cols = effectiveColumns(availableWidth, columns);
    final itemWidth = cols <= 1
        ? availableWidth
        : (availableWidth - spacing * (cols - 1)) / cols;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      crossAxisSpacing: spacing,
      mainAxisSpacing: mainAxisSpacing,
      mainAxisExtent: itemWidth + WorkCard.textHeightFor(context),
    );
  }
}

/// 静态作品网格（收藏列表、播放列表详情等非分页场景共用）。
class StaticWorkGrid extends StatelessWidget {
  const StaticWorkGrid({
    super.key,
    required this.works,
    this.columns = 2,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 28),
    this.onLongPress,
  });

  final List<Work> works;
  final int columns;
  final EdgeInsets padding;
  final void Function(Work work)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - padding.horizontal;
        return GridView.builder(
          padding: padding,
          gridDelegate: WorkGridLayout.delegate(
            context,
            availableWidth: available,
            columns: columns,
          ),
          itemCount: works.length,
          itemBuilder: (context, i) {
            final work = works[i];
            final card = WorkCard(work: work);
            if (onLongPress == null) return card;
            return GestureDetector(
              onLongPress: () => onLongPress!(work),
              child: card,
            );
          },
        );
      },
    );
  }
}

/// 作品列表视图：统一处理骨架屏、错误、空态、无限滚动与网格 / 列表两种布局。
///
/// 以 sliver 形式对外暴露，方便与页面头部（筛选栏、搜索结果统计等）拼装。
class WorkFeedView extends StatelessWidget {
  const WorkFeedView({
    super.key,
    required this.feed,
    this.columns = 2,
    this.listMode = false,
    this.leadingSlivers = const [],
    this.sectionSpacing = 0,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 28),
    this.emptyMessage,
    this.errorActionBuilder,
  });

  final WorkFeed feed;
  final int columns;
  final bool listMode;
  final List<Widget> leadingSlivers;
  final double sectionSpacing;
  final EdgeInsets padding;
  final String? emptyMessage;
  final Widget? Function(BuildContext context, WorkFeed feed)?
  errorActionBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - padding.horizontal;
        final safeColumns = WorkGridLayout.effectiveColumns(available, columns);

        return AnimatedBuilder(
          animation: feed,
          builder: (context, _) {
            final items = feed.items;
            final showSkeleton = feed.loading && items.isEmpty;
            final showError = feed.error != null && items.isEmpty;
            final showEmpty =
                feed.isEmpty && !feed.loading && feed.error == null;
            final showFilteredContinue =
                feed.loadedOnce &&
                items.isEmpty &&
                feed.hasMore &&
                !feed.loading &&
                !feed.loadingMore &&
                feed.error == null;

            return NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis != Axis.vertical) return false;
                if (feed.error == null &&
                    feed.hasMore &&
                    !feed.loadingMore &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (feed.error == null) feed.loadMore();
                  });
                }
                return false;
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  ...leadingSlivers,
                  if (sectionSpacing > 0)
                    SliverToBoxAdapter(child: SizedBox(height: sectionSpacing)),
                  if (showSkeleton)
                    SliverPadding(
                      padding: padding,
                      sliver: SliverToBoxAdapter(
                        child: GridSkeleton(
                          columns: safeColumns,
                          count: safeColumns * 3,
                        ),
                      ),
                    )
                  else if (showError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ErrorView(
                        message: feed.error ?? '',
                        icon: feed.errorIsAuth
                            ? Icons.lock_outline_rounded
                            : Icons.cloud_off_rounded,
                        action: errorActionBuilder?.call(context, feed),
                        onRetry: () => feed.load(),
                      ),
                    )
                  else if (showFilteredContinue)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyView(
                        message: L10n.of(context)('similar.loadMoreFiltered'),
                        icon: Icons.filter_alt_outlined,
                        action: FilledButton.tonalIcon(
                          onPressed: feed.loadMore,
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          label: Text(L10n.of(context)('common.loadMore')),
                        ),
                      ),
                    )
                  else if (showEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyView(
                        message:
                            emptyMessage ?? L10n.of(context)('search.noResult'),
                        icon: Icons.search_off_rounded,
                      ),
                    )
                  else if (listMode)
                    SliverPadding(
                      padding: EdgeInsets.only(
                        top: padding.top,
                        bottom: padding.bottom,
                      ),
                      sliver: FeedEntrance(
                        builder: (entrance) => SliverList.builder(
                          itemCount: items.length,
                          itemBuilder: (context, i) =>
                              entrance(i, WorkListTile(work: items[i])),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: padding,
                      sliver: FeedEntrance(
                        builder: (entrance) => SliverGrid.builder(
                          itemCount: items.length,
                          gridDelegate: WorkGridLayout.delegate(
                            context,
                            availableWidth: available,
                            columns: columns,
                          ),
                          itemBuilder: (context, i) => entrance(
                            i ~/ safeColumns,
                            WorkCard(work: items[i]),
                          ),
                        ),
                      ),
                    ),
                  if (items.isNotEmpty && feed.loadingMore)
                    const SliverToBoxAdapter(
                      child: LoadMoreIndicator(loading: true, hasMore: true),
                    ),
                  if (items.isNotEmpty &&
                      !feed.loadingMore &&
                      feed.error != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              feed.error!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: feed.loadMore,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: Text(L10n.of(context)('common.retry')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (items.isNotEmpty &&
                      !feed.loadingMore &&
                      feed.error == null &&
                      !feed.hasMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 28),
                        child: Center(
                          child: Text(
                            L10n.of(context)('common.noMore'),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
