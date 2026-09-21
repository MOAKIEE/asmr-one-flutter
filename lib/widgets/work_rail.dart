import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/models/work.dart';
import '../l10n/app_localizations.dart';
import '../state/work_feed.dart';
import 'common.dart';
import 'work_card.dart';

/// 首页 / 详情页里的横向作品滑动区。
class WorkRail extends StatefulWidget {
  const WorkRail({
    super.key,
    required this.title,
    required this.query,
    this.icon,
    this.subtitle,
    this.onSeeAll,
    this.cardWidth = 146,
    this.pageSize = 12,
  });

  final String title;
  final WorkQuery query;
  final IconData? icon;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final double cardWidth;
  final int pageSize;

  @override
  State<WorkRail> createState() => _WorkRailState();
}

class _WorkRailState extends State<WorkRail> {
  late final WorkFeed _feed;

  @override
  void initState() {
    super.initState();
    _feed = WorkFeed(
      (page, pageSize) => ApiClient.instance.fetchWorks(
        widget.query.copyWith(page: page, pageSize: pageSize),
      ),
      pageSize: widget.pageSize,
      label: 'rail:${widget.title}',
    );
    _feed.load();
  }

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: widget.title,
          subtitle: widget.subtitle,
          icon: widget.icon,
          action: widget.onSeeAll == null ? null : l('common.seeAll'),
          onAction: widget.onSeeAll,
        ),
        SizedBox(
          height: widget.cardWidth + WorkCard.textHeight + 8,
          child: AnimatedBuilder(
            animation: _feed,
            builder: (context, _) {
              if (_feed.loading && _feed.items.isEmpty) {
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 4,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, _) => SizedBox(
                    width: widget.cardWidth,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(aspectRatio: 1, radius: 18),
                        SizedBox(height: 10),
                        ShimmerBox(height: 12, radius: 6),
                        SizedBox(height: 6),
                        ShimmerBox(height: 12, width: 64, radius: 6),
                      ],
                    ),
                  ),
                );
              }
              if (_feed.error != null && _feed.items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ErrorView(
                    message: _feed.error!,
                    compact: true,
                    onRetry: () => _feed.load(),
                  ),
                );
              }
              final items = _feed.items;
              return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.axis == Axis.horizontal &&
                      n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
                    _feed.loadMore();
                  }
                  return false;
                },
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length + (_feed.hasMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    if (i >= items.length) {
                      return SizedBox(
                        width: widget.cardWidth,
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                      );
                    }
                    return SizedBox(
                      width: widget.cardWidth,
                      child: WorkCard(work: items[i]),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
