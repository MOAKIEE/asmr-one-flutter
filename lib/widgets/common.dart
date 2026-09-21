import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// 封面图：带渐变占位、可选模糊（成人内容打码）与圆角。
class CoverImage extends StatefulWidget {
  const CoverImage({
    super.key,
    required this.url,
    required this.seedId,
    this.aspectRatio = 1.0,
    this.radius = 16,
    this.blur = false,
    this.fit = BoxFit.cover,
    this.showRevealButton = true,
    this.onTap,
  });

  final String url;

  /// 用于生成稳定的占位渐变色。
  final int seedId;
  final double aspectRatio;
  final double radius;
  final bool blur;
  final BoxFit fit;
  final bool showRevealButton;
  final VoidCallback? onTap;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shouldBlur = widget.blur && !_revealed;

    Widget image = widget.url.isEmpty
        ? _placeholder(scheme)
        : CachedNetworkImage(
            imageUrl: widget.url,
            fit: widget.fit,
            fadeInDuration: const Duration(milliseconds: 220),
            placeholder: (_, _) => _placeholder(scheme),
            errorWidget: (_, _, _) => _placeholder(scheme, failed: true),
          );

    if (shouldBlur) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: image,
      );
    }

    final child = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (shouldBlur)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                  ),
                ),
              ),
            if (shouldBlur && widget.showRevealButton)
              Center(
                child: _RevealButton(
                  onTap: () => setState(() => _revealed = true),
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.onTap == null) return child;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }

  Widget _placeholder(ColorScheme scheme, {bool failed = false}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppDecor.placeholderGradient(scheme, widget.seedId),
      ),
      child: Center(
        child: Icon(
          failed ? Icons.broken_image_outlined : Icons.graphic_eq_rounded,
          color: Colors.white.withValues(alpha: 0.75),
          size: 32,
        ),
      ),
    );
  }
}

class _RevealButton extends StatelessWidget {
  const _RevealButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.visibility_outlined, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// 微光骨架屏方块。
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.radius = 12,
    this.aspectRatio,
  });

  final double? width;
  final double? height;
  final double radius;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (aspectRatio != null) {
      box = AspectRatio(aspectRatio: aspectRatio!, child: box);
    }
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHigh,
      highlightColor: dark ? const Color(0xFF2E2739) : const Color(0xFFF4F2FA),
      child: box,
    );
  }
}

/// 网格骨架屏。
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({super.key, this.columns = 2, this.count = 6});

  final int columns;
  final int count;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: count,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(child: ShimmerBox(aspectRatio: 1, radius: 18)),
          SizedBox(height: 10),
          ShimmerBox(height: 12, radius: 6),
          SizedBox(height: 6),
          ShimmerBox(height: 12, width: 70, radius: 6),
        ],
      ),
    );
  }
}

/// 通用错误提示。
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: compact ? 24 : 30, color: scheme.error),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(L10n.of(context)('common.retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 通用空状态。
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 46,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// 列表 / 网格底部加载指示器。
class LoadMoreIndicator extends StatelessWidget {
  const LoadMoreIndicator({
    super.key,
    required this.loading,
    required this.hasMore,
    this.noMoreText,
  });

  final bool loading;
  final bool hasMore;
  final String? noMoreText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Text(
                hasMore ? '' : (noMoreText ?? ''),
                style: Theme.of(context).textTheme.labelSmall,
              ),
      ),
    );
  }
}

/// 小节标题，右侧可带一个操作按钮。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.action,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (action != null) Text(action!),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 评分徽标（含星标）。
class RatingBadge extends StatelessWidget {
  const RatingBadge({
    super.key,
    required this.rating,
    this.count,
    this.compact = false,
  });

  final double rating;
  final int? count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();
    const amber = Color(0xFFFFB300);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 14, color: amber),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1),
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: amber, fontWeight: FontWeight.w700),
        ),
        if (count != null && !compact) ...[
          const SizedBox(width: 4),
          Text('(${count!})', style: Theme.of(context).textTheme.labelSmall),
        ],
      ],
    );
  }
}

/// 18 禁 / 全年龄角标。
class AgeBadge extends StatelessWidget {
  const AgeBadge({super.key, required this.nsfw, this.label});

  final bool nsfw;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = nsfw ? const Color(0xFFE05B6B) : scheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Text(
        label ?? (nsfw ? 'R18' : 'ALL'),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 自适应换行的标签组。
class TagWrap extends StatelessWidget {
  const TagWrap({
    super.key,
    required this.labels,
    this.onTap,
    this.selected = const {},
    this.maxLines,
    this.dense = false,
  });

  final List<String> labels;
  final void Function(String label, int index)? onTap;
  final Set<String> selected;
  final int? maxLines;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visible = maxLines == null
        ? labels
        : labels.take(maxLines!).toList(growable: false);
    return Wrap(
      spacing: dense ? 6 : 8,
      runSpacing: dense ? 6 : 8,
      children: [
        for (var i = 0; i < visible.length; i++)
          _TagChip(
            label: visible[i],
            selected: selected.contains(visible[i]),
            dense: dense,
            onTap: onTap == null ? null : () => onTap!(visible[i], i),
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.dense,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.92)
          : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 10 : 12,
            vertical: dense ? 5 : 7,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              fontSize: dense ? 11 : 12,
            ),
          ),
        ),
      ),
    );
  }
}
