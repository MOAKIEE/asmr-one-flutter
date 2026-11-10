import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/player_state.dart';
import 'mini_player.dart';

/// 在路由内为播放条和底部导航分配空间。
class PlayerScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final hasPlayer = context.select<PlayerState?, bool>(
      (player) => player?.hasQueue ?? false,
    );
    return Scaffold(
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: hasPlayer || bottomNavigationBar != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasPlayer)
                  SafeArea(
                    top: false,
                    bottom: bottomNavigationBar == null,
                    child: const MiniPlayer(),
                  ),
                ?bottomNavigationBar,
              ],
            )
          : null,
    );
  }
}
