import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/player_state.dart';
import 'app_motion.dart';
import 'mini_player.dart';

/// 在路由内为播放条和底部导航分配空间。
class PlayerScaffold extends StatefulWidget {
  const PlayerScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  @override
  State<PlayerScaffold> createState() => _PlayerScaffoldState();
}

class _PlayerScaffoldState extends State<PlayerScaffold> {
  PlayItem? _lastItem;

  @override
  Widget build(BuildContext context) {
    final item = context.select<PlayerState?, PlayItem?>(
      (player) => player?.currentItem,
    );
    if (item != null) _lastItem = item;
    return Scaffold(
      appBar: widget.appBar,
      body: widget.body,
      floatingActionButton: widget.floatingActionButton,
      bottomNavigationBar:
          _lastItem == null && widget.bottomNavigationBar == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_lastItem != null)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: item == null ? 0 : 1),
                    duration: AppMotion.duration(context, AppMotion.standard),
                    curve: Curves.easeOutCubic,
                    onEnd: () {
                      if (context.read<PlayerState?>()?.currentItem == null) {
                        setState(() => _lastItem = null);
                      }
                    },
                    child: IgnorePointer(
                      ignoring: item == null,
                      child: SafeArea(
                        top: false,
                        bottom: widget.bottomNavigationBar == null,
                        child: MiniPlayer(item: _lastItem),
                      ),
                    ),
                    builder: (_, value, child) => ClipRect(
                      child: Align(
                        heightFactor: value,
                        alignment: Alignment.bottomCenter,
                        child: Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 8 * (1 - value)),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ?widget.bottomNavigationBar,
              ],
            ),
    );
  }
}
