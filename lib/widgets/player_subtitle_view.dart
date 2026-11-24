import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/models/subtitle.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../state/listening_notes.dart';
import '../state/player_state.dart';
import 'app_motion.dart';

/// Bounded-height scrolling subtitle panel embedded in [PlayerScreen].
///
/// Subscribes directly to [PlayerState.player]'s position stream so position
/// updates only rebuild this panel and never the outer player layout.
class PlayerSubtitleView extends StatefulWidget {
  const PlayerSubtitleView({
    super.key,
    required this.player,
    required this.notes,
    required this.onOpenReplace,
  });

  final PlayerState player;
  final ListeningNotes notes;
  final VoidCallback onOpenReplace;

  @override
  State<PlayerSubtitleView> createState() => _PlayerSubtitleViewState();
}

class _PlayerSubtitleViewState extends State<PlayerSubtitleView> {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _cueKeys = {};
  bool _follow = true;
  int _lastActive = -1;
  String? _boundKey;
  List<SubtitleCue> _boundCues = const [];
  int _scrollToken = 0;

  @override
  void initState() {
    super.initState();
    _boundKey = widget.notes.key;
    _boundCues = widget.notes.cues;
  }

  @override
  void didUpdateWidget(covariant PlayerSubtitleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final trackChanged = widget.notes.key != _boundKey;
    final cuesChanged = !identical(widget.notes.cues, _boundCues);
    if (trackChanged || cuesChanged) {
      _boundKey = widget.notes.key;
      _boundCues = widget.notes.cues;
      _follow = true;
      _lastActive = -1;
      _cueKeys.clear();
      _scrollToken++;
      if (_scroll.hasClients && widget.notes.cues.isNotEmpty) {
        final active = Subtitles.activeIndex(
          widget.notes.cues,
          widget.player.player.position.inMilliseconds,
          offsetMs: widget.notes.offsetMs,
        );
        if (active < 0) {
          _scroll.jumpTo(0);
        }
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleScrollTo(int index, {required bool animate}) {
    if (index < 0 || index >= widget.notes.cues.length) return;
    final token = ++_scrollToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _scrollToken || !_scroll.hasClients) return;
      final targetCtx = _cueKeys[index]?.currentContext;
      if (targetCtx != null) {
        Scrollable.ensureVisible(
          targetCtx,
          alignment: 0.5,
          duration: animate
              ? AppMotion.duration(targetCtx, AppMotion.standard)
              : Duration.zero,
          curve: Curves.easeOut,
        );
        return;
      }
      final maxExtent = _scroll.position.maxScrollExtent;
      if (maxExtent > 0 && widget.notes.cues.length > 1) {
        final approx = maxExtent * (index / (widget.notes.cues.length - 1));
        _scroll.jumpTo(approx.clamp(0.0, maxExtent));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || token != _scrollToken) return;
          final retryCtx = _cueKeys[index]?.currentContext;
          if (retryCtx != null) {
            Scrollable.ensureVisible(
              retryCtx,
              alignment: 0.5,
              duration: animate
                  ? AppMotion.duration(retryCtx, AppMotion.standard)
                  : Duration.zero,
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  int _nearestCueIndex(List<SubtitleCue> cues, int positionMs, int offsetMs) {
    final active = Subtitles.activeIndex(cues, positionMs, offsetMs: offsetMs);
    if (active >= 0) return active;
    final time = positionMs - offsetMs;
    for (var i = 0; i < cues.length; i++) {
      if (cues[i].text.isNotEmpty && cues[i].startMs >= time) return i;
    }
    for (var i = cues.length - 1; i >= 0; i--) {
      if (cues[i].text.isNotEmpty) return i;
    }
    return -1;
  }

  void _resumeFollow() {
    final cues = widget.notes.cues;
    final target = _nearestCueIndex(
      cues,
      widget.player.player.position.inMilliseconds,
      widget.notes.offsetMs,
    );
    setState(() {
      _follow = true;
      _lastActive = target;
    });
    if (target >= 0) {
      _scheduleScrollTo(target, animate: true);
    }
  }

  void _seekToCue(int index, SubtitleCue cue) {
    final targetMs = (cue.startMs + widget.notes.offsetMs).clamp(0, 1 << 40);
    widget.player.seek(Duration(milliseconds: targetMs));
    setState(() {
      _follow = true;
      _lastActive = index;
    });
    _scheduleScrollTo(index, animate: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notes = widget.notes;
    final l = L10n.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: _buildBody(context, notes, l),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ListeningNotes notes, L10n l) {
    switch (notes.subtitleStatus) {
      case SubtitleStatus.idle:
      case SubtitleStatus.loading:
        return _StatusPanel(
          icon: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          message: l('subtitle.matching'),
        );

      case SubtitleStatus.empty:
        return _StatusPanel(
          icon: Icon(
            Icons.subtitles_off_outlined,
            size: 28,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          message: l('subtitle.empty'),
          actions: [
            OutlinedButton.icon(
              onPressed: widget.onOpenReplace,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(l('notes.replaceSubtitle')),
            ),
          ],
        );

      case SubtitleStatus.ambiguous:
        return _StatusPanel(
          icon: Icon(
            Icons.subtitles_outlined,
            size: 28,
            color: Theme.of(context).colorScheme.primary,
          ),
          message: l('subtitle.ambiguous'),
          actions: [
            FilledButton.tonalIcon(
              onPressed: widget.onOpenReplace,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(l('notes.replaceSubtitle')),
            ),
          ],
        );

      case SubtitleStatus.offlineEmpty:
        return _StatusPanel(
          icon: Icon(
            Icons.cloud_off_outlined,
            size: 28,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          message: l('subtitle.offlineEmpty'),
          actions: [
            OutlinedButton.icon(
              onPressed: widget.onOpenReplace,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(l('notes.replaceSubtitle')),
            ),
            TextButton.icon(
              onPressed: notes.retrySubtitle,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l('common.retry')),
            ),
          ],
        );

      case SubtitleStatus.networkError:
        return _StatusPanel(
          icon: Icon(
            Icons.wifi_off_rounded,
            size: 28,
            color: Theme.of(context).colorScheme.error,
          ),
          message: l('subtitle.networkError'),
          actions: [
            FilledButton.tonalIcon(
              onPressed: notes.retrySubtitle,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l('common.retry')),
            ),
            TextButton.icon(
              onPressed: widget.onOpenReplace,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(l('notes.replaceSubtitle')),
            ),
          ],
        );

      case SubtitleStatus.parseError:
        return _StatusPanel(
          icon: Icon(
            Icons.error_outline_rounded,
            size: 28,
            color: Theme.of(context).colorScheme.error,
          ),
          message: l('subtitle.parseError'),
          actions: [
            FilledButton.tonalIcon(
              onPressed: widget.onOpenReplace,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(l('notes.replaceSubtitle')),
            ),
            TextButton.icon(
              onPressed: notes.retrySubtitle,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l('common.retry')),
            ),
          ],
        );

      case SubtitleStatus.loaded:
        final cues = notes.cues;
        if (cues.isEmpty) {
          return _StatusPanel(
            icon: Icon(
              Icons.subtitles_off_outlined,
              size: 28,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            message: l('subtitle.empty'),
            actions: [
              OutlinedButton.icon(
                onPressed: widget.onOpenReplace,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(l('notes.replaceSubtitle')),
              ),
            ],
          );
        }

        return StreamBuilder<Duration>(
          initialData: widget.player.player.position,
          stream: widget.player.player.positionStream,
          builder: (context, snapshot) {
            final posMs =
                (snapshot.data ?? widget.player.player.position).inMilliseconds;
            final active = Subtitles.activeIndex(
              cues,
              posMs,
              offsetMs: notes.offsetMs,
            );
            final activeVisible = active >= 0 && cues[active].text.isNotEmpty
                ? active
                : -1;

            if (_follow && activeVisible >= 0 && activeVisible != _lastActive) {
              final animate = _lastActive >= 0;
              _lastActive = activeVisible;
              _scheduleScrollTo(activeVisible, animate: animate);
            } else if (_follow && activeVisible < 0 && _lastActive >= 0) {
              _lastActive = -1;
            }

            final scheme = Theme.of(context).colorScheme;
            return Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    final isUserDrag =
                        (notification is UserScrollNotification &&
                            notification.direction != ScrollDirection.idle) ||
                        (notification is ScrollStartNotification &&
                            notification.dragDetails != null);
                    if (isUserDrag && _follow) {
                      setState(() => _follow = false);
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      12,
                      12,
                      _follow ? 16 : 56,
                    ),
                    itemCount: cues.length,
                    itemBuilder: (context, i) {
                      final cue = cues[i];
                      if (cue.text.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final key = _cueKeys.putIfAbsent(i, GlobalKey.new);
                      final isActive = i == activeVisible;
                      return Padding(
                        key: key,
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          animateColor: true,
                          animationDuration: AppMotion.duration(
                            context,
                            AppMotion.quick,
                          ),
                          color: isActive
                              ? scheme.primaryContainer
                              : scheme.surface.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _seekToCue(i, cue),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    Fmt.position(
                                      Duration(milliseconds: cue.startMs),
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: isActive
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    cue.text,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontSize: 15,
                                          height: 1.45,
                                          fontWeight: isActive
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: isActive
                                              ? scheme.onPrimaryContainer
                                              : scheme.onSurface.withValues(
                                                  alpha: 0.85,
                                                ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!_follow)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: Center(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        onPressed: _resumeFollow,
                        icon: const Icon(Icons.my_location_rounded, size: 16),
                        label: Text(l('player.backToCurrentLine')),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
    }
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.message,
    this.actions = const [],
  });

  final Widget icon;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
