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
