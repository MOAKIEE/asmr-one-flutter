import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/player_state.dart';
import 'browse_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'search_screen.dart';

/// 底部导航容器：首页 / 浏览 / 搜索 / 我的。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _playerBarHeight = 82.0;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final hasPlayer = context.select<PlayerState, bool>((p) => p.hasQueue);

    return Scaffold(
      body: Padding(
        // 给悬浮的迷你播放条留出空间，避免遮挡列表末尾内容。
        padding: EdgeInsets.only(bottom: hasPlayer ? _playerBarHeight : 0),
        child: IndexedStack(
          index: _index,
          children: const [
            HomeScreen(),
            BrowseScreen(),
            SearchScreen(),
            LibraryScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome_rounded),
            label: l('nav.home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view_rounded),
            label: l('nav.browse'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.search_outlined),
            selectedIcon: const Icon(Icons.search_rounded),
            label: l('nav.search'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: l('nav.library'),
          ),
        ],
      ),
    );
  }
}
