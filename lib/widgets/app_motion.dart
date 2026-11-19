import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const quick = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 200);

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

class MotionFade extends StatelessWidget {
  const MotionFade({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSwitcher(duration: AppMotion.standard, child: child);
}

class CoverHero extends StatelessWidget {
  const CoverHero({super.key, required this.tag, required this.child});
  final Object? tag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (tag == null || MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(tag: tag!, transitionOnUserGestures: true, child: child);
  }
}

class PlayPauseGlyph extends StatelessWidget {
  const PlayPauseGlyph({
    super.key,
    required this.playing,
    this.size,
    this.color,
  });
  final bool playing;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: playing ? 1.0 : 0.0),
    duration: AppMotion.duration(context, AppMotion.quick),
    builder: (_, value, _) => AnimatedIcon(
      icon: AnimatedIcons.play_pause,
      progress: AlwaysStoppedAnimation(value),
      size: size,
      color: color,
    ),
  );
}

/// 同一批首屏内容共用时间轴，滚回已构建过的行时保持其最终状态。
class FeedEntrance extends StatefulWidget {
  const FeedEntrance({super.key, required this.builder});
  final Widget Function(Widget Function(int row, Widget child) entrance)
  builder;

  @override
  State<FeedEntrance> createState() => _FeedEntranceState();
}

class _FeedEntranceState extends State<FeedEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 248),
  );
  late final _rows = List.generate(
    3,
    (row) => _controller.drive(
      CurveTween(
        curve: Interval(
          row * 24 / 248,
          (row * 24 + 200) / 248,
          curve: Curves.easeOut,
        ),
      ),
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return widget.builder(
      (row, child) => reduced || row >= _rows.length
          ? child
          : FadeTransition(opacity: _rows[row], child: child),
    );
  }
}
