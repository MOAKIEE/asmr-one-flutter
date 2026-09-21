import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../screens/player_screen.dart';
import '../state/player_state.dart';
import 'common.dart';

/// 悬浮在页面底部的迷你播放条。
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final item = player.currentItem;
    if (item == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Material(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PlayerScreen())),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: CoverImage(
                        url: item.coverUrl,
                        seedId: item.workId,
                        radius: 11,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.workTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    _ControlButton(
                      icon: Icons.skip_previous_rounded,
                      onTap: player.previous,
                    ),
                    _ControlButton(
                      icon: player.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      big: true,
                      onTap: player.toggle,
                    ),
                    _ControlButton(
                      icon: Icons.skip_next_rounded,
                      onTap: player.hasNext ? player.next : null,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: L10n.of(context)('common.close'),
                      onPressed: player.stop,
                    ),
                  ],
                ),
              ),
              _ProgressLine(player: player),
            ],
          ),
        ),
      ),
    );
  }
}

/// 迷你播放条底部的细进度线。
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 2.5,
      child: StreamBuilder<Duration>(
        stream: player.player.positionStream,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final total = player.player.duration ?? Duration.zero;
          final ratio = total.inMilliseconds <= 0
              ? 0.0
              : (position.inMilliseconds / total.inMilliseconds).clamp(
                  0.0,
                  1.0,
                );
          return LinearProgressIndicator(
            value: ratio,
            minHeight: 2.5,
            backgroundColor: scheme.surfaceContainerHighest,
          );
        },
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, this.onTap, this.big = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      iconSize: big ? 32 : 24,
      color: onTap == null
          ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
          : (big ? scheme.primary : scheme.onSurface),
      icon: Icon(icon),
    );
  }
}
