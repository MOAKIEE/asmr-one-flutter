import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/work_feed.dart';
import 'common.dart';
import 'work_card.dart';

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
  });

  final WorkFeed feed;
  final int columns;
  final bool listMode;
  final List<Widget> leadingSlivers;
  final double sectionSpacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = listMode ? 0.0 : 12.0;
        final available = constraints.maxWidth - padding.horizontal;
        final safeColumns = columns.clamp(1, 5);
        final itemWidth = safeColumns <= 1
            ? available
            : (available - spacing * (safeColumns - 1)) / safeColumns;

        return AnimatedBuilder(
          animation: feed,
          builder: (context, _) {
            final items = feed.items;
            final showSkeleton = feed.loading && items.isEmpty;
            final showError = feed.error != null && items.isEmpty;
            final showEmpty =
                !feed.loading && feed.error == null && items.isEmpty;

            return NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis != Axis.vertical) return false;
                if (n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
                  feed.loadMore();
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
                        onRetry: () => feed.load(),
                      ),
                    )
                  else if (showEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyView(
                        message: L10n.of(context)('search.noResult'),
                        icon: Icons.search_off_rounded,
                      ),
                    )
                  else if (listMode)
                    SliverPadding(
                      padding: EdgeInsets.only(
                        top: padding.top,
                        bottom: padding.bottom,
                      ),
                      sliver: SliverList.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) =>
                            WorkListTile(work: items[i]),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: padding,
                      sliver: SliverGrid.builder(
                        itemCount: items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: safeColumns,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: 18,
                          mainAxisExtent: itemWidth + WorkCard.textHeight,
                        ),
                        itemBuilder: (context, i) => WorkCard(work: items[i]),
                      ),
                    ),
                  if (items.isNotEmpty && feed.loadingMore)
                    const SliverToBoxAdapter(
                      child: LoadMoreIndicator(loading: true, hasMore: true),
                    ),
                  if (items.isNotEmpty && !feed.loadingMore && !feed.hasMore)
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
