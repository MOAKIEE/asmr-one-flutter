import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_motion.dart';
import '../widgets/player_scaffold.dart';
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

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: AppMotion.quick,
    value: 1,
  );

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  int _index = 0;
  static const _pages = [
    HomeScreen(),
    BrowseScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return PlayerScaffold(
      body: FadeTransition(
        opacity: MediaQuery.disableAnimationsOf(context)
            ? const AlwaysStoppedAnimation(1)
            : _fade,
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _pages.length; i++)
              TickerMode(enabled: i == _index, child: _pages[i]),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (i == _index) return;
            setState(() => _index = i);
            if (!MediaQuery.disableAnimationsOf(context)) {
              _fade.forward(from: 0);
            }
          },
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
      ),
    );
  }
}
