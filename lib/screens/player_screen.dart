import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:provider/provider.dart';

import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/player_state.dart';
import '../state/settings_state.dart';
import '../widgets/common.dart';

/// 全屏播放器。
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final player = context.watch<PlayerState>();
    final item = player.currentItem;
    final scheme = Theme.of(context).colorScheme;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyView(
          message: l('player.nothing'),
          icon: Icons.music_note_outlined,
          action: Text(l('player.nothingHint')),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l('player.title')),
        actions: [
          IconButton(
            tooltip: l('player.queue'),
            onPressed: _openQueue,
            icon: const Icon(Icons.queue_music_rounded),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 背景：封面放大 + 模糊，营造氛围感。
          CoverImage(url: item.coverUrl, seedId: item.workId, radius: 0),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.86),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 8, 26, 20),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.34,
                    child: CoverImage(
                      url: item.coverUrl,
                      seedId: item.workId,
                      radius: 24,
                    ),
                  ),
                  const Spacer(flex: 2),
                  Text(
                    item.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.folderLabel.isEmpty
                        ? item.workTitle
                        : '${item.workTitle} · ${item.folderLabel}',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 22),
                  _ProgressBar(
                    player: player,
                    dragValue: _dragValue,
                    onDrag: (v) => setState(() => _dragValue = v),
                    onDragEnd: (v) {
                      final total = player.player.duration;
                      if (total != null && total.inMilliseconds > 0) {
                        player.seek(
                          Duration(
                            milliseconds: (total.inMilliseconds * v).round(),
                          ),
                        );
                      }
                      setState(() => _dragValue = null);
                    },
                  ),
                  const SizedBox(height: 8),
                  _Controls(player: player),
                  const Spacer(),
                  _BottomActions(player: player),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openQueue() async {
    final player = context.read<PlayerState>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<PlayerState>.value(
        value: player,
        child: const _QueueSheet(),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.player,
    required this.dragValue,
    required this.onDrag,
    required this.onDragEnd,
  });

  final PlayerState player;
  final double? dragValue;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: player.player.durationStream,
          builder: (context, durationSnap) {
            final total = durationSnap.data ?? Duration.zero;
            final totalMs = total.inMilliseconds;
            final ratio = totalMs <= 0
                ? 0.0
                : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
            final value = dragValue ?? ratio;
            final shown = totalMs <= 0
                ? Duration.zero
                : Duration(milliseconds: (totalMs * value).round());

            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                  ),
                  child: Slider(
                    value: value,
                    onChanged: onDrag,
                    onChangeEnd: onDragEnd,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        Fmt.position(shown),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        Fmt.position(total),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: player.toggleShuffle,
          iconSize: 24,
          color: player.shuffleEnabled
              ? scheme.primary
              : scheme.onSurfaceVariant,
          icon: const Icon(Icons.shuffle_rounded),
        ),
        IconButton(
          onPressed: player.previous,
          iconSize: 38,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        StreamBuilder<ja.PlayerState>(
          stream: player.player.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? player.playing;
            return Material(
              color: scheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: player.toggle,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 34,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            );
          },
        ),
        IconButton(
          onPressed: player.hasNext ? player.next : null,
          iconSize: 38,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          onPressed: player.cycleLoopMode,
          iconSize: 24,
          color: player.loopMode == ja.LoopMode.off
              ? scheme.onSurfaceVariant
              : scheme.primary,
          icon: Icon(switch (player.loopMode) {
            ja.LoopMode.off => Icons.repeat_rounded,
            ja.LoopMode.all => Icons.repeat_rounded,
            ja.LoopMode.one => Icons.repeat_one_rounded,
          }),
        ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _PillButton(
          icon: Icons.speed_rounded,
          label:
              '${player.speed.toStringAsFixed(player.speed == player.speed.roundToDouble() ? 0 : 1)}x',
          onTap: () => _showSpeedSheet(context, player),
        ),
        _PillButton(
          icon: Icons.bedtime_outlined,
          label: player.stopAfterTrack
              ? l('player.stopAfterTrack')
              : player.sleepDeadline == null
              ? l('player.sleep')
              : '${player.sleepRemaining.inMinutes}m',
          active: player.sleepDeadline != null || player.stopAfterTrack,
          onTap: () => _showSleepSheet(context, player),
        ),
        _PillButton(
          icon: Icons.high_quality_outlined,
          label: context.watch<SettingsState>().preferLowQuality ? 'LQ' : 'HQ',
          onTap: () {
            final s = context.read<SettingsState>();
            s.preferLowQuality = !s.preferLowQuality;
          },
        ),
      ],
    );
  }

  Future<void> _showSpeedSheet(BuildContext context, PlayerState player) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                L10n.of(sheetContext)('player.speed'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final v in const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
              ListTile(
                leading: Icon(
                  player.speed == v
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: player.speed == v
                      ? Theme.of(sheetContext).colorScheme.primary
                      : null,
                ),
                title: Text('${v}x'),
                onTap: () {
                  player.setSpeed(v);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showSleepSheet(BuildContext context, PlayerState player) async {
    final l = L10n.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l('player.sleep'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_off_outlined),
              title: Text(l('player.sleepOff')),
              onTap: () {
                player.clearSleepTimer();
                Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.music_off),
              title: Text(l('player.stopAfterTrack')),
              onTap: () {
                player.setStopAfterTrack(true);
                Navigator.of(sheetContext).pop();
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(l('player.fadeHint')),
            ),
            for (final m in const [15, 30, 45, 60, 90])
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: Text(l('player.sleepIn', {'n': m})),
                onTap: () {
                  player.setSleepTimer(m);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 播放队列面板。
class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final player = context.watch<PlayerState>();
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Text(
                  l('player.queue'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: 10),
                Text(
                  '${player.queue.length}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: player.stop,
                  child: Text(l('common.close')),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: player.queue.length,
              itemBuilder: (context, i) {
                final item = player.queue[i];
                final isCurrent = i == player.currentIndex;
                return ListTile(
                  selected: isCurrent,
                  selectedTileColor: scheme.primary.withValues(alpha: 0.1),
                  leading: Icon(
                    isCurrent
                        ? Icons.graphic_eq_rounded
                        : Icons.music_note_outlined,
                    color: isCurrent ? scheme.primary : null,
                  ),
                  title: Text(
                    Fmt.stripExt(item.title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent ? scheme.primary : null,
                    ),
                  ),
                  subtitle: item.folderLabel.isEmpty
                      ? null
                      : Text(
                          item.folderLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => player.removeFromQueue(i),
                  ),
                  onTap: () => player.seekToIndex(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
